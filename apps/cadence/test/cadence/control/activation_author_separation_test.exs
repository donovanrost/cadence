defmodule Cadence.Control.ActivationAuthorSeparationTest do
  @moduledoc """
  Board #236: approving a spacecraft configuration activation needs an approver who is neither the
  requester nor ANY author of the configuration being activated (for each spacecraft, everyone who
  saved a version after its active configuration, up to and including the reviewed one), wherever
  the approval policy requires an independent approver. Before, only the requester was excluded,
  so A could write a draft, B submit it, and A approve their own content.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Authors, Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

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
