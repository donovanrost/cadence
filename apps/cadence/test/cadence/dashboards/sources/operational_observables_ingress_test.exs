defmodule Cadence.Dashboards.Sources.OperationalObservablesIngressTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{DataLink, Field, Frame, ResolveWarning, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables

  test "resolves ingress processing latency latest operational observable into a matrix frame" do
    runtime_metric_snapshots_fun = fn organization_id, mission_id, opts ->
      send(self(), {:runtime_metric_snapshots, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          transport_id: "transport-alpha",
          ground_station_id: "dss-14",
          link_id: "link-alpha",
          adapter_key: :tcp_socket,
          value: 4.5,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z],
          error?: false
        },
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-2",
          source_endpoint_id: "endpoint-beta",
          value: 9.0,
          observed_at: ~U[2026-06-17 12:07:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        runtime_metric_snapshots_fun: runtime_metric_snapshots_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :ingress_processing_latency
    assert frame.meta.supported_capability == :ingress_processing_latency
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.observable_id == "ingress.processing_latency_ms"
    assert frame.meta.unit == "ms"
    assert frame.meta.returned_points == 1
    assert frame.meta.freshness_policy == %{stale_after_ms: 5_000}
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:06:02Z]
    assert frame.meta.warning_codes == []

    assert [
             %DataLink{target: :transport, target_id: "transport-alpha"},
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :ground_station, target_id: "dss-14"},
             %DataLink{target: :link, target_id: "link-alpha"}
           ] = frame.meta.links

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [4.5]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields

    assert_received {:runtime_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "filters ingress processing latency latest rows to multi-spacecraft scope" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :spacecraft, mode: :many, ids: ["spacecraft-alpha", "spacecraft-beta"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              spacecraft_id: "spacecraft-beta",
              value: 5.5,
              observed_at: ~U[2026-06-17 12:06:01Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-gamma",
              spacecraft_id: "spacecraft-gamma",
              value: 6.5,
              observed_at: ~U[2026-06-17 12:06:01Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 2

    assert [
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :source_endpoint, target_id: "endpoint-beta"}
           ] = Enum.filter(frame.meta.links, &(&1.target == :source_endpoint))

    assert [
             %Field{
               name: "observable_id",
               values: ["ingress.processing_latency_ms", "ingress.processing_latency_ms"]
             },
             %Field{name: "resource_id", values: ["endpoint-alpha", "endpoint-beta"]},
             %Field{
               name: "label",
               values: ["Ingress latency / endpoint-alpha", "Ingress latency / endpoint-beta"]
             },
             %Field{name: "scope_kind", values: [:source_endpoint, :source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-beta"]},
             %Field{name: "transport_id", values: [nil, nil]},
             %Field{name: "ground_station_id", values: [nil, nil]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "contact_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [nil, nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha", "spacecraft-beta"]},
             %Field{name: "value", values: [4.5, 5.5]} | _rest
           ] = frame.fields
  end

  test "filters ingress processing latency latest rows to contact scope" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :contact, mode: :one, ids: ["contact-alpha"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              contact_id: "contact-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              contact_id: "contact-beta",
              value: 5.5,
              observed_at: ~U[2026-06-17 12:06:01Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1

    assert [
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :contact, target_id: "contact-alpha"}
           ] = Enum.filter(frame.meta.links, &(&1.target in [:source_endpoint, :contact]))

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: ["contact-alpha"]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: [nil]},
             %Field{name: "value", values: [4.5]} | _rest
           ] = frame.fields
  end

  test "marks ingress processing latency stale when the runtime sample exceeds freshness policy" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 1_000},
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :stale_data, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.details.supported_capability == :ingress_processing_latency
    assert warning.details.frame_ids == ["ops-request-1:ingress_processing_latency"]
    assert warning.details.observable_ids == ["ingress.processing_latency_ms"]
    assert frame.meta.warning_codes == [:stale_data]

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: [nil]},
             %Field{name: "value", values: [4.5]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:stale]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields
  end

  test "overlays live runtime-health ingress latency over an older durable sample" do
    parent = self()

    durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 12.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:00:00Z]
        }
      ]
    end

    runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 4.5,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [4.5]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :flight
    assert durable_opts[:dataset] == "operational_observables"

    assert_received {:runtime_ingress_latency, "org-1", "mission-1", runtime_opts}
    assert runtime_opts[:realm] == :flight
    assert runtime_opts[:dataset] == "operational_observables"
  end

  test "keeps newer durable ingress latency when runtime-health sample is older" do
    parent = self()

    durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 8.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z]
        }
      ]
    end

    runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 99.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:00:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == []

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [8.0]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :flight
    assert durable_opts[:dataset] == "operational_observables"

    assert_received {:runtime_ingress_latency, "org-1", "mission-1", runtime_opts}
    assert runtime_opts[:realm] == :flight
    assert runtime_opts[:dataset] == "operational_observables"
  end

  test "returns no ingress latency rows when durable and runtime-health samples are absent" do
    parent = self()

    empty_durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})
      []
    end

    empty_runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})
      []
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: empty_durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: empty_runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert [
             %Field{name: "observable_id", values: []},
             %Field{name: "resource_id", values: []},
             %Field{name: "label", values: []},
             %Field{name: "scope_kind", values: []},
             %Field{name: "source_endpoint_id", values: []},
             %Field{name: "transport_id", values: []},
             %Field{name: "ground_station_id", values: []},
             %Field{name: "link_id", values: []},
             %Field{name: "contact_id", values: []},
             %Field{name: "adapter_key", values: []},
             %Field{name: "spacecraft_id", values: []},
             %Field{name: "value", values: []},
             %Field{name: "unit", values: []},
             %Field{name: "observed_at", values: []},
             %Field{name: "freshness_state", values: []},
             %Field{name: "age_ms", values: []},
             %Field{name: "error", values: []}
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :flight
    assert durable_opts[:dataset] == "operational_observables"

    assert_received {:runtime_ingress_latency, "org-1", "mission-1", runtime_opts}
    assert runtime_opts[:realm] == :flight
    assert runtime_opts[:dataset] == "operational_observables"
  end

  test "does not overlay process-local runtime-health ingress latency on replay reads" do
    parent = self()

    durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 8.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z],
          replay_run_id: "replay-run-1"
        }
      ]
    end

    runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})
      []
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:time_context, %{mode: :replay_run, replay_run_id: "replay-run-1"})
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [8.0]} | _rest
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :replay
    assert durable_opts[:dataset] == "operational_observables_replay"
    assert durable_opts[:replay_run_id] == "replay-run-1"

    refute_received {:runtime_ingress_latency, _, _, _}
  end

  test "resolves replay-scoped ingress processing latency history into a wide frame" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> Map.put(:time_context, %{
        mode: :replay_run,
        replay_run_id: "replay-run-1",
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        ingress_processing_latency_history_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:ingress_latency_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              transport_id: "transport-alpha",
              ground_station_id: "dss-14",
              link_id: "link-alpha",
              adapter_key: :tcp_socket,
              value: 4.5,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:01:00Z],
              replay_run_id: "replay-run-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              transport_id: "transport-alpha",
              ground_station_id: "dss-14",
              link_id: "link-alpha",
              adapter_key: :tcp_socket,
              value: 5.25,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:02:00Z],
              replay_run_id: "replay-run-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              value: 9.0,
              observed_at: ~U[2026-06-17 12:02:00Z],
              replay_run_id: "replay-run-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              value: 99.0,
              observed_at: ~U[2026-06-17 12:02:30Z],
              replay_run_id: "other-replay-run"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              value: 3.0,
              observed_at: ~U[2026-06-17 11:59:00Z],
              replay_run_id: "replay-run-1"
            }
          ]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert result.meta.supported_capability == :ingress_processing_latency_history
    assert result.meta.returned_frame_count == 1
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert frame.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.observable_id == "ingress.processing_latency_ms"
    assert frame.meta.resource_id == "endpoint-alpha"
    assert frame.meta.scope_kind == :source_endpoint
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.transport_id == "transport-alpha"
    assert frame.meta.ground_station_id == "dss-14"
    assert frame.meta.link_id == "link-alpha"
    assert frame.meta.adapter_key == :tcp_socket
    assert frame.meta.unit == "ms"
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.returned_points == 2

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    resource_link_id = frame.meta.resource_link_id
    links = frame.meta.links

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Field{
               name: "ingress.processing_latency_ms",
               values: [4.5, 5.25],
               metadata: %{
                 observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / endpoint-alpha",
                 unit: "ms",
                 resource_id: "endpoint-alpha",
                 scope_kind: :source_endpoint,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket,
                 resource_link_id: ^resource_link_id,
                 links: ^links
               }
             }
           ] = frame.fields

    assert_received {:ingress_latency_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "filters ingress processing latency history rows to contact scope" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:scope_context, %{
        primary: %{kind: :contact, mode: :one, ids: ["contact-alpha"]}
      })
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        ingress_processing_latency_history_snapshots_fun: fn _organization_id,
                                                             _mission_id,
                                                             _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              contact_id: "contact-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:01:00Z],
              source_event_id:
                "operational_event:operational_observable_snapshot:contact-ingress-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              contact_id: "contact-beta",
              value: 5.5,
              observed_at: ~U[2026-06-17 12:02:00Z],
              source_event_id:
                "operational_event:operational_observable_snapshot:contact-ingress-2"
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1
    assert frame.meta.resource_id == "endpoint-alpha"
    assert frame.meta.contact_id == "contact-alpha"

    assert frame.meta.links
           |> Enum.filter(&(&1.target in [:source_endpoint, :contact]))
           |> Enum.map(&{&1.target, &1.target_id}) == [
             {:source_endpoint, "endpoint-alpha"},
             {:contact, "contact-alpha"}
           ]

    assert %DataLink{
             target: :operational_event,
             target_id: "operational_event:operational_observable_snapshot:contact-ingress-1"
           } = Enum.find(frame.meta.links, &(&1.target == :operational_event))

    resource_link_id = frame.meta.resource_link_id
    field_links = Enum.filter(frame.meta.links, &(&1.target in [:source_endpoint, :contact]))

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z]]},
             %Field{
               name: "ingress.processing_latency_ms",
               values: [4.5],
               metadata: %{
                 observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / endpoint-alpha",
                 unit: "ms",
                 resource_id: "endpoint-alpha",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "endpoint-alpha",
                 contact_id: "contact-alpha",
                 resource_link_id: ^resource_link_id,
                 links: ^field_links
               }
             }
           ] = frame.fields
  end

  test "resolves empty ingress processing latency history as a chartable zero-point frame" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        ingress_processing_latency_history_snapshots_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:empty_ingress_latency_history_snapshots, organization_id, mission_id, opts}
          )

          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert result.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.observable_id == "ingress.processing_latency_ms"
    assert frame.meta.resource_id == "endpoint-alpha"
    assert frame.meta.scope_kind == :source_endpoint
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.unit == "ms"
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:source_endpoint, "endpoint-alpha"}
           ]

    resource_link_id = frame.meta.resource_link_id
    links = frame.meta.links

    assert [
             %Field{name: "time", values: []},
             %Field{
               name: "ingress.processing_latency_ms",
               values: [],
               metadata: %{
                 observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / endpoint-alpha",
                 unit: "ms",
                 resource_id: "endpoint-alpha",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "endpoint-alpha",
                 resource_link_id: ^resource_link_id,
                 links: ^links
               }
             }
           ] = frame.fields

    assert_received {:empty_ingress_latency_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves mixed operational metric history through product-specific wide frames" do
    result =
      source_request()
      |> Map.put(:observables, [
        "link.snr_db",
        "comms.transport.downlink_bitrate",
        "ingress.processing_latency_ms"
      ])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_metric_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_rf_metric_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              value: 11.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:01:00Z],
              source_event_id: "operational_event:operational_observable_snapshot:rf-snr-1"
            }
          ]
        end,
        transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_bitrate_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:01:30Z],
              source_event_id:
                "operational_event:operational_observable_snapshot:downlink-bitrate-1"
            }
          ]
        end,
        ingress_processing_latency_history_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_ingress_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              transport_id: "transport-alpha",
              ground_station_id: "dss-14",
              link_id: "link-alpha",
              adapter_key: :tcp_socket,
              value: 4.5,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:02:00Z],
              source_event_id: "operational_event:operational_observable_snapshot:ingress-1"
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [rf_frame, bitrate_frame, ingress_frame], warnings: []} =
             result

    assert result.meta.supported_capability == :operational_metric_history
    assert result.meta.returned_frame_count == 3

    assert Enum.map(result.frames, & &1.meta.supported_capability) == [
             :link_rf_metric_history,
             :transport_bitrate_history,
             :ingress_processing_latency_history
           ]

    assert Enum.map(result.frames, & &1.meta.product_family) == [
             :link_rf,
             :transport_bitrate,
             :runtime_ingress
           ]

    assert rf_frame.meta.observable_id == "link.snr_db"
    assert rf_frame.meta.resource_id == "link-alpha"
    assert rf_frame.meta.returned_points == 1
    assert [%Field{name: "time", values: [~U[2026-06-17 12:01:00Z]]}, rf_value] = rf_frame.fields
    assert rf_value.name == "link.snr_db"
    assert rf_value.values == [11.5]
    assert rf_value.metadata.resource_id == "link-alpha"

    assert operational_event_link_ids(rf_frame) == [
             "operational_event:operational_observable_snapshot:rf-snr-1"
           ]

    assert operational_event_evidence_ids(rf_frame) == [
             "operational_event:operational_observable_snapshot:rf-snr-1"
           ]

    assert bitrate_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert bitrate_frame.meta.resource_id == "transport-alpha"
    assert bitrate_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:30Z]]},
             bitrate_value
           ] = bitrate_frame.fields

    assert bitrate_value.name == "comms.transport.downlink_bitrate"
    assert bitrate_value.values == [12_500.5]
    assert bitrate_value.metadata.resource_id == "transport-alpha"

    assert operational_event_link_ids(bitrate_frame) == [
             "operational_event:operational_observable_snapshot:downlink-bitrate-1"
           ]

    assert operational_event_evidence_ids(bitrate_frame) == [
             "operational_event:operational_observable_snapshot:downlink-bitrate-1"
           ]

    assert ingress_frame.meta.observable_id == "ingress.processing_latency_ms"
    assert ingress_frame.meta.resource_id == "endpoint-alpha"
    assert ingress_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             ingress_value
           ] = ingress_frame.fields

    assert ingress_value.name == "ingress.processing_latency_ms"
    assert ingress_value.values == [4.5]
    assert ingress_value.metadata.resource_id == "endpoint-alpha"

    assert operational_event_link_ids(ingress_frame) == [
             "operational_event:operational_observable_snapshot:ingress-1"
           ]

    assert operational_event_evidence_ids(ingress_frame) == [
             "operational_event:operational_observable_snapshot:ingress-1"
           ]

    assert_received {:mixed_metric_history_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:realm] == :flight
    assert transport_opts[:dataset] == "operational_observables"

    assert_received {:mixed_rf_metric_history_snapshots, "org-1", "mission-1", rf_opts}
    assert rf_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert rf_opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:mixed_bitrate_history_snapshots, "org-1", "mission-1", bitrate_opts}
    assert bitrate_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert bitrate_opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:mixed_ingress_history_snapshots, "org-1", "mission-1", ingress_opts}
    assert ingress_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert ingress_opts[:to] == ~U[2026-06-17 12:03:00Z]
  end
end
