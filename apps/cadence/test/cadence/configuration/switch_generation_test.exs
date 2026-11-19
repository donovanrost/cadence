defmodule Cadence.Configuration.SwitchGenerationTest do
  @moduledoc "Commanding and telemetry switches as change-set fields (L22)."
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Applications.SpacecraftConfiguration.{CatalogAuthority, Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.{Configuration, ConfigurationSwitches}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Spacecraft.ConfigKinds.Spacecraft, as: SpacecraftKind
  alias Cadence.SpacecraftStore

  setup do
    org = "org-switch-gen-#{System.unique_integer([:positive])}"
    mid = "mission-switch-gen-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    configure(scope, mission, craft, revision.catalog_revision_id)
    %{org: org, mission: mission, scope: scope, craft: craft, endpoint: endpoint}
  end

  test "commanding off cancels waiting commands; one being sent blocks until it finishes", c do
    id = c.craft.spacecraft_id
    waiting = request!(c, "validated")
    in_flight = request!(c, "released", verification_state: "pending")
    {:ok, staged} = stage(c, [switch_op(id, "commanding_enabled", false)])

    assert {:ok, %{checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, staged.change_set_id)

    items = Enum.flat_map(checks, & &1.items)
    sending = Enum.find(items, &(&1[:reason] == :commanding_command_in_flight))
    canceled = Enum.find(items, &(&1[:reason] == :commanding_disabled_cancels_commands))

    assert %{blocking: true, sentence: sending_sentence} = sending
    assert sending_sentence =~ "while “NOOP” is being sent to it. Abort that request"
    assert %{blocking: false, sentence: canceled_sentence} = canceled
    assert canceled_sentence =~ "cancels 1 command waiting to be sent to"

    assert {:error, {:holds_blocking, _preview}} = submit(c, staged)

    Repo.query!(
      "UPDATE command_requests SET verification_state = 'satisfied' WHERE command_request_id = $1",
      [in_flight]
    )

    assert {:ok, %{state: :applied}} = submit(c, staged)

    %{rows: [[state, metadata]]} =
      Repo.query!(
        "SELECT lifecycle_state, metadata_document FROM command_requests WHERE command_request_id = $1",
        [waiting]
      )

    assert state == "canceled"
    assert get_in(metadata, ["value", "cancellation", "reason"]) =~ "commanding_disabled: "
  end

  test "turning commanding off is a generation the configuration follows; a save can't turn it back on",
       c do
    id = c.craft.spacecraft_id

    # Set by a change set (the fixture stands in for it, DECISIONS #109).
    assert %{^id => document} = SpacecraftKind.load(c.org, c.mission.mission_id, [id])
    assert document["commanding_enabled"] == true

    assert SpacecraftKind.runtime_impact(
             :update,
             %{"commanding_enabled" => true},
             %{"commanding_enabled" => false}
           ) == :generation

    assert SpacecraftKind.runtime_impact(:update, %{"display_name" => "a"}, %{
             "display_name" => "b"
           }) == :none

    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    {:ok, staged} = stage(c, [switch_op(id, "commanding_enabled", false)])

    assert {:ok, %{state: :applied, generation: generation}} = submit(c, staged)
    assert generation > before.generation

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, id)
    assert entry["commanding_enabled"] == false
    assert entry["document"]["commanding_enabled"] == false
    assert entry["document"]["telemetry_enabled"] == true

    assert {:ok, %{commanding_enabled: false, telemetry_enabled: true} = craft} =
             SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, id)

    assert Drafts.latest(c.org, c.mission.mission_id, id).document["commanding_enabled"] == false

    assert %{^id => %{"commanding_enabled" => false} = document} =
             SpacecraftKind.load(c.org, c.mission.mission_id, [id])

    assert document["telemetry_enabled"] == true

    # One writer (#109): a saved configuration takes the spacecraft's switch, whatever it asks.
    current = Drafts.snapshot(c.mission, c.craft)

    assert {:ok, _} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               id,
               current.token,
               Map.put(current.document, "commanding_enabled", true)
             )

    assert Drafts.latest(c.org, c.mission.mission_id, id).document["commanding_enabled"] == false

    # The review's backstop still refuses a configuration that disagrees.
    assert {:error, :spacecraft_switch_set_by_change_set} =
             CatalogAuthority.switches_check(craft, %{
               "commanding_enabled" => true,
               "telemetry_enabled" => true
             })

    assert :ok =
             CatalogAuthority.switches_check(craft, %{
               "commanding_enabled" => false,
               "telemetry_enabled" => true
             })
  end

  test "turning telemetry off holds for acknowledgment, drops the decode, and turns back on", c do
    id = c.craft.spacecraft_id
    {:ok, staged} = stage(c, [switch_op(id, "telemetry_enabled", false)])

    assert {:ok, %{verdict: :hold, checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, staged.change_set_id)

    assert %{blocking: false, sentence: sentence} =
             checks
             |> Enum.flat_map(& &1.items)
             |> Enum.find(&(&1[:reason] == :telemetry_disabled))

    assert sentence =~ "telemetry from #{c.craft.display_name} isn't decoded"

    assert {:ok, %{state: :applied}} = submit(c, staged)
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, id)
    assert entry["telemetry_capability_ids"] == []

    {:ok, again} = stage(c, [switch_op(id, "telemetry_enabled", true)])
    assert {:ok, %{state: :applied}} = submit(c, again)
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, id)
    assert entry["telemetry_capability_ids"] != []
  end

  # Save installs the telemetry app when telemetry turns on; a change set doesn't (an installation
  # is its own governed act, director 11-15), so it holds and the apply refuses.
  test "turning telemetry on without the telemetry app installed is a blocking hold", c do
    id = c.craft.spacecraft_id
    {:ok, off} = stage(c, [switch_op(id, "telemetry_enabled", false)])
    assert {:ok, %{state: :applied}} = submit(c, off)

    host = HostContext.spacecraft(c.mission.mission_id, id)
    assert {:ok, _} = ApplicationInstallations.uninstall(c.scope, host, "telemetry_decom")

    {:ok, on} = stage(c, [switch_op(id, "telemetry_enabled", true)])

    assert {:ok, %{checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, on.change_set_id)

    assert %{blocking: true, sentence: sentence, spacecraft_ids: [^id], details: details} =
             checks
             |> Enum.flat_map(& &1.items)
             |> Enum.find(&(&1[:reason] == :telemetry_app_not_installed))

    assert sentence ==
             "Telemetry can't be turned on for #{c.craft.display_name}: the telemetry app " <>
               "isn't installed on it. Install the app in Setup › Apps first."

    assert %{app_key: "telemetry_decom", app_name: name} = details
    assert is_binary(name)
    assert {:error, {:holds_blocking, _preview}} = submit(c, on)
    assert ConfigurationSwitches.not_installed(c.org, c.mission.mission_id, [id]) == [id]
  end

  test "an edit that doesn't move a switch doesn't take it over" do
    sc = %Cadence.Spacecraft{
      spacecraft_id: "s",
      mission_id: "m",
      display_name: "S",
      commanding_enabled: nil,
      telemetry_enabled: nil
    }

    running = %{"document" => %{"commanding_enabled" => true, "telemetry_enabled" => false}}
    assert ConfigurationSwitches.targets(%{"s" => sc}, %{"s" => running}) == %{}

    assert ConfigurationSwitches.targets(%{"s" => %{sc | telemetry_enabled: true}}, %{
             "s" => running
           }) == %{"s" => %{"telemetry_enabled" => true}}

    refute ConfigurationSwitches.packet_inputs?(%{"document" => %{"handled_apids" => []}})
  end

  defp switch_op(id, path, value),
    do: %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [%{path: path, value: value}]
    }

  defp stage(c, ops),
    do: Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Switches"}, ops)

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
      reason: "Switch generation test",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  defp request!(c, state, opts \\ []) do
    id = "command-request-#{System.unique_integer([:positive])}"

    Repo.query!(
      """
      INSERT INTO command_requests (command_request_id, organization_id, mission_id,
        source_endpoint_ref, mission_model_revision_id, command_id, command_name, lifecycle_state,
        verification_state, requested_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'model', 'command', 'NOOP', $5, $6, now(), now(), now())
      """,
      [
        id,
        c.org,
        c.mission.mission_id,
        c.endpoint.source_endpoint_id,
        state,
        Keyword.get(opts, :verification_state)
      ]
    )

    id
  end

  defp configure(scope, mission, craft, catalog) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    :ok =
      Fixtures.change_set_switches!(
        scope.organization_id,
        mission.mission_id,
        craft.spacecraft_id,
        document
      )

    {:ok, _} =
      Drafts.save(scope, mission.mission_id, craft.spacecraft_id, current.token, document)

    token = Drafts.snapshot(mission, craft).token

    {:ok, request} =
      Review.request_many(scope, mission.mission_id, %{craft.spacecraft_id => token})

    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
