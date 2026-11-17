defmodule Cadence.Configuration.SwitchOwnerTest do
  @moduledoc """
  DECISIONS #109 (director 11-17): change sets are the only writer of a spacecraft's Telemetry
  and Commanding switches. A saved configuration takes the spacecraft row's values ('not set by any
  change set' reads off) and ignores switch input. A new mission's first start: a change set turns
  telemetry on, then the craft's configuration is reviewed and activated, then it runs.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.SpacecraftStore

  setup do
    org = "org-switch-owner-#{System.unique_integer([:positive])}"
    mid = "mission-switch-owner-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    %{
      org: org,
      mission: mission,
      scope: scope,
      craft: craft,
      catalog: revision.catalog_revision_id
    }
  end

  test "a saved configuration takes the spacecraft's switches and ignores switch input", c do
    # Not set by any change set: off, whatever the input says.
    assert {:ok, _} = save(c, %{"telemetry_enabled" => true, "commanding_enabled" => true})
    assert %{"telemetry_enabled" => false, "commanding_enabled" => false} = latest(c)

    # Set by a change set: the row's values, whatever the input says.
    {:ok, _} =
      SpacecraftStore.put_switches(c.org, c.mission.mission_id, c.craft.spacecraft_id, %{
        telemetry_enabled: true,
        commanding_enabled: false
      })

    assert {:ok, _} = save(c, %{"telemetry_enabled" => false, "commanding_enabled" => true})
    assert %{"telemetry_enabled" => true, "commanding_enabled" => false} = latest(c)
  end

  test "a fresh mission's first start: a change set turns telemetry on, then review and activate, then the craft runs",
       c do
    id = c.craft.spacecraft_id

    assert {:error, _none} =
             Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    # The craft has no fleet entry (nothing has run): the change set stores the switch, no refusal.
    op = %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [%{path: "telemetry_enabled", value: true}]
    }

    {:ok, staged} =
      Configuration.stage(c.scope, c.mission.mission_id, %{summary: "First start"}, [op])

    assert {:ok, %{state: :applied}} =
             Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
               reason: "Turn telemetry on for the first start",
               expected_version: staged.version,
               acknowledged_holds: true
             })

    assert {:ok, %{telemetry_enabled: true}} =
             SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, id)

    # The configuration takes the change set's switch; then review and activate.
    assert {:ok, _} = save(c, %{})
    assert %{"telemetry_enabled" => true} = latest(c)

    token = Drafts.snapshot(c.mission, c.craft).token
    assert {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, %{id => token})
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    assert {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)

    # It runs, decoding telemetry.
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, id)
    assert entry["document"]["telemetry_enabled"] == true
    assert entry["telemetry_capability_ids"] != []
  end

  defp save(c, switches) do
    current = Drafts.snapshot(c.mission, c.craft)

    document =
      SpacecraftConfigurationInput.empty()
      |> Map.merge(%{"catalog_revision_id" => c.catalog, "handled_apids" => [42]})
      |> Map.merge(switches)

    Drafts.save(c.scope, c.mission.mission_id, c.craft.spacecraft_id, current.token, document)
  end

  defp latest(c), do: Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id).document
end
