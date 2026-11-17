defmodule Cadence.MissionModels.FirstRevisionTest do
  @moduledoc """
  A mission's first model revision, end to end (lead's gate finding 11-17; domain 062d93e87 + api):
  with no configuration yet there's no binding set and nothing earlier, so the console's compare
  runs against nothing (`against` null, replay not run), its importer is refused under
  'independent' approval, another administrator approves, and the per-spacecraft configuration
  then introduces it (a mission's first generation; a change set builds one only over an active
  one). Before the fix, compare refused with `mission_model_no_active_binding_set`, so a new
  mission's first catalog could never be approved through the console.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{Actor, FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Reads.MissionModelApprovals

  setup do
    org = "org-first-revision-#{System.unique_integer([:positive])}"
    mid = "mission-first-revision-#{System.unique_integer([:positive])}"
    importer = Fixtures.user_scope(org, "importer")
    {:ok, actor} = Actor.from_scope(importer)

    {craft, revision, _endpoint} =
      Fixtures.setup_imported_mission!(org, mid, approve: false, requested_by: actor)

    %{
      org: org,
      mid: mid,
      craft: craft,
      importer: importer,
      admin: Fixtures.user_scope(org, "admin"),
      catalog: revision.catalog_revision_id,
      model: revision.mission_model_revision_id
    }
  end

  test "compare with nothing earlier, the importer refused, another admin approves, then it is introduced",
       c do
    assert {:error, _none} = Cadence.Activations.fetch_active_activation(c.org, c.mid)

    assert {:ok, %{against: nil, passed: true, report_id: report_id} = cmp} =
             MissionModelApprovals.compare(c.admin, c.mid, c.model)

    assert %{status: "not_run"} = cmp.replay
    assert cmp.totals.added > 0

    assert {:error, :mission_model_self_approval_forbidden} =
             MissionModelApprovals.approve(c.importer, c.mid, c.model, report_id)

    assert {:ok, _approved} = MissionModelApprovals.approve(c.admin, c.mid, c.model, report_id)

    # The configuration request's own approval rule is not what this test is about.
    policy = ActivationPolicy.load(c.org, c.mid)

    {:ok, _} =
      ActivationPolicy.save(c.admin, c.mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    # A mission's first configuration comes from the per-spacecraft review (an activation
    # request), not a change set: a change-set apply builds a generation only over an active one
    # (ConfigurationGeneration.build_for). The model gate checks this path too.
    introduce!(c)

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mid)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    assert entry["catalog_revision_id"] == c.catalog
    assert entry["mission_model"]["revision_id"] == c.model
  end

  defp introduce!(c) do
    {:ok, mission} = Cadence.Missions.fetch_mission(c.org, c.mid)
    current = Drafts.snapshot(mission, c.craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    {:ok, _} = Drafts.save(c.admin, c.mid, c.craft.spacecraft_id, current.token, document)
    token = Drafts.snapshot(mission, c.craft).token
    {:ok, request} = Review.request_many(c.admin, c.mid, %{c.craft.spacecraft_id => token})
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    assert {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
