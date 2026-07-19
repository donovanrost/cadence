defmodule Cadence.Dashboards.Sources.OperationalObservablesMetricsTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{DataLink, Field, Frame, ResolveWarning, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables

  test "resolves transport bit rate from configured transports and metric snapshots" do
    transports_fun = fn organization_id, mission_id, opts ->
      send(self(), {:bitrate_transports, organization_id, mission_id, opts})

      [
        transport("transport-alpha", "Lab TCP",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14"
        ),
        transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
      ]
    end

    transport_metric_snapshots_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transport_metric_snapshots, organization_id, mission_id, opts})

      [
        %{
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          adapter_key: :tcp_socket,
          downlink_bitrate: 12_500.5,
          observed_at: ~U[2026-06-17 12:04:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:04:02Z],
        transports_fun: transports_fun,
        transport_metric_snapshots_fun: transport_metric_snapshots_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :transport_bitrate
    assert result.meta.degraded?
    assert warning.details.supported_capability == :transport_bitrate
    assert warning.details.frame_ids == ["ops-request-1:transport_bitrate"]
    assert warning.details.observable_ids == ["comms.transport.downlink_bitrate"]
    assert frame.meta.supported_capability == :transport_bitrate
    assert frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert frame.meta.unit == "bit/s"
    assert frame.meta.returned_points == 2
    assert frame.meta.warning_codes == [:missing_snapshot]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:transport, "transport-beta"},
             {:source_endpoint, "endpoint-beta"}
           ]

    assert [
             %Field{
               name: "observable_id",
               values: [
                 "comms.transport.downlink_bitrate",
                 "comms.transport.downlink_bitrate"
               ]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "transport-beta"]},
             %Field{name: "label", values: ["Lab TCP", "Backup TCP"]},
             %Field{name: "scope_kind", values: [:transport, :transport]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-beta"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-beta"]},
             %Field{name: "ground_station_id", values: ["dss-14", nil]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "value", values: [12_500.5, nil]},
             %Field{name: "unit", values: ["bit/s", "bit/s"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:04:00Z], nil]},
             %Field{name: "freshness_state", values: [:fresh, :missing]},
             %Field{name: "age_ms", values: [2_000, nil]}
           ] = frame.fields

    assert_received {:bitrate_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:transport_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves uplink transport bit rate as the transport bitrate family" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.uplink_bitrate"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:04:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              uplink_bitrate: 4_800.0,
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert result.meta.supported_capability == :transport_bitrate
    assert frame.meta.supported_capability == :transport_bitrate
    assert frame.meta.observable_id == "comms.transport.uplink_bitrate"
    assert frame.meta.observable_ids == ["comms.transport.uplink_bitrate"]

    assert [
             %Field{name: "observable_id", values: ["comms.transport.uplink_bitrate"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "value", values: [4_800.0]},
             %Field{name: "unit", values: ["bit/s"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:04:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "filters transport bit rate rows to link scope" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:04:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:04:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              downlink_bitrate: 9_000.0,
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: []
           } = result

    assert [
             %Field{name: "observable_id", values: ["comms.transport.downlink_bitrate"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "value", values: [12_500.5]} | _rest
           ] = frame.fields
  end

  test "resolves transport bit rate history into one wide frame per transport" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:bitrate_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            ),
            transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
          ]
        end,
        transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:bitrate_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 13_000.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              source_endpoint_id: "endpoint-beta",
              adapter_key: :tcp_socket,
              downlink_bitrate: 9_000.0,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              transport_id: "transport-alpha",
              downlink_bitrate: 14_000.0,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [alpha_frame, beta_frame], warnings: []} = result
    assert result.meta.supported_capability == :transport_bitrate_history
    assert result.meta.returned_frame_count == 2

    assert alpha_frame.meta.supported_capability == :transport_bitrate_history
    assert alpha_frame.meta.product_family == :transport_bitrate
    assert alpha_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert alpha_frame.meta.resource_id == "transport-alpha"
    assert alpha_frame.meta.unit == "bit/s"
    assert alpha_frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Field{
               name: "comms.transport.downlink_bitrate",
               values: [12_500.5, 13_000.0],
               metadata: %{label: "Lab TCP", resource_id: "transport-alpha", unit: "bit/s"}
             }
           ] = alpha_frame.fields

    assert beta_frame.meta.resource_id == "transport-beta"
    assert beta_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:30Z]]},
             %Field{name: "comms.transport.downlink_bitrate", values: [9_000.0]}
           ] = beta_frame.fields

    assert_received {:bitrate_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:bitrate_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "keeps downlink and uplink transport bit rate history in separate series" do
    result =
      source_request()
      |> Map.put(:observables, [
        "comms.transport.downlink_bitrate",
        "comms.transport.uplink_bitrate"
      ])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [transport("transport-alpha", "Lab TCP", source_endpoint_id: "endpoint-alpha")]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              downlink_bitrate: 12_500.5,
              uplink_bitrate: 4_800.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [downlink_frame, uplink_frame], warnings: []} = result
    assert result.meta.supported_capability == :transport_bitrate_history
    assert result.meta.returned_frame_count == 2

    assert downlink_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert downlink_frame.meta.product_family == :transport_bitrate

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             %Field{name: "comms.transport.downlink_bitrate", values: [12_500.5]}
           ] = downlink_frame.fields

    assert uplink_frame.meta.observable_id == "comms.transport.uplink_bitrate"
    assert uplink_frame.meta.product_family == :transport_bitrate

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             %Field{name: "comms.transport.uplink_bitrate", values: [4_800.0]}
           ] = uplink_frame.fields
  end

  test "resolves empty transport bitrate history as a chartable zero-point frame" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_bitrate_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
          ]
        end,
        transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_bitrate_history_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    refute result.meta.degraded?
    assert result.meta.supported_capability == :transport_bitrate_history
    assert frame.meta.supported_capability == :transport_bitrate_history
    assert frame.meta.product_family == :transport_bitrate
    assert frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert frame.meta.resource_id == "transport-alpha"
    assert frame.meta.scope_kind == :transport
    assert frame.meta.transport_id == "transport-alpha"
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.ground_station_id == "dss-14"
    assert frame.meta.link_id == "link-alpha"
    assert frame.meta.unit == "bit/s"
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "time", values: []},
             %Field{
               name: "comms.transport.downlink_bitrate",
               values: [],
               metadata: %{
                 observable_id: "comms.transport.downlink_bitrate",
                 label: "Lab TCP",
                 unit: "bit/s",
                 resource_id: "transport-alpha",
                 scope_kind: :transport,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket
               }
             }
           ] = frame.fields

    assert_received {:empty_bitrate_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:empty_bitrate_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves command queue depth latest operational observable into a matrix frame" do
    command_queue_entries_fun = fn organization_id, mission_id, opts ->
      send(self(), {:command_queue_entries, organization_id, mission_id, opts})

      [
        command_queue_entry("queue-1", "endpoint-alpha", :pending),
        command_queue_entry("queue-2", "endpoint-alpha", :release_pending),
        command_queue_entry("queue-3", "endpoint-beta", :pending)
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        command_queue_entries_fun: command_queue_entries_fun,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :command_queue_depth
    assert frame.meta.supported_capability == :command_queue_depth
    assert frame.meta.product_family == :commanding
    assert frame.meta.observable_id == "commanding.queue_depth"
    assert frame.meta.unit == "commands"
    assert frame.meta.returned_points == 1
    assert frame.meta.command_queue_entry_ids == ["queue-1", "queue-3"]

    assert evidence_identities(frame) == [
             {:command_queue_entry, "queue-1"},
             {:command_queue_entry, "queue-3"}
           ]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [2]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:command_queue_entries, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "preserves replay command queue row identity and evidence refs" do
    command_queue_entries_fun = fn organization_id, mission_id, opts ->
      send(self(), {:replay_command_queue_entries, organization_id, mission_id, opts})

      [
        command_queue_entry("replay-queue-1", "endpoint-alpha", :pending),
        command_queue_entry("replay-queue-2", "endpoint-alpha", :released)
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z],
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{
        realm: :replay,
        replay_run_id: "replay-run-1",
        source_contexts: %{
          operational_observables: %{
            data_source_id: "managed_operational_observables_replay",
            source_binding_id: "replay-operational-observables",
            dataset: "operational_observables_replay"
          }
        }
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: command_queue_entries_fun,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.data_source_id == "managed_operational_observables_replay"
    assert frame.meta.source_binding_id == "replay-operational-observables"
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.command_queue_entry_ids == ["replay-queue-1"]
    assert evidence_identities(frame) == [{:command_queue_entry, "replay-queue-1"}]

    assert [%{kind: :command_queue_entry, id: "replay-queue-1"} = evidence_ref] =
             frame.meta.evidence_refs

    assert evidence_ref.source == :operational_observables
    assert evidence_ref.confidence == :direct
    assert evidence_ref.observed_at == ~U[2026-06-17 12:00:00Z]

    assert_received {:replay_command_queue_entries, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
  end

  test "resolves an empty command queue as a fresh zero aggregate" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_command_queue_entries, organization_id, mission_id, opts})
          []
        end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert frame.meta.supported_capability == :command_queue_depth
    assert frame.meta.command_queue_entry_ids == []
    assert frame.meta.evidence_refs == []
    assert frame.meta.warning_codes == []
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [0]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:empty_command_queue_entries, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks non-ingress latest operational rows stale when freshness policy expires" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        freshness_policy: %{stale_after_ms: 1_000},
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :stale_data, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.details.supported_capability == :command_queue_depth
    assert warning.details.frame_ids == ["ops-request-1:command_queue_depth"]
    assert warning.details.observable_ids == ["commanding.queue_depth"]
    assert frame.meta.warning_codes == [:stale_data]
    assert frame.meta.freshness_policy == %{stale_after_ms: 1_000}
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [0]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:stale]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "filters command queue depth to source endpoint scope" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-alpha", :pending),
            command_queue_entry("queue-2", "endpoint-beta", :pending)
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert [%DataLink{target: :source_endpoint, target_id: "endpoint-alpha"}] = frame.meta.links

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["source endpoint / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "value", values: [1]} | _rest
           ] = frame.fields
  end

  test "filters command queue depth to multi-spacecraft scope without mislabeling the first spacecraft" do
    scope_ids = ["spacecraft-alpha", "spacecraft-beta"]
    resource_id = Enum.join(scope_ids, ",")

    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :spacecraft, mode: :many, ids: scope_ids}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-alpha", "endpoint-alpha", :pending)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-alpha"}),
            command_queue_entry("queue-beta", "endpoint-beta", :pending)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-beta"}),
            command_queue_entry("queue-gamma", "endpoint-gamma", :pending)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-gamma"}),
            command_queue_entry("queue-released", "endpoint-alpha", :released)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-alpha"})
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.links == []

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: [^resource_id]},
             %Field{name: "label", values: ["spacecraft / " <> ^resource_id]},
             %Field{name: "scope_kind", values: [:spacecraft]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [2]} | _rest
           ] = frame.fields
  end

  test "resolves empty source endpoint command queue as a fresh zero with resource link" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-beta", :pending),
            command_queue_entry("queue-2", "endpoint-alpha", :released)
          ]
        end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert [%DataLink{target: :source_endpoint, target_id: "endpoint-alpha"}] = frame.meta.links
    assert frame.meta.warning_codes == []
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["source endpoint / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "value", values: [0]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "marks source endpoint command queue rows stale without dropping resource link" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-alpha", :pending),
            command_queue_entry("queue-2", "endpoint-beta", :pending)
          ]
        end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        freshness_policy: %{stale_after_ms: 1_000},
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :stale_data, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.details.supported_capability == :command_queue_depth
    assert warning.details.observable_ids == ["commanding.queue_depth"]
    assert [%DataLink{target: :source_endpoint, target_id: "endpoint-alpha"}] = frame.meta.links
    assert frame.meta.warning_codes == [:stale_data]
    assert frame.meta.freshness_policy == %{stale_after_ms: 1_000}
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["source endpoint / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "value", values: [1]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:stale]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end
end
