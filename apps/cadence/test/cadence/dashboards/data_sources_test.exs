defmodule Cadence.Dashboards.DataSourcesTest do
  use Cadence.DataCase, async: true

  alias Cadence.DataSources.{DataSource, DataSourceEvent}
  alias Cadence.Management.DataSources

  @organization_id "org-dash-source-lifecycle"
  @mission_id "mission-dash-source-lifecycle"
  @event_bus __MODULE__.UnusedEventBus

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "persists and lists dashboard data sources" do
    data_source = %DataSource{
      data_source_id: "org-managed-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      isolation_level: :org_isolated,
      capabilities: %{range_scan?: true, watermarks?: false},
      metadata: %{storage: :questdb}
    }

    assert {:ok, persisted} =
             DataSources.persist_data_source(data_source,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 18:00:00Z],
               event_bus: @event_bus,
               payload: %{reason: :initial_source}
             )

    assert persisted.data_source_id == "org-managed-questdb"
    assert persisted.owner == :cadence
    assert persisted.kind == :managed_tsdb
    assert persisted.adapter == Cadence.Dashboards.Sources.Telemetry
    assert persisted.isolation_level == :org_isolated
    assert persisted.credentials_ref == nil
    assert persisted.status == :active
    assert is_binary(persisted.current_event_id)
    assert persisted.capabilities == %{"range_scan?" => true, "watermarks?" => false}
    assert persisted.metadata == %{"storage" => "questdb"}

    assert listed =
             @organization_id
             |> DataSources.list_data_sources(@mission_id)
             |> Enum.find(&(&1.data_source_id == "org-managed-questdb"))

    assert listed.data_source_id == "org-managed-questdb"

    assert [%DataSourceEvent{} = registered_event] =
             DataSources.list_data_source_events(@organization_id, @mission_id,
               data_source_id: "org-managed-questdb"
             )

    assert registered_event.event_type == :registered
    assert registered_event.data_source_id == "org-managed-questdb"
    assert registered_event.current_status == :active
    assert registered_event.current_owner == :cadence
    assert registered_event.current_kind == :managed_tsdb
    assert registered_event.current_adapter == Cadence.Dashboards.Sources.Telemetry
    assert registered_event.current_isolation_level == :org_isolated

    assert registered_event.current_capabilities == %{
             "range_scan?" => true,
             "watermarks?" => false
           }

    assert registered_event.current_metadata == %{"storage" => "questdb"}
    assert registered_event.actor_id == "operator-1"
    assert registered_event.payload["reason"] == "initial_source"

    updated_source = %DataSource{
      data_source
      | capabilities: %{range_scan?: true, watermarks?: true},
        metadata: %{storage: :questdb, retention: :bounded}
    }

    assert {:ok, updated} =
             DataSources.persist_data_source(updated_source,
               actor_id: "operator-2",
               occurred_at: ~U[2026-06-21 19:00:00Z],
               event_bus: @event_bus,
               payload: %{change_request_id: "DS-42"}
             )

    assert updated.capabilities["watermarks?"] == true
    assert updated.metadata["retention"] == "bounded"

    assert [changed_event, first_event] =
             DataSources.list_data_source_events(@organization_id, @mission_id,
               data_source_id: "org-managed-questdb"
             )

    assert first_event.data_source_event_id == registered_event.data_source_event_id
    assert changed_event.event_type == :changed
    assert changed_event.previous_status == :active
    assert changed_event.current_status == :active

    assert changed_event.previous_capabilities == %{
             "range_scan?" => true,
             "watermarks?" => false
           }

    assert changed_event.current_capabilities == %{"range_scan?" => true, "watermarks?" => true}
    assert changed_event.previous_metadata == %{"storage" => "questdb"}
    assert changed_event.current_metadata == %{"retention" => "bounded", "storage" => "questdb"}
    assert changed_event.actor_id == "operator-2"
    assert changed_event.payload["change_request_id"] == "DS-42"

    assert {:ok, _same_source} =
             DataSources.persist_data_source(updated, event_bus: @event_bus)

    assert [_, _] =
             DataSources.list_data_source_events(@organization_id, @mission_id,
               data_source_id: "org-managed-questdb"
             )
  end

  test "disables and enables data sources as lifecycle events" do
    data_source = %DataSource{
      data_source_id: "toggle-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} =
             DataSources.persist_data_source(data_source,
               occurred_at: ~U[2026-06-21 18:00:00Z],
               event_bus: @event_bus
             )

    assert {:ok, disabled} =
             DataSources.disable_data_source("toggle-questdb", %{},
               actor_id: "operator-3",
               occurred_at: ~U[2026-06-21 19:00:00Z],
               event_bus: @event_bus,
               payload: %{reason: :maintenance}
             )

    assert disabled.status == :disabled
    assert disabled.disabled_at == ~U[2026-06-21 19:00:00.000000Z]
    assert is_binary(disabled.current_event_id)

    assert {:ok, fetched_disabled} = DataSources.fetch_data_source("toggle-questdb")
    assert fetched_disabled.status == :disabled

    assert {:ok, enabled} =
             DataSources.enable_data_source("toggle-questdb", %{},
               actor_id: "operator-4",
               occurred_at: ~U[2026-06-21 20:00:00Z],
               event_bus: @event_bus,
               payload: %{reason: :maintenance_complete}
             )

    assert enabled.status == :active
    assert enabled.disabled_at == nil

    assert [enabled_event, disabled_event, registered_event] =
             DataSources.list_data_source_events(@organization_id, @mission_id,
               data_source_id: "toggle-questdb"
             )

    assert registered_event.event_type == :registered
    assert disabled_event.event_type == :disabled
    assert disabled_event.previous_status == :active
    assert disabled_event.current_status == :disabled
    assert disabled_event.actor_id == "operator-3"
    assert disabled_event.payload["reason"] == "maintenance"
    assert enabled_event.event_type == :enabled
    assert enabled_event.previous_status == :disabled
    assert enabled_event.current_status == :active
    assert enabled_event.actor_id == "operator-4"
    assert enabled_event.payload["reason"] == "maintenance_complete"
  end
end
