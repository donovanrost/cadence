defmodule Cadence.Dashboards.SourceRegistryEvidenceTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.{
    DataSources,
    Field,
    Frame,
    SourceRegistry
  }

  alias Cadence.OperationalEvents.EffectiveInterval

  test "enriches telemetry frames with selected operational interval evidence" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})
      [sample(point_id, "sample-1", 42, selected_at, "evidence-1")]
    end

    result =
      SourceRegistry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "source_endpoint", mode: "one", ids: ["endpoint-alpha"]}
          },
          sampling: %{mode: :raw_series, max_raw_points: 25}
        ),
        data_sources: [data_source("flight-questdb", range_scan?: true)],
        data_bindings: [data_binding("flight-questdb")],
        source_opts: %{telemetry: [history_fun: history_fun]},
        persisted?: true,
        source_binding_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          [effective_interval(:binding_set, "binding-set-interval-1", "runtime-apps")]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "application-binding-interval-1",
              "runtime-apps-packet-counter-rule"
            )
          ]
        end,
        catalog_revision_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:catalog_revision_intervals, organization_id, mission_id, opts})
          [effective_interval(:catalog_revision, "catalog-revision-interval-1", "catalog-rev-a")]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "binding-set-interval-1", kind: :binding_set},
             %{interval_id: "application-binding-interval-1", kind: :application_binding},
             %{interval_id: "catalog-revision-interval-1", kind: :catalog_revision}
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(frame.meta.evidence, :binding_set_interval, "binding-set-interval-1")

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "application-binding-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :catalog_revision_interval,
             "catalog-revision-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :operational_interval,
             "source-event-binding-set-interval-1"
           )

    assert evidence_ref(frame.meta.evidence, :source_binding, "flight-telemetry")

    assert [%Field{name: "time"}, %Field{name: "HK.counter"} = value_field] = frame.fields

    assert value_field.metadata.links
           |> hd()
           |> Map.fetch!(:context)
           |> get_in([:data, :source_binding_id]) == "flight-telemetry"

    assert_receive {:history, "org-1", "mission-1", "HK.counter", history_opts}
    assert history_opts[:from_receipt_time] == from_time
    assert history_opts[:to_receipt_time] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"

    assert_receive {:catalog_revision_intervals, "org-1", "mission-1", catalog_opts}
    assert catalog_opts[:at] == selected_at
    assert catalog_opts[:catalog_family] == :telemetry
  end

  test "enriches limits frames with selected catalog revision interval evidence" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_latest, organization_id, mission_id, point_id, opts})

      limit_event(point_id,
        receipt_time: selected_at,
        generation_time: selected_at,
        normalized_state: :yellow,
        limit_state: :yellow_high,
        violation: true
      )
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_intervals, organization_id, mission_id, point_id, opts})

      [
        limit_definition_interval(point_id,
          active_from: ~U[2026-06-21 20:00:00Z],
          active_to: nil
        )
      ]
    end

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :limits,
          observables: ["HK.counter"],
          sampling: %{mode: :latest_state},
          time_context: %{axis: :receipt_time, to: selected_at},
          scope_context: %{
            organization_id: "org-1",
            mission_id: "mission-1",
            primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
          }
        ),
        source_opts: %{limits: [latest_fun: latest_fun, interval_fun: interval_fun]},
        data_sources: [capability_variant_data_source(:limits)],
        data_bindings: [DataSources.default_flight_limits_binding()],
        persisted?: true,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          []
        end,
        catalog_revision_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:catalog_revision_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :catalog_revision,
              "limits-catalog-revision-interval-1",
              "catalog-rev-limits"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.source == :limits
    assert frame.meta.logical_source == :limits
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "limits-catalog-revision-interval-1", kind: :catalog_revision}
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :catalog_revision_interval,
             "limits-catalog-revision-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :operational_interval,
             "source-event-limits-catalog-revision-interval-1"
           )

    assert evidence_ref(frame.meta.evidence, :source_binding, "default_flight_limits")
    assert evidence_ref(frame.meta.evidence, :limit_event, "limit-event-1")

    assert_receive {:limits_latest, "org-1", "mission-1", "HK.counter", latest_opts}
    assert latest_opts[:data_source_id] == "managed_limits_projection"
    assert latest_opts[:dataset] == "telemetry_latest_limit_states"

    assert_receive {:limits_intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:data_source_id] == "managed_limits_projection"

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:catalog_revision_intervals, "org-1", "mission-1", catalog_opts}
    assert catalog_opts[:at] == selected_at
    assert catalog_opts[:catalog_family] == :telemetry
  end

  test "enriches operational metric-history frames with selected operational interval evidence" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["link.snr_db"],
          sampling: %{mode: :raw_series, max_raw_points: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "link", mode: "one", ids: ["link-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            transports_fun: fn organization_id, mission_id, opts ->
              send(parent, {:metric_history_transports, organization_id, mission_id, opts})

              [
                %{
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  ground_station_id: "dss-14",
                  link_assignment_id: "link-alpha",
                  display_name: "Transport Alpha"
                }
              ]
            end,
            link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:link_rf_metric_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "link.snr_db",
                  resource_id: "link-alpha",
                  link_id: "link-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  value: 12.5,
                  snr_db: 12.5,
                  unit: "dB",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:snr-sample-1"
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          [effective_interval(:binding_set, "metric-binding-set-interval-1", "runtime-apps")]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "metric-application-binding-interval-1",
              "runtime-apps-link-rule"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.logical_source == :operational_observables
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "metric-binding-set-interval-1", kind: :binding_set},
             %{interval_id: "metric-application-binding-interval-1", kind: :application_binding}
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :binding_set_interval,
             "metric-binding-set-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "metric-application-binding-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :operational_interval,
             "source-event-metric-binding-set-interval-1"
           )

    assert_receive {:metric_history_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:from] == from_time
    assert transport_opts[:to] == to_time

    assert_receive {:link_rf_metric_snapshots, "org-1", "mission-1", snapshot_opts}
    assert snapshot_opts[:from] == from_time
    assert snapshot_opts[:to] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"
  end

  test "enriches operational observable frames with source-health interval evidence" do
    parent = self()
    observed_at = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
    source_health_event_id = "source-health-operational-observables-1"
    operational_event_id = "operational_event:source_health_event:#{source_health_event_id}"

    status =
      source_health_status(%{
        source_health_event_id: source_health_event_id,
        source_health: :degraded,
        reason: :source_probe_failed,
        observed_at: observed_at,
        last_seen_at: observed_at
      })

    source_health_interval = %EffectiveInterval{
      interval_id: "effective_interval:source_health:#{operational_event_id}",
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: :source_health,
      subject_kind: :data_source,
      subject_id: "managed_operational_observables",
      starts_at: observed_at,
      source_event_id: operational_event_id,
      payload: %{
        "source_health_event_id" => source_health_event_id,
        "source_health" => "degraded",
        "reason" => "source_probe_failed"
      }
    }

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["comms.transport.connection_state"],
          sampling: %{mode: :latest}
        ),
        source_opts: %{
          operational_observables: [
            transports_fun: fn organization_id, mission_id, opts ->
              send(parent, {:source_health_transports, organization_id, mission_id, opts})

              [
                %{
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  ground_station_id: "dss-14",
                  display_name: "Transport Alpha"
                }
              ]
            end,
            source_endpoints_fun: fn organization_id, mission_id, opts ->
              send(parent, {:source_health_source_endpoints, organization_id, mission_id, opts})
              []
            end,
            connection_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:source_health_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "comms.transport.connection_state",
                  transport_id: "transport-alpha",
                  connection_state: :degraded,
                  observed_at: observed_at
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        source_health_events?: true,
        record_source_health_events?: false,
        source_health_statuses: [status],
        source_health_freshness: %{default_max_age_ms: 2_000_000_000},
        source_health_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:source_health_intervals, organization_id, mission_id, opts})
          [source_health_interval]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert result.meta.source_health == :degraded
    assert result.meta.source_health_event_id == source_health_event_id
    assert result.meta.source_health_interval_id == source_health_interval.interval_id
    assert result.meta.source_health_interval_source_event_id == operational_event_id
    assert result.meta.degraded?

    assert frame.meta.source_health == :degraded
    assert frame.meta.source_health_event_id == source_health_event_id
    assert frame.meta.source_health_interval_id == source_health_interval.interval_id
    assert frame.meta.source_health_interval.source_event_id == operational_event_id
    assert frame.meta.source_health_interval.kind == :source_health
    assert frame.meta.degraded?

    assert evidence_ref(
             frame.meta.evidence,
             :source_health_interval,
             source_health_interval.interval_id
           )

    assert evidence_ref(frame.meta.evidence, :operational_interval, operational_event_id)
    assert evidence_ref(frame.meta.evidence, :source_health_event, source_health_event_id)

    assert_received {:source_health_intervals, "org-1", "mission-1", interval_opts}
    assert interval_opts[:at] == observed_at
    assert interval_opts[:logical_source] == :operational_observables
    assert interval_opts[:data_source_id] == "managed_operational_observables"
    assert interval_opts[:source_binding_id] == "default_flight_operational_observables"
    assert interval_opts[:realm] == :flight
    assert interval_opts[:dataset] == "operational_observables"

    assert_received {:source_health_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:data_source_id] == "managed_operational_observables"

    assert_received {:source_health_source_endpoints, "org-1", "mission-1", endpoint_opts}
    assert endpoint_opts[:dataset] == "operational_observables"

    assert_received {:source_health_snapshots, "org-1", "mission-1", snapshot_opts}
    assert snapshot_opts[:source_binding_id] == "default_flight_operational_observables"
  end

  test "enriches all operational metric-history product frames with selected intervals" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: [
            "link.snr_db",
            "comms.transport.downlink_bitrate",
            "ingress.processing_latency_ms"
          ],
          sampling: %{mode: :raw_series, max_raw_points: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "link", mode: "one", ids: ["link-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            transports_fun: fn organization_id, mission_id, opts ->
              send(parent, {:metric_history_transports, organization_id, mission_id, opts})

              [
                %{
                  transport_id: "transport-alpha",
                  display_name: "Transport Alpha",
                  metadata: %{
                    source_endpoint_id: "endpoint-alpha",
                    ground_station_id: "dss-14",
                    link_assignment_id: "link-alpha"
                  }
                }
              ]
            end,
            link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:link_rf_metric_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "link.snr_db",
                  resource_id: "link-alpha",
                  link_id: "link-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  value: 12.5,
                  snr_db: 12.5,
                  unit: "dB",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:snr-sample-1"
                }
              ]
            end,
            transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
              send(parent, {:transport_bitrate_snapshots, organization_id, mission_id, opts})

              [
                %{
                  observable_id: "comms.transport.downlink_bitrate",
                  transport_id: "transport-alpha",
                  source_endpoint_id: "endpoint-alpha",
                  link_id: "link-alpha",
                  value: 96_000,
                  unit: "bit/s",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:bitrate-sample-1"
                }
              ]
            end,
            ingress_processing_latency_history_snapshots_fun: fn organization_id,
                                                                 mission_id,
                                                                 opts ->
              send(
                parent,
                {:ingress_latency_history_snapshots, organization_id, mission_id, opts}
              )

              [
                %{
                  observable_id: "ingress.processing_latency_ms",
                  mission_id: mission_id,
                  source_endpoint_id: "endpoint-alpha",
                  spacecraft_id: "spacecraft-alpha",
                  transport_id: "transport-alpha",
                  ground_station_id: "dss-14",
                  link_id: "link-alpha",
                  adapter_key: :tcp_socket,
                  value: 4.5,
                  unit: "ms",
                  observed_at: selected_at,
                  source_event_id: "operational_event:metric_sample:ingress-sample-1"
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :binding_set,
              "metric-history-binding-set-interval-1",
              "runtime-apps"
            )
          ]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "metric-history-application-binding-interval-1",
              "runtime-apps-link-rule"
            )
          ]
        end
      )

    assert %{frames: frames} = result
    assert length(frames) == 3

    expected_frames = %{
      "link.snr_db" => {:link_rf_metric_history, :link_rf, :link, "link-alpha"},
      "comms.transport.downlink_bitrate" =>
        {:transport_bitrate_history, :transport_bitrate, :transport, "transport-alpha"},
      "ingress.processing_latency_ms" =>
        {:ingress_processing_latency_history, :runtime_ingress, :source_endpoint,
         "endpoint-alpha"}
    }

    for {observable_id, {capability, product_family, scope_kind, resource_id}} <- expected_frames do
      frame = Enum.find(frames, &(&1.meta.observable_id == observable_id))
      assert %Frame{} = frame
      assert frame.meta.logical_source == :operational_observables
      assert frame.meta.supported_capability == capability
      assert frame.meta.product_family == product_family
      assert frame.meta.scope_kind == scope_kind
      assert frame.meta.resource_id == resource_id
      assert frame.meta.source_endpoint_id == "endpoint-alpha"
      assert frame.meta.selected_operational_interval_at == selected_at

      assert [
               %{interval_id: "metric-history-binding-set-interval-1", kind: :binding_set},
               %{
                 interval_id: "metric-history-application-binding-interval-1",
                 kind: :application_binding
               }
             ] = frame.meta.selected_operational_intervals

      assert evidence_ref(
               frame.meta.evidence,
               :binding_set_interval,
               "metric-history-binding-set-interval-1"
             )

      assert evidence_ref(
               frame.meta.evidence,
               :application_binding_interval,
               "metric-history-application-binding-interval-1"
             )
    end

    assert_receive {:metric_history_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:from] == from_time
    assert transport_opts[:to] == to_time

    assert_receive {:link_rf_metric_snapshots, "org-1", "mission-1", link_rf_opts}
    assert link_rf_opts[:from] == from_time
    assert link_rf_opts[:to] == to_time

    assert_receive {:transport_bitrate_snapshots, "org-1", "mission-1", bitrate_opts}
    assert bitrate_opts[:from] == from_time
    assert bitrate_opts[:to] == to_time

    assert_receive {:ingress_latency_history_snapshots, "org-1", "mission-1", ingress_opts}
    assert ingress_opts[:from] == from_time
    assert ingress_opts[:to] == to_time
  end

  test "enriches runtime ingress metric-history frames with selected intervals from frame source-endpoint fields" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["ingress.processing_latency_ms"],
          sampling: %{mode: :raw_series, max_raw_points: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "source_endpoint", mode: "one", ids: ["endpoint-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            ingress_processing_latency_history_snapshots_fun: fn organization_id,
                                                                 mission_id,
                                                                 opts ->
              send(
                parent,
                {:ingress_latency_history_snapshots, organization_id, mission_id, opts}
              )

              [
                %{
                  observable_id: "ingress.processing_latency_ms",
                  mission_id: mission_id,
                  source_endpoint_id: "endpoint-alpha",
                  spacecraft_id: "spacecraft-alpha",
                  transport_id: "transport-alpha",
                  ground_station_id: "dss-14",
                  link_id: "link-alpha",
                  adapter_key: :tcp_socket,
                  value: 4.5,
                  unit: "ms",
                  observed_at: selected_at
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :binding_set,
              "ingress-binding-set-interval-1",
              "runtime-apps"
            )
          ]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "ingress-application-binding-interval-1",
              "runtime-apps-ingress-rule"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.logical_source == :operational_observables
    assert frame.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "ingress-binding-set-interval-1", kind: :binding_set},
             %{
               interval_id: "ingress-application-binding-interval-1",
               kind: :application_binding
             }
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :binding_set_interval,
             "ingress-binding-set-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "ingress-application-binding-interval-1"
           )

    assert %Field{metadata: %{source_endpoint_id: "endpoint-alpha"}} =
             Enum.find(frame.fields, &(&1.name == "ingress.processing_latency_ms"))

    assert_receive {:ingress_latency_history_snapshots, "org-1", "mission-1", snapshot_opts}
    assert snapshot_opts[:from] == from_time
    assert snapshot_opts[:to] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"
  end

  test "enriches transport execution frames with selected intervals from frame source-endpoint fields" do
    selected_at = ~U[2026-06-21 20:30:00Z]
    from_time = ~U[2026-06-21 20:00:00Z]
    to_time = ~U[2026-06-21 21:00:00Z]
    parent = self()

    result =
      SourceRegistry.resolve(
        source_request(
          logical_source: :operational_observables,
          observables: ["comms.transport.execution_state"],
          sampling: %{mode: :event_history, limit: 25},
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          scope_context: %{
            mission_id: "mission-1",
            primary: %{kind: "transport", mode: "one", ids: ["transport-alpha"]}
          }
        ),
        source_opts: %{
          operational_observables: [
            transport_execution_intervals_fun: fn organization_id, mission_id, opts ->
              send(parent, {:transport_execution_intervals, organization_id, mission_id, opts})

              [
                %EffectiveInterval{
                  interval_id: "transport-execution-interval-1",
                  organization_id: organization_id,
                  mission_id: mission_id,
                  kind: :transport_execution,
                  subject_kind: :transport,
                  subject_id: "transport-alpha",
                  starts_at: selected_at,
                  ends_at: ~U[2026-06-21 20:45:00Z],
                  source_event_id: "transport-execution-event-1",
                  payload: %{
                    "capability_instance_id" => "transport-alpha",
                    "source_endpoint_id" => "endpoint-alpha",
                    "ground_station_id" => "dss-14",
                    "link_assignment_id" => "link-alpha",
                    "event_kind" => "initialized"
                  }
                }
              ]
            end
          ]
        },
        data_sources: [DataSources.default_operational_observables_data_source()],
        data_bindings: [DataSources.default_flight_operational_observables_binding()],
        persisted?: true,
        operational_interval_at: selected_at,
        binding_set_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:binding_set_intervals, organization_id, mission_id, opts})
          [effective_interval(:binding_set, "transport-binding-set-interval-1", "runtime-apps")]
        end,
        application_binding_intervals_fun: fn organization_id, mission_id, opts ->
          send(parent, {:application_binding_intervals, organization_id, mission_id, opts})

          [
            effective_interval(
              :application_binding,
              "transport-application-binding-interval-1",
              "runtime-apps-transport-rule"
            )
          ]
        end
      )

    assert %{frames: [%Frame{} = frame]} = result
    assert frame.meta.logical_source == :operational_observables
    assert frame.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.selected_operational_interval_at == selected_at

    assert [
             %{interval_id: "transport-binding-set-interval-1", kind: :binding_set},
             %{
               interval_id: "transport-application-binding-interval-1",
               kind: :application_binding
             }
           ] = frame.meta.selected_operational_intervals

    assert evidence_ref(
             frame.meta.evidence,
             :binding_set_interval,
             "transport-binding-set-interval-1"
           )

    assert evidence_ref(
             frame.meta.evidence,
             :application_binding_interval,
             "transport-application-binding-interval-1"
           )

    assert %Field{values: ["endpoint-alpha"]} =
             Enum.find(frame.fields, &(&1.name == "source_endpoint_id"))

    assert_receive {:transport_execution_intervals, "org-1", "mission-1", interval_opts}
    assert interval_opts[:from] == from_time
    assert interval_opts[:to] == to_time

    assert_receive {:binding_set_intervals, "org-1", "mission-1", binding_opts}
    assert binding_opts[:at] == selected_at

    assert_receive {:application_binding_intervals, "org-1", "mission-1", application_opts}
    assert application_opts[:at] == selected_at
    assert application_opts[:source_endpoint_ref] == "endpoint-alpha"
  end
end
