defmodule Cadence.Control.ActivationAuthorSeparationTest do
  @moduledoc """
  Board #236: approving a spacecraft configuration activation needs an approver who is neither the
  requester nor ANY author of the configuration being activated (for each spacecraft, everyone who
  saved a version after its active configuration, up to and including the reviewed one), wherever
  the approval policy requires an independent approver. Before, only the requester was excluded,
  so A could write a draft, B submit it, and A approve their own content.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.{
    Active,
    Authors,
    Drafts,
    Review,
    RevisionRow
  }

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth
  alias Cadence.Auth.{ServiceAccountableRow, ServiceIdentity}
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

  describe "#280: a version saved under a service identity's id (a change set's applier)" do
    # Drafts.derive writes the change set applier's id as `created_by`, and that can be a service
    # identity's (api-ops' cross-PR item on #435). Here B's saved version is re-stamped as if a
    # service had applied it: the stand-in for derive's write, on the test database only.
    setup c do
      save(c, c.b, c.craft, [42])

      %{
        service: issue_service!(c, "Config applier", c.a),
        revision_id: latest_revision_id(c)
      }
    end

    test "the service's accountable person (its issuer) can't approve; someone else can", c do
      restamp!(c.revision_id, c.service.service_identity_id)
      {:ok, request} = submit(c, c.b, [c.craft])
      id = c.craft.spacecraft_id

      assert {:error, {:activation_approver_authored_content, [^id]}} = approve(c.a, request)
      assert {:ok, _request, _decision, _approved} = approve(c.c, request)
    end

    test "a service with nobody on record refuses everyone, naming the service", c do
      legacy = c.service.service_identity_id

      Repo.delete_all(
        from(row in ServiceAccountableRow, where: row.service_identity_id == ^legacy)
      )

      restamp!(c.revision_id, legacy)
      {:ok, request} = submit(c, c.b, [c.craft])

      for approver <- [c.a, c.c] do
        assert {:error,
                {:activation_approver_authors_unknown,
                 %{service: %{id: ^legacy, name: "Config applier"}}}} = approve(approver, request)
      end
    end
  end

  # #439 (mms-engineer, api-ops): the author check reads which authors are service identities in
  # one query, so approving costs the same whether one person or several saved the reviewed craft.
  # The whole approve is counted, with the craft count held equal (per-craft work elsewhere in
  # approve, like the preflight, is #434's own bound).
  test "the whole approve costs the same queries for one author as for several" do
    one = approve_queries(fn _n -> "author-same" end)
    several = approve_queries(fn n -> "author-#{n}" end)

    assert one == several
  end

  # A fresh mission with three craft; craft n is saved by `author.(n)`, B submits all three, and C
  # approves (allowed: C saved nothing). Returns the approve's query count.
  defp approve_queries(author) do
    org = "org-author-q-#{System.unique_integer([:positive])}"
    mid = "mission-author-q-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    c = %{org: org, mission: mission, catalog: revision.catalog_revision_id}
    admin = Fixtures.user_scope(org, "policy-admin")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(admin, mid, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })

    crafts =
      for n <- 2..3, reduce: [craft] do
        acc ->
          other = Fixtures.persist_spacecraft!(org, mid, display_name: "Craft #{n}")

          Fixtures.persist_source_endpoint!(org, mid, other.spacecraft_id,
            display_name: "TT&C #{n}"
          )

          acc ++ [other]
      end

    crafts
    |> Enum.with_index(1)
    |> Enum.each(fn {each, n} -> save(c, named_scope(org, author.(n)), each, [42]) end)

    {:ok, request} = submit(c, Fixtures.user_scope(org, "submitter-b"), crafts)
    approver = Fixtures.user_scope(org, "approver-c")

    {queries, result} = count_queries(fn -> approve(approver, request) end)
    assert {:ok, _request, _decision, _approved} = result
    queries
  end

  defp named_scope(org, user_id) do
    scope = Fixtures.user_scope(org, "unused")
    %{scope | user: %{scope.user | user_id: user_id}}
  end

  defp issue_service!(c, name, issued_by) do
    identity =
      ServiceIdentity.new(%{
        organization_id: c.org,
        mission_id: c.mission.mission_id,
        display_name: name,
        capabilities: [:mission_admin]
      })

    {:ok, %{service_identity: service}} = Auth.issue_service_identity(identity, issued_by)
    service
  end

  defp latest_revision_id(c) do
    craft = c.craft.spacecraft_id

    from(row in RevisionRow,
      where: row.spacecraft_id == ^craft,
      order_by: [desc: row.version],
      limit: 1,
      select: row.configuration_revision_id
    )
    |> Repo.one!()
  end

  defp restamp!(revision_id, by) do
    {1, _} =
      from(row in RevisionRow, where: row.configuration_revision_id == ^revision_id)
      |> Repo.update_all(set: [created_by: by])
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
