defmodule Cadence.Dashboards.DataSourcesBindingHistoryTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Dashboards.DataSourcesFixtures

  alias Cadence.Dashboards.{
    DataBinding,
    DataBindingEvent,
    DataBindingInterval,
    DataSourceRegistry,
    DataSources,
    EvidenceRef,
    Frame,
    SourceFacts,
    SourceHealth,
    SourceRegistry
  }

  alias Cadence.OperationalEvents
  alias Cadence.Projections.DataSourceBindings

  setup do
    persist_mission_scope("org-dash-source", "mission-dash-source")
    :ok
  end

  test "persists and lists dashboard data bindings" do
    persist_source("mission-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{reason: :primary}
    }

    assert {:ok, persisted} = DataSources.persist_data_binding(binding)
    assert persisted.binding_id == "mission-flight-telemetry"
    assert persisted.realm == :flight
    assert persisted.logical_source == :telemetry
    assert persisted.dataset == "flight"
    assert persisted.status == :active
    assert persisted.binding_version == 1
    assert is_binary(persisted.current_event_id)
    assert persisted.metadata == %{"reason" => "primary"}

    assert [%DataBindingEvent{} = event] =
             DataSources.list_data_binding_events("mission-flight-telemetry")

    assert event.event_type == :registered
    assert event.current_status == :active
    assert event.current_binding_version == 1
    assert event.current_data_source_id == "mission-questdb"
    assert event.current_dataset == "flight"
    assert event.current_priority == 0
    assert event.current_realm == :flight

    assert [operational_event] =
             OperationalEvents.list_events("org-dash-source", "mission-dash-source",
               category: :data_source,
               kind: :source_binding_registered,
               source_record_kind: :dashboard_data_binding_event,
               source_record_id: event.data_binding_event_id
             )

    assert operational_event.subject == %{kind: :source_binding, id: "mission-flight-telemetry"}
    assert operational_event.scope["logical_source"] == "telemetry"
    assert operational_event.scope["source_binding_id"] == "mission-flight-telemetry"
    assert operational_event.scope["data_source_id"] == "mission-questdb"
    assert operational_event.scope["data_realm"] == "flight"
    assert operational_event.payload["binding_version"] == 1
    assert operational_event.payload["event_type"] == "registered"
    assert operational_event.current["status"] == "active"

    assert [listed] = DataSources.list_data_bindings("org-dash-source", "mission-dash-source")
    assert listed.binding_id == "mission-flight-telemetry"
  end

  test "records changed data binding lifecycle events and skips idempotent upserts" do
    persist_source("mission-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb",
      dataset: "flight",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 20:00:00Z],
               payload: %{reason: :initial_binding}
             )

    assert registered.binding_version == 1

    assert {:ok, same_binding} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 20:05:00Z]
             )

    assert same_binding.binding_version == 1
    assert [registered_event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert registered_event.event_type == :registered

    changed = %DataBinding{binding | dataset: "flight-v2", priority: 1}

    assert {:ok, updated} =
             DataSources.persist_data_binding(changed,
               actor_id: "operator-2",
               occurred_at: ~U[2026-06-21 21:00:00Z],
               payload: %{change_request_id: "CR-42"}
             )

    assert updated.binding_version == 2

    assert [changed_event, first_event] =
             DataSources.list_data_binding_events("mission-flight-telemetry")

    assert changed_event.event_type == :changed
    assert changed_event.previous_binding_version == 1
    assert changed_event.current_binding_version == 2
    assert changed_event.previous_dataset == "flight"
    assert changed_event.current_dataset == "flight-v2"
    assert changed_event.previous_priority == 0
    assert changed_event.current_priority == 1
    assert changed_event.actor_id == "operator-2"
    assert changed_event.payload["change_request_id"] == "CR-42"
    assert first_event.data_binding_event_id == registered_event.data_binding_event_id
  end

  test "disables enables and supersedes data bindings as lifecycle events" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "mission-flight-telemetry",
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 realm: :flight,
                 logical_source: :telemetry,
                 data_source_id: "mission-questdb",
                 dataset: "flight",
                 priority: 0
               },
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    assert {:ok, disabled} =
             DataSources.disable_data_binding("mission-flight-telemetry", %{},
               actor_id: "operator-3",
               occurred_at: ~U[2026-06-21 22:00:00Z]
             )

    assert disabled.status == :disabled
    assert disabled.disabled_at == ~U[2026-06-21 22:00:00.000000Z]
    assert disabled.binding_version == 2

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(), persisted?: true)

    assert warning.code == :missing_source_binding

    assert {:ok, enabled} =
             DataSources.enable_data_binding("mission-flight-telemetry", %{},
               actor_id: "operator-4",
               occurred_at: ~U[2026-06-21 23:00:00Z]
             )

    assert enabled.status == :active
    assert enabled.disabled_at == nil
    assert enabled.binding_version == 3
    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "mission-flight-telemetry"

    assert {:ok, superseded} =
             DataSources.supersede_data_binding("mission-flight-telemetry", %{},
               actor_id: "operator-5",
               occurred_at: ~U[2026-06-22 00:00:00Z]
             )

    assert superseded.status == :superseded
    assert superseded.superseded_at == ~U[2026-06-22 00:00:00.000000Z]
    assert superseded.active_to == ~U[2026-06-22 00:00:00.000000Z]
    assert superseded.binding_version == 4

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(), persisted?: true)

    assert warning.code == :missing_source_binding

    assert [superseded_event, enabled_event, disabled_event, registered_event] =
             DataSources.list_data_binding_events("mission-flight-telemetry")

    assert registered_event.event_type == :registered
    assert disabled_event.event_type == :disabled
    assert disabled_event.previous_status == :active
    assert disabled_event.current_status == :disabled
    assert enabled_event.event_type == :enabled
    assert enabled_event.previous_status == :disabled
    assert enabled_event.current_status == :active
    assert superseded_event.event_type == :superseded
    assert superseded_event.previous_status == :active
    assert superseded_event.current_status == :superseded
  end

  test "rolls back data binding projection changes when lifecycle event validation fails" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, %DataBinding{} = binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "flight",
               priority: 0
             })

    assert {:error, %Ecto.Changeset{} = changeset} =
             DataSources.persist_data_binding(%DataBinding{binding | dataset: "flight-v2"},
               payload: %{token: "plaintext"}
             )

    assert "must not embed credentials or secrets" in field_errors(changeset, :payload)

    assert {:ok, fetched} = DataSources.fetch_data_binding("mission-flight-telemetry")
    assert fetched.dataset == "flight"
    assert fetched.binding_version == 1

    assert [event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert event.event_type == :registered
  end

  test "persisted binding resolution skips source-wide unavailable health" do
    persist_source("primary-health-questdb", :mission_isolated)
    persist_source("backup-health-questdb", :mission_isolated)

    assert {:ok, _primary_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "primary-health-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "primary-health-questdb",
               dataset: "flight-primary",
               priority: 0
             })

    assert {:ok, _backup_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "backup-health-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "backup-health-questdb",
               dataset: "flight-backup",
               priority: 10
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 logical_source: :telemetry,
                 data_source_id: "primary-health-questdb",
                 source_health: :unavailable,
                 reason: :source_connection_failed,
                 observed_at: DateTime.utc_now()
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, resolved} = DataSourceBindings.resolve(source_request())

    assert resolved.binding.binding_id == "backup-health-flight"
    assert resolved.data_source.data_source_id == "backup-health-questdb"

    assert [
             %{
               binding_id: "primary-health-flight",
               decision: :rejected,
               reasons: [:source_unavailable],
               source_health: :unavailable,
               source_health_reason: :source_connection_failed
             },
             %{binding_id: "backup-health-flight", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "persisted binding resolution accepts strict source readiness policy" do
    persist_source("primary-degraded-questdb", :mission_isolated)
    persist_source("backup-degraded-questdb", :mission_isolated)

    assert {:ok, _primary_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "primary-degraded-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "primary-degraded-questdb",
               dataset: "flight-primary",
               priority: 0
             })

    assert {:ok, _backup_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "backup-degraded-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "backup-degraded-questdb",
               dataset: "flight-backup",
               priority: 10
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 logical_source: :telemetry,
                 data_source_id: "primary-degraded-questdb",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: DateTime.utc_now()
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, resolved} =
             DataSourceBindings.resolve(source_request(),
               source_readiness_policy: [
                 policy_id: :strict_ops,
                 block_source_health: [:unavailable, :degraded],
                 block_freshness: [:fresh]
               ]
             )

    assert resolved.binding.binding_id == "backup-degraded-flight"
    assert resolved.data_source.data_source_id == "backup-degraded-questdb"
    assert resolved.source_selection.source_readiness_policy.policy_id == :strict_ops

    assert [
             %{
               binding_id: "primary-degraded-flight",
               decision: :rejected,
               reasons: [:source_degraded],
               source_health: :degraded,
               source_health_reason: :source_schema_probe_failed
             },
             %{binding_id: "backup-degraded-flight", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "reconstructs source binding intervals and resolves historical bindings" do
    first_event_at = ~U[2026-06-21 20:00:00Z]
    second_event_at = ~U[2026-06-21 21:00:00Z]

    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: first_event_at
             )

    assert {:ok, changed} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               actor_id: "operator-2",
               occurred_at: second_event_at
             )

    assert [
             %DataBindingInterval{} = first_interval,
             %DataBindingInterval{} = second_interval
           ] =
             DataSources.list_data_binding_intervals("org-dash-source", "mission-dash-source",
               binding_id: "mission-flight-telemetry"
             )

    assert first_interval.data_binding_event_id == registered.current_event_id
    assert first_interval.data_source_id == "mission-questdb-v1"
    assert first_interval.dataset == "flight-v1"
    assert first_interval.binding_version == 1
    assert DateTime.compare(first_interval.started_at, first_event_at) == :eq
    assert DateTime.compare(first_interval.ended_at, second_event_at) == :eq

    assert second_interval.data_binding_event_id == changed.current_event_id
    assert second_interval.data_source_id == "mission-questdb-v2"
    assert second_interval.dataset == "flight-v2"
    assert second_interval.binding_version == 2
    assert DateTime.compare(second_interval.started_at, second_event_at) == :eq
    assert second_interval.ended_at == nil

    assert {:ok, historical_resolved} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 20:30:00Z]
             )

    assert historical_resolved.data_source.data_source_id == "mission-questdb-v1"
    assert historical_resolved.binding.dataset == "flight-v1"
    assert historical_resolved.binding.binding_version == 1
    assert historical_resolved.binding.current_event_id == registered.current_event_id

    assert historical_resolved.binding_interval.data_binding_event_id ==
             registered.current_event_id

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 19:30:00Z]
             )

    assert warning.code == :missing_source_binding
    assert warning.details.source_binding_at == ~U[2026-06-21 19:30:00Z]

    assert warning.details.source_binding_miss_reason ==
             :source_binding_not_started_at_requested_time

    assert warning.details.nearest_source_binding_id == "mission-flight-telemetry"
    assert warning.details.nearest_data_source_id == "mission-questdb-v1"

    assert DateTime.compare(warning.details.nearest_source_binding_started_at, first_event_at) ==
             :eq

    assert DateTime.compare(warning.details.nearest_source_binding_ended_at, second_event_at) ==
             :eq

    assert %{strategy: :historical_binding, eligible_candidate_count: 0, candidates: candidates} =
             warning.details.source_selection

    assert [
             %{
               binding_id: "mission-flight-telemetry",
               decision: :rejected,
               reasons: [:interval_not_effective]
             },
             %{
               binding_id: "mission-flight-telemetry",
               decision: :rejected,
               reasons: [:interval_not_effective]
             }
           ] = candidates

    assert {:ok, current_resolved} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 21:30:00Z]
             )

    assert current_resolved.data_source.data_source_id == "mission-questdb-v2"
    assert current_resolved.binding.dataset == "flight-v2"
    assert current_resolved.binding.binding_version == 2
    assert current_resolved.binding_interval.data_binding_event_id == changed.current_event_id
  end

  test "historical source binding resolution honors explicit binding context" do
    persist_source("primary-questdb", :mission_isolated)
    persist_source("selected-questdb", :mission_isolated)

    assert {:ok, _primary} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "primary-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "primary-questdb",
               dataset: "primary-flight",
               priority: 0
             })

    assert {:ok, _selected} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "selected-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "selected-questdb",
               dataset: "selected-flight",
               priority: 10
             })

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(
               source_request(
                 data_context: %{realm: :flight, source_binding_id: "selected-flight-telemetry"}
               ),
               persisted?: true,
               source_binding_at: DateTime.utc_now()
             )

    assert resolved.binding.binding_id == "selected-flight-telemetry"
    assert resolved.data_source.data_source_id == "selected-questdb"
    assert resolved.binding.dataset == "selected-flight"
  end

  test "historical range segmentation filters intervals by explicit binding context" do
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]

    persist_source("primary-questdb-v1", :mission_isolated)
    persist_source("primary-questdb-v2", :mission_isolated)
    persist_source("selected-questdb", :mission_isolated)

    primary_binding = %DataBinding{
      binding_id: "primary-segmented-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "primary-questdb-v1",
      dataset: "primary-v1",
      priority: 0
    }

    assert {:ok, _primary_v1} =
             DataSources.persist_data_binding(primary_binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _primary_v2} =
             DataSources.persist_data_binding(
               %DataBinding{
                 primary_binding
                 | data_source_id: "primary-questdb-v2",
                   dataset: "primary-v2"
               },
               occurred_at: boundary_time
             )

    assert {:ok, selected_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "selected-segmented-telemetry",
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 realm: :flight,
                 logical_source: :telemetry,
                 data_source_id: "selected-questdb",
                 dataset: "selected-flight",
                 priority: 10
               },
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, [resolved]} =
             DataSourceRegistry.resolve_segments(
               source_request(
                 data_context: %{
                   realm: :flight,
                   source_binding_id: "selected-segmented-telemetry"
                 }
               ),
               persisted?: true,
               source_binding_at: from_time,
               source_binding_range: %{from: from_time, to: to_time}
             )

    assert resolved.binding.binding_id == "selected-segmented-telemetry"
    assert resolved.binding.current_event_id == selected_binding.current_event_id
    assert resolved.data_source.data_source_id == "selected-questdb"
    assert resolved.segment_from == from_time
    assert resolved.segment_to == to_time
  end

  test "historical range resolution warns when a query crosses source binding intervals" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, _registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _changed} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 20:15:00Z],
               source_binding_range: %{
                 from: ~U[2026-06-21 20:15:00Z],
                 to: ~U[2026-06-21 21:15:00Z]
               }
             )

    assert warning.code == :source_binding_interval_ambiguous
    assert warning.severity == :error
    assert warning.details.from == ~U[2026-06-21 20:15:00Z]
    assert warning.details.to == ~U[2026-06-21 21:15:00Z]

    assert Enum.map(warning.details.intervals, & &1.data_source_id) == [
             "mission-questdb-v1",
             "mission-questdb-v2"
           ]
  end

  test "source registry segments telemetry history reads across source binding intervals" do
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: boundary_time
             )

    history_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:history_opts, opts})

      case Keyword.fetch!(opts, :data_source_id) do
        "mission-questdb-v1" ->
          assert Keyword.fetch!(opts, :from_receipt_time) == from_time
          assert DateTime.compare(Keyword.fetch!(opts, :to_receipt_time), boundary_time) == :eq

          [
            sample(point_id, "sample-v1", 11.0, ~U[2026-06-21 20:30:00Z], "evidence-v1",
              generation_time: ~U[2026-06-21 20:29:59Z]
            )
          ]

        "mission-questdb-v2" ->
          assert DateTime.compare(Keyword.fetch!(opts, :from_receipt_time), boundary_time) == :eq
          assert Keyword.fetch!(opts, :to_receipt_time) == to_time

          [
            sample(point_id, "sample-v2", 22.0, ~U[2026-06-21 21:05:00Z], "evidence-v2",
              generation_time: ~U[2026-06-21 21:04:59Z]
            )
          ]
      end
    end

    result =
      SourceRegistry.resolve(
        source_request(
          sampling: %{mode: :raw_series},
          time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
        ),
        persisted?: true,
        source_binding_at: from_time,
        source_binding_range: %{from: from_time, to: to_time},
        source_opts: %{telemetry: [history_fun: history_fun]}
      )

    refute Enum.any?(result.warnings, &(&1.severity == :error))
    assert result.meta.segmented_source_bindings?
    assert result.meta.source_binding_segment_count == 2

    assert Enum.map(result.meta.source_binding_segments, & &1.data_source_id) == [
             "mission-questdb-v1",
             "mission-questdb-v2"
           ]

    assert Enum.map(result.meta.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.segmented_source_bindings?
    assert frame.meta.source_binding_segment_count == 2
    refute Map.has_key?(frame.meta, :source_binding_id)
    assert frame.meta.data_source_ids == ["mission-questdb-v1", "mission-questdb-v2"]
    assert frame.meta.datasets == ["flight-v1", "flight-v2"]

    assert frame.meta.evidence
           |> Enum.filter(&match?(%EvidenceRef{kind: :source_binding_event}, &1))
           |> Enum.map(& &1.id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert [
             %{name: "time", values: [~U[2026-06-21 20:30:00Z], ~U[2026-06-21 21:05:00Z]]},
             %{name: "HK.counter", values: [11.0, 22.0]}
           ] = frame.fields

    assert_received {:history_opts, first_opts}
    assert_received {:history_opts, second_opts}
    assert Keyword.fetch!(first_opts, :data_source_id) == "mission-questdb-v1"
    assert Keyword.fetch!(second_opts, :data_source_id) == "mission-questdb-v2"
  end

  test "segmented telemetry facts carry source binding segments for cache preflight" do
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_watermarked_source("mission-questdb-v1")
    persist_watermarked_source("mission-questdb-v2")

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: boundary_time
             )

    watermark_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:watermark_opts, opts})

      %{
        complete_through: Keyword.fetch!(opts, :to_receipt_time),
        latest_receipt_time: Keyword.fetch!(opts, :to_receipt_time),
        retention_starts_at: Keyword.fetch!(opts, :from_receipt_time),
        point_id: point_id,
        confidence: :best_effort
      }
    end

    assert {:ok, %SourceFacts{} = facts} =
             SourceRegistry.facts(
               source_request(
                 sampling: %{mode: :raw_series},
                 time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
               ),
               persisted?: true,
               source_binding_at: from_time,
               source_binding_range: %{from: from_time, to: to_time},
               source_opts: %{telemetry: [watermark_fun: watermark_fun]}
             )

    assert facts.source_binding == nil
    assert facts.data_source == nil
    assert facts.source_health == :healthy
    assert facts.meta.segmented_source_bindings?
    assert facts.meta.source_binding_segment_count == 2
    assert length(facts.watermarks) == 2
    assert facts.watermark.confidence == :best_effort
    assert DateTime.compare(facts.watermark.complete_through, boundary_time) == :eq

    assert Enum.map(facts.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    key =
      SourceFacts.runtime_cache_key(
        source_request(
          sampling: %{mode: :raw_series},
          time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
        ),
        facts,
        cache_policy: :snapshot
      )

    refute Map.has_key?(key.parts, :source_binding)
    refute Map.has_key?(key.parts, :data_source)

    assert Enum.map(key.parts.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert_received {:watermark_opts, first_opts}
    assert_received {:watermark_opts, second_opts}
    assert Keyword.fetch!(first_opts, :data_source_id) == "mission-questdb-v1"
    assert Keyword.fetch!(second_opts, :data_source_id) == "mission-questdb-v2"
  end
end
