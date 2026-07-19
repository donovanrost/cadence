defmodule CadenceWeb.Assets.DashboardRenderedViewportOperationalFixtures do
  @moduledoc false

  import ExUnit.Assertions
  alias Cadence.Dashboards.Document
  alias Cadence.Dashboards.Placement
  alias Cadence.Dashboards.RenderItem
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.OperationalEvents.EffectiveInterval

  def operational_rf_state_timeline_source_execution_opts do
    [
      source_result_cache?: false,
      source_opts: %{
        operational_observables: [
          link_rf_lock_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-link-rf-lock-state-revision"
          end,
          link_rf_frame_sync_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-link-rf-frame-sync-state-revision"
          end,
          link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
            [
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                lock_state: :acquiring,
                observed_at: ~U[2026-06-17 12:00:30Z]
              },
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                lock_state: :locked,
                observed_at: ~U[2026-06-17 12:01:30Z]
              },
              %{
                transport_id: "browser-transport-beta",
                source_endpoint_id: "browser-source-endpoint-beta",
                ground_station_id: "dss-63",
                link_assignment_id: "link-beta",
                adapter_key: :tcp_socket,
                lock_state: :unlocked,
                observed_at: ~U[2026-06-17 12:01:30Z]
              }
            ]
          end,
          link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
            [
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                frame_sync_state: :acquiring,
                observed_at: ~U[2026-06-17 12:00:45Z]
              },
              %{
                transport_id: "browser-transport-alpha",
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_assignment_id: "link-alpha",
                adapter_key: :tcp_socket,
                frame_sync_state: :synchronized,
                observed_at: ~U[2026-06-17 12:02:00Z]
              },
              %{
                transport_id: "browser-transport-beta",
                source_endpoint_id: "browser-source-endpoint-beta",
                ground_station_id: "dss-63",
                link_assignment_id: "link-beta",
                adapter_key: :tcp_socket,
                frame_sync_state: :lost,
                observed_at: ~U[2026-06-17 12:02:00Z]
              }
            ]
          end
        ]
      }
    ]
  end

  def operational_transport_execution_state_timeline_source_execution_opts do
    [
      source_result_cache?: false,
      source_opts: %{
        operational_observables: [
          transport_execution_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-transport-execution-state-revision"
          end,
          transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
            [
              transport_execution_interval(
                "browser-transport-execution-alpha-1",
                "browser-transport-alpha",
                :initialized,
                ~U[2026-06-17 12:00:10Z],
                ~U[2026-06-17 12:01:30Z],
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_id: "link-alpha",
                source_event_id: "browser-transport-execution-event-alpha-1"
              ),
              transport_execution_interval(
                "browser-transport-execution-alpha-2",
                "browser-transport-alpha",
                :transport_event_handled,
                ~U[2026-06-17 12:01:30Z],
                ~U[2026-06-17 12:03:30Z],
                source_endpoint_id: "browser-source-endpoint-alpha",
                ground_station_id: "dss-14",
                link_id: "link-alpha",
                source_event_id: "browser-transport-execution-event-alpha-2"
              ),
              transport_execution_interval(
                "browser-transport-execution-beta-1",
                "browser-transport-beta",
                :timer_handled,
                ~U[2026-06-17 12:02:00Z],
                ~U[2026-06-17 12:03:00Z],
                source_endpoint_id: "browser-source-endpoint-beta",
                ground_station_id: "dss-63",
                link_id: "link-beta",
                contact_id: "browser-contact-beta",
                path_id: "browser-uplink-beta",
                source_event_id: "browser-transport-execution-event-beta-1"
              )
            ]
          end
        ]
      }
    ]
  end

  def operational_transport_execution_state_timeline_source_unavailable_opts do
    [
      source_result_cache?: false,
      source_opts: %{
        operational_observables: [
          transport_execution_state_revision_fun: fn _organization_id, _mission_id, _opts ->
            "browser-transport-execution-state-unavailable-revision"
          end,
          transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
            raise "browser transport execution source unavailable"
          end
        ]
      }
    ]
  end

  def transport_execution_interval(
        interval_id,
        transport_id,
        event_kind,
        starts_at,
        ends_at,
        opts
      ) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "browser-org",
      mission_id: "browser-mission",
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: transport_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: Keyword.fetch!(opts, :source_event_id),
      payload: %{
        "capability_instance_id" => transport_id,
        "transport_record_id" => "record-#{interval_id}",
        "source_endpoint_id" => Keyword.get(opts, :source_endpoint_id),
        "ground_station_id" => Keyword.get(opts, :ground_station_id),
        "link_assignment_id" => Keyword.get(opts, :link_id),
        "contact_id" => Keyword.get(opts, :contact_id, "browser-contact-alpha"),
        "path_id" => Keyword.get(opts, :path_id, "browser-uplink-alpha"),
        "event_kind" => Atom.to_string(event_kind)
      }
    }
  end

  def build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  def fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  def persist_dashboard_defaults!(org, mission, dashboard, defaults) do
    %Document{} = document = fetch_dashboard_document!(org, mission, dashboard)
    updated_document = %Document{document | defaults: defaults}

    assert {:ok, %Document{} = draft_document} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               updated_document,
               expected_version: Document.version(document)
             )

    draft_version = Document.version(draft_document)

    assert {:ok, %Cadence.Dashboards.Version{document: %Document{} = published_document}} =
             Cadence.Dashboards.publish_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               draft_version,
               expected_version: draft_version
             )

    published_document
  end

  def render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  def placement_by_id!(%Document{} = document, placement_id) do
    Enum.find(document.placements, &(&1.placement_id == placement_id))
  end

  def persist_repeated_dashboard_document!(org, mission, spacecraft_ids) do
    [primary_spacecraft_id | _] = spacecraft_ids

    document = %Document{
      dashboard_id: "dashboard-repeat-render-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Repeat Render Browser",
      defaults: %{
        "scope" => %{
          "primary" => %{
            "kind" => "spacecraft",
            "mode" => "many",
            "ids" => spacecraft_ids
          }
        },
        "time" => %{
          "mode" => "live",
          "axis" => "generation_time",
          "range" => %{"kind" => "relative", "duration_ms" => 300_000}
        },
        "data" => %{
          "realm" => "flight",
          "source_mode" => "primary",
          "allowed_realms" => ["flight"]
        }
      },
      placements: [
        %Placement{
          placement_id: "placement-repeat",
          layout: %{x: 0, y: 0, w: 4, h: 3},
          repeat: %{axis: :scope, over: :spacecraft, layout: :wrap_grid, max_instances: 12},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.status_matrix",
            widget_type_version: 1,
            title: "Repeated Status",
            binding: %{
              source: :telemetry,
              observables: ["HK.counter"],
              scope_mode: :repeat,
              sampling: :latest,
              overlays: []
            },
            options: %{}
          }
        },
        %Placement{
          placement_id: "placement-trend",
          layout: %{x: 0, y: 3, w: 6, h: 3},
          scope_override: %{
            primary: %{kind: "spacecraft", mode: "one", ids: [primary_spacecraft_id]}
          },
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Counter Trend",
            binding: %{
              source: :telemetry,
              observables: ["HK.counter"],
              scope_mode: :override,
              sampling: :raw_series,
              overlays: []
            },
            options: %{}
          }
        }
      ]
    }

    assert {:ok, persisted} = Cadence.Dashboards.persist_document(org.organization_id, document)
    persisted
  end

  def persist_replay_operational_metric_time_series_dashboard!(
        org,
        mission,
        transport_id,
        opts
      ) do
    data_override = Keyword.get(opts, :data_override)
    overlays = Keyword.get(opts, :overlays, [])
    source_endpoint_id = Keyword.fetch!(opts, :source_endpoint_id)

    document = %Document{
      dashboard_id: "dashboard-replay-operational-metric-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Replay Operational Metric Time Series Browser",
      placements: [
        %Placement{
          placement_id: "placement-rf-snr-history",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          data_override: data_override,
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR Replay",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-transport-bitrate-history",
          layout: %{x: 6, y: 0, w: 6, h: 3},
          data_override: data_override,
          scope_override: %{
            primary: %{kind: "transport", mode: "one", ids: [transport_id]}
          },
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Transport Bitrate Replay",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.downlink_bitrate",
                "comms.transport.uplink_bitrate"
              ],
              scope_mode: :override,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-rf-ebn0-history",
          layout: %{x: 0, y: 3, w: 6, h: 3},
          data_override: data_override,
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF Eb/N0 Replay",
            binding: %{
              source: :operational_observables,
              observables: ["link.eb_n0_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-rf-mixed-history",
          layout: %{x: 6, y: 3, w: 6, h: 3},
          data_override: data_override,
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF Mixed Metric Replay",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db", "link.symbol_rate_sps"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        },
        %Placement{
          placement_id: "placement-ingress-latency-history",
          layout: %{x: 0, y: 6, w: 6, h: 3},
          data_override: data_override,
          scope_override: %{
            primary: %{kind: "source_endpoint", mode: "one", ids: [source_endpoint_id]}
          },
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "Ingress Latency Replay",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"],
              scope_mode: :override,
              sampling: :raw_series,
              overlays: overlays
            },
            options: %{legend: true}
          }
        }
      ]
    }

    assert {:ok, persisted} = Cadence.Dashboards.persist_document(org.organization_id, document)
    persisted
  end

  def repeated_placement_id(placement_id, spacecraft_id) do
    "#{placement_id}__repeat__spacecraft__#{spacecraft_id}"
  end
end
