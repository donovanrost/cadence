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

  test "a change set that sets a switch while a save waits for the configuration lock is what the save stores",
       c do
    # The save authorizes (reading the spacecraft) BEFORE it takes the configuration lock. A change
    # set landing in between is simulated right after the lock is granted: the save must store the
    # row's switch as it is under the lock, not the earlier read (api-ops R1).
    lock_key = key(Cadence.Applications.ConfigurationLock, c.org, c.mission.mission_id)
    handler = "switch-owner-race-#{System.unique_integer([:positive])}"
    config = %{pid: self(), key: lock_key, c: c}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        &__MODULE__.set_switches_once/4,
        config
      )

    try do
      assert {:ok, _} = save(c, %{})
    after
      :telemetry.detach(handler)
    end

    assert Process.get(:switches_set_under_lock) == true
    assert %{"telemetry_enabled" => true, "commanding_enabled" => true} = latest(c)
  end

  test "a change set that turns a switch OFF while a save waits for the lock: the save stores off, no refusal",
       c do
    # Set on both; the save authorizes reading true/true, then a change set turns commanding off
    # before the lock. The save stores what the row says under the lock, and its checks compare
    # with that same row (api-ops' review of (B): comparing with the authorize read refused it).
    switches_on(c)
    lock_key = key(Cadence.Applications.ConfigurationLock, c.org, c.mission.mission_id)
    handler = "switch-owner-off-#{System.unique_integer([:positive])}"
    config = %{pid: self(), key: lock_key, c: c}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        &__MODULE__.commanding_off_once/4,
        config
      )

    try do
      assert {:ok, _} = save(c, %{})
    after
      :telemetry.detach(handler)
    end

    assert Process.get(:commanding_off_under_lock) == true
    assert %{"telemetry_enabled" => true, "commanding_enabled" => false} = latest(c)
  end

  @doc false
  def commanding_off_once(_event, _measurements, %{query: query, params: params}, config) do
    if self() == config.pid and query =~ "pg_advisory_xact_lock" and params == [config.key] and
         Process.get(:commanding_off_under_lock) != true do
      Process.put(:commanding_off_under_lock, true)

      {:ok, _} =
        SpacecraftStore.put_switches(
          config.c.org,
          config.c.mission.mission_id,
          config.c.craft.spacecraft_id,
          %{telemetry_enabled: true, commanding_enabled: false}
        )
    end
  end

  def commanding_off_once(_event, _measurements, _metadata, _config), do: :ok

  test "aligning unset row switches to the running values applies with no generation (the alignment change set)",
       c do
    id = c.craft.spacecraft_id
    switches_on(c)
    assert {:ok, _} = save(c, %{})
    token = Drafts.snapshot(c.mission, c.craft).token
    {:ok, request} = Review.request_many(c.scope, c.mission.mission_id, %{id => token})
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    # The legacy state (qa, Earendil 11-17): running with both switches on, rows never set.
    Repo.query!(
      "UPDATE mission_spacecraft SET telemetry_enabled = NULL, commanding_enabled = NULL WHERE spacecraft_id = $1",
      [id]
    )

    op = %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [
        %{path: "telemetry_enabled", value: true},
        %{path: "commanding_enabled", value: true}
      ]
    }

    {:ok, staged} = Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Align"}, [op])

    assert {:ok, %{checks: checks} = preview} =
             Configuration.preview(c.scope, c.mission.mission_id, staged.change_set_id)

    refute preview[:verdict] == :hold
    assert checks |> Enum.flat_map(& &1.items) |> Enum.filter(&(&1[:blocking] == true)) == []

    assert {:ok, %{state: :applied, generation: nil, activation_id: nil}} =
             Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
               reason: "Align the row switches with what runs",
               expected_version: staged.version,
               acknowledged_holds: true
             })

    {:ok, after_align} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert after_align.activation_id == before.activation_id

    assert {:ok, %{telemetry_enabled: true, commanding_enabled: true}} =
             SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, id)
  end

  @doc false
  def set_switches_once(_event, _measurements, %{query: query, params: params}, config) do
    if self() == config.pid and query =~ "pg_advisory_xact_lock" and params == [config.key] and
         Process.get(:switches_set_under_lock) != true do
      Process.put(:switches_set_under_lock, true)
      switches_on(config.c)
    end
  end

  def set_switches_once(_event, _measurements, _metadata, _config), do: :ok

  defp switches_on(c) do
    {:ok, _} =
      SpacecraftStore.put_switches(c.org, c.mission.mission_id, c.craft.spacecraft_id, %{
        telemetry_enabled: true,
        commanding_enabled: true
      })
  end

  defp key(module, organization_id, id) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({module, organization_id, id}))

    key
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
