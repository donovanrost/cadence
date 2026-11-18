defmodule Cadence.Control.ActivationAuthorSeparationTest do
  @moduledoc """
  Board #236: approving a spacecraft configuration activation needs an approver who is neither the
  requester nor ANY author of the configuration being activated (for each spacecraft, everyone who
  saved a version after its active configuration, up to and including the reviewed one), wherever
  the approval policy requires an independent approver. Before, only the requester was excluded,
  so A could write a draft, B submit it, and A approve their own content.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{
    Active,
    Authors,
    Drafts,
    Review,
    RevisionRow
  }

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow

  setup do
    org = "org-author-sep-#{System.unique_integer([:positive])}"
    mid = "mission-author-sep-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    a = Fixtures.user_scope(org, "author-a")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(a, mid, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    %{
      org: org,
      mission: mission,
      craft: craft,
      catalog: revision.catalog_revision_id,
      a: a,
      b: Fixtures.user_scope(org, "submitter-b"),
      c: Fixtures.user_scope(org, "approver-c")
    }
  end

  test "an author of the configuration can't approve its activation, even if someone else submitted it",
       c do
    save(c, c.a, c.craft, [42])
    save(c, c.b, c.craft, [42])
    {:ok, request} = submit(c, c.b, [c.craft])
    assert request.state == :approval_pending
    id = c.craft.spacecraft_id

    assert {:error, {:activation_approver_authored_content, [^id]}} = approve(c.a, request)

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(c.c, request.activation_request_id)

    assert {:ok, _request, _decision, _approved} = approve(c.c, request)
  end

  test "a fleet review names only the spacecraft the approver authored", c do
    other = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Second")

    Fixtures.persist_source_endpoint!(c.org, c.mission.mission_id, other.spacecraft_id,
      display_name: "Second TT&C"
    )

    save(c, c.a, c.craft, [42])
    save(c, c.b, other, [42])
    {:ok, request} = submit(c, c.b, [c.craft, other])
    id = c.craft.spacecraft_id

    assert {:error, {:activation_approver_authored_content, [^id]}} = approve(c.a, request)
    assert {:ok, _request, _decision, _approved} = approve(c.c, request)
  end

  test "authors fail closed: a review whose version can't be found can't be approved by anyone",
       c do
    review = %{
      "configuration_review" => %{
        "spacecraft_id" => c.craft.spacecraft_id,
        "configuration_revision_id" => "no-such-revision",
        "configuration_token" => "x",
        "base_activation_id" => nil
      }
    }

    id = c.craft.spacecraft_id

    assert {:error, {:activation_approver_authors_unknown, [^id]}} =
             Authors.by_spacecraft(c.mission, review)

    assert {:ok, %{}} =
             Authors.by_spacecraft(c.mission, %{})
  end

  test "authors count only after EACH craft's active version: an author of an active one may approve the next",
       c do
    save(c, c.a, c.craft, [42])
    {:ok, first} = submit(c, c.b, [c.craft])

    assert {:ok, %{status: :succeeded}} =
             ControlActivations.approve_and_execute(c.c, first.activation_request_id, "Reviewed")

    assert {:ok, active} = Active.load(c.mission)
    assert active.entries[c.craft.spacecraft_id]["configuration_version"] == 1

    # A second craft with nothing active, so the fleet's floors are mixed (1 and 0): the authors
    # query reads from the lowest floor, and each craft's own floor must still apply.
    other = Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Second")

    Fixtures.persist_source_endpoint!(c.org, c.mission.mission_id, other.spacecraft_id,
      display_name: "Second TT&C"
    )

    save(c, c.b, c.craft, [42])
    save(c, c.b, other, [42])
    {:ok, second} = submit(c, c.c, [c.craft, other])
    ids = Enum.sort([c.craft.spacecraft_id, other.spacecraft_id])

    # B saved the reviewed version of both craft: B authored them and can't approve.
    assert {:error, {:activation_approver_authored_content, ^ids}} = approve(c.b, second)
    # A saved only the first craft's ACTIVE version 1, which isn't in this review: A may approve.
    assert {:ok, _request, _decision, _approved} = approve(c.a, second)
  end

  test "a 500-craft fleet review reads its authors in two queries, each craft in its own window",
       c do
    now = DateTime.utc_now()
    mid = c.mission.mission_id
    ids = for n <- 1..500, do: "fleet-#{System.unique_integer([:positive])}-#{n}"

    Repo.insert_all(
      SpacecraftRow,
      Enum.map(
        ids,
        &%{
          spacecraft_id: &1,
          organization_id: c.org,
          mission_id: mid,
          display_name: &1,
          metadata: %{},
          inserted_at: now
        }
      )
    )

    revision = fn id, version, by ->
      %{
        configuration_revision_id: "#{id}-v#{version}",
        organization_id: c.org,
        mission_id: mid,
        spacecraft_id: id,
        version: version,
        document: %{},
        content_sha256: "x",
        application_basis: "x",
        created_by: by,
        inserted_at: now
      }
    end

    Repo.insert_all(
      RevisionRow,
      Enum.flat_map(ids, &[revision.(&1, 1, "fleet-a"), revision.(&1, 2, "fleet-b")])
    )

    # Even craft are reviewed at version 2 (both saved), odd ones at version 1 (only A had).
    reviewed =
      ids
      |> Enum.with_index()
      |> Map.new(fn {id, i} -> {id, if(rem(i, 2) == 0, do: 2, else: 1)} end)

    metadata = %{
      "configuration_review" => %{
        "base_activation_id" => nil,
        "spacecraft_reviews" =>
          Map.new(reviewed, fn {id, v} ->
            {id, %{"configuration_revision_id" => "#{id}-v#{v}"}}
          end)
      }
    }

    {queries, result} = count_queries(fn -> Authors.by_spacecraft(c.mission, metadata) end)
    assert {:ok, authors} = result
    assert map_size(authors) == 500

    for {id, v} <- reviewed do
      expected = if v == 2, do: ["fleet-a", "fleet-b"], else: ["fleet-a"]
      assert Enum.sort(authors[id]) == expected
    end

    # Active.load's own read(s) plus Authors' two, whatever the fleet size.
    assert queries <= 4
  end

  defp count_queries(fun) do
    ref = make_ref()
    me = self()
    handler = "author-queries-#{inspect(ref)}"

    # The handler runs in the querying process: count only this test's own queries, not those of
    # other processes running meanwhile.
    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _cfg -> if self() == me, do: send(me, {:query, ref}) end,
      nil
    )

    try do
      result = fun.()
      {drain(ref, 0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, n) do
    receive do
      {:query, ^ref} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end

  defp save(c, scope, craft, apids) do
    current = Drafts.snapshot(c.mission, craft)

    document =
      SpacecraftConfigurationInput.empty()
      |> Map.merge(%{
        "catalog_revision_id" => c.catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => apids
      })

    :ok =
      Fixtures.change_set_switches!(c.org, c.mission.mission_id, craft.spacecraft_id, document)

    {:ok, _} =
      Drafts.save(
        scope,
        c.mission.mission_id,
        craft.spacecraft_id,
        current.token,
        document
      )
  end

  defp submit(c, scope, crafts) do
    tokens = Map.new(crafts, &{&1.spacecraft_id, Drafts.snapshot(c.mission, &1).token})
    Review.request_many(scope, c.mission.mission_id, tokens)
  end

  defp approve(scope, request),
    do: ControlActivations.approve(scope, request.activation_request_id, "Reviewed")
end
