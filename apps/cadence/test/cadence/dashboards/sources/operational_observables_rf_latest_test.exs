defmodule Cadence.Dashboards.Sources.OperationalObservablesRFLatestTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{Field, Frame, ResolveWarning, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables

  test "resolves RF lock state from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:07:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_lock_transports, organization_id, mission_id, opts})

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
        link_rf_lock_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_lock_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              lock_state: "locked",
              observed_at: ~U[2026-06-17 12:07:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              lock_state: :unlocked,
              observed_at: ~U[2026-06-17 12:07:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_lock_state
    assert frame.meta.supported_capability == :link_rf_lock_state
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :lock_state
    assert frame.meta.observable_id == "link.rf_lock_state"
    assert frame.meta.returned_points == 1

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF lock / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "state", values: [:locked]},
             %Field{name: "normalized_state", values: [:green]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:07:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:rf_lock_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:rf_lock_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks configured link RF lock rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:07:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_lock_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_lock_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :link_rf_lock_state
    assert warning.details.frame_ids == ["ops-request-1:link_rf_lock_state"]
    assert warning.details.observable_ids == ["link.rf_lock_state"]
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:07:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF lock / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "state", values: [:unknown]},
             %Field{name: "normalized_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_rf_lock_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_rf_lock_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves frame sync state from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:09:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:frame_sync_transports, organization_id, mission_id, opts})

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
        link_rf_frame_sync_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:frame_sync_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: "synchronized",
              observed_at: ~U[2026-06-17 12:09:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:09:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_frame_sync_state
    assert frame.meta.supported_capability == :link_rf_frame_sync_state
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :frame_sync_state
    assert frame.meta.observable_id == "link.frame_sync_state"
    assert frame.meta.returned_points == 1

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.frame_sync_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["Frame sync / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "state", values: [:synchronized]},
             %Field{name: "normalized_state", values: [:green]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:09:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:frame_sync_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:frame_sync_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks configured frame sync rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:09:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_frame_sync_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_frame_sync_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :link_rf_frame_sync_state
    assert warning.details.frame_ids == ["ops-request-1:link_rf_frame_sync_state"]
    assert warning.details.observable_ids == ["link.frame_sync_state"]
    assert frame.meta.supported_capability == :link_rf_frame_sync_state
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :frame_sync_state
    assert frame.meta.observable_id == "link.frame_sync_state"
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:09:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.frame_sync_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["Frame sync / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "state", values: [:unknown]},
             %Field{name: "normalized_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_frame_sync_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_frame_sync_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF SNR metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_transports, organization_id, mission_id, opts})

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
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              snr_db: 7.5,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.snr_db"]
    assert frame.meta.returned_points == 1

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.snr_db"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF SNR / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [12.75]},
             %Field{name: "unit", values: ["dB"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:rf_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:rf_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF Eb/N0 metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.eb_n0_db"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:03Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_metric_transports, organization_id, mission_id, opts})

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
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              eb_n0_db: 9.75,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              eb_n0_db: 6.5,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.eb_n0_db"]
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.eb_n0_db"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF Eb/N0 / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [9.75]},
             %Field{name: "unit", values: ["dB"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [3_000]}
           ] = frame.fields

    assert_received {:eb_n0_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:eb_n0_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF symbol-rate metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.symbol_rate_sps"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:04Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_metric_transports, organization_id, mission_id, opts})

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
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              symbol_rate_sps: 1_024_000.0,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              symbols_per_second: 512_000.0,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.symbol_rate_sps"]
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.symbol_rate_sps"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF Symbol Rate / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [1_024_000.0]},
             %Field{name: "unit", values: ["sym/s"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [4_000]}
           ] = frame.fields

    assert_received {:symbol_rate_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:symbol_rate_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF Doppler metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.doppler_hz"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:04Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_metric_transports, organization_id, mission_id, opts})

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
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frequency_offset_hz: -42.5,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              doppler_hz: 71.0,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.doppler_hz"]
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.doppler_hz"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF Doppler / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [-42.5]},
             %Field{name: "unit", values: ["Hz"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [4_000]}
           ] = frame.fields

    assert_received {:doppler_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:doppler_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks configured RF SNR metric rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_metric_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_metric_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :link_rf_metric
    assert warning.details.frame_ids == ["ops-request-1:link_rf_metric"]
    assert warning.details.observable_ids == ["link.snr_db"]
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.snr_db"]
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:08:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.snr_db"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF SNR / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "value", values: [nil]},
             %Field{name: "unit", values: ["dB"]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_rf_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_rf_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end
end
