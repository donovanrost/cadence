defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection

  describe "selected refs" do
    test "builds selected refs from data links and event params" do
      link = %DataLink{
        link_id: "link-1",
        target: :telemetry_point,
        target_id: "HK.counter",
        source: :chart_point,
        context: %{
          scope: %{
            "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc-1"]}
          },
          data: %{
            "realm" => "rehearsal",
            "time_mode" => "ignored-data-time-mode",
            "source_contexts" => %{
              "telemetry" => %{
                "view" => "canonical",
                "data_source_id" => "questdb-rehearsal",
                "source_binding_id" => "binding-1"
              }
            },
            "replay_run_id" => "replay-1"
          },
          time: %{"mode" => "archive", "axis" => "receipt_time"},
          limit: %{"semantics_mode" => "observed"},
          observable_id: "obs-1",
          selection: %{placement_id: "stored-placement", timestamp_ms: 11}
        }
      }

      assert DataLinkSelection.selected_ref(link, %{
               "placement-id" => "placement-1",
               "timestamp-ms" => "12345",
               "series-role" => "compare",
               "compare-of" => "HK.counter",
               "data-view" => "canonical"
             }) == %{
               "link_id" => "link-1",
               "target" => "telemetry_point",
               "target_id" => "HK.counter",
               "target_text" => "telemetry point",
               "timestamp_ms" => 12_345,
               "placement_id" => "placement-1",
               "source" => "chart_point",
               "scope_kind" => "spacecraft",
               "scope_id" => "sc-1",
               "spacecraft_id" => "sc-1",
               "realm" => "rehearsal",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "data_view" => "canonical",
               "series_role" => "compare",
               "compare_of" => "HK.counter",
               "replay_run_id" => "replay-1",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "binding-1",
               "limit_mode" => "observed",
               "observable_id" => "obs-1"
             }
    end

    test "selected refs use operational resource identity when scope contains multiple resources" do
      link = %DataLink{
        link_id: "transport:transport-beta:ops-request-1",
        target: :transport,
        target_id: "transport-beta",
        source: :frame,
        context: %{
          scope: %{
            primary: %{
              kind: "transport",
              mode: "many",
              ids: ["transport-alpha", "transport-beta"]
            }
          },
          data: %{
            realm: "flight",
            source_contexts: %{
              operational_observables: %{
                data_source_id: "managed-operational",
                source_binding_id: "ops-binding"
              }
            }
          },
          time: %{mode: "live", axis: "generation_time"},
          logical_source: :operational_observables,
          observable_id: "comms.transport.downlink_bitrate",
          operational_resource: %{
            resource_id: "transport-beta",
            scope_kind: :transport,
            transport_id: "transport-beta",
            source_endpoint_id: "endpoint-beta",
            ground_station_id: "dss-63",
            link_id: "link-beta",
            adapter_key: :tcp_socket
          }
        }
      }

      assert DataLinkSelection.selected_ref(link, %{"placement-id" => "placement-bitrate"}) ==
               %{
                 "link_id" => "transport:transport-beta:ops-request-1",
                 "target" => "transport",
                 "target_id" => "transport-beta",
                 "target_text" => "transport",
                 "placement_id" => "placement-bitrate",
                 "source" => "frame",
                 "scope_kind" => "transport",
                 "scope_id" => "transport-beta",
                 "scope_ids" => "transport-alpha,transport-beta",
                 "transport_id" => "transport-beta",
                 "source_endpoint_id" => "endpoint-beta",
                 "ground_station_id" => "dss-63",
                 "scope_link_id" => "link-beta",
                 "realm" => "flight",
                 "time_mode" => "live",
                 "time_axis" => "generation_time",
                 "data_source_id" => "managed-operational",
                 "source_binding_id" => "ops-binding",
                 "observable_id" => "comms.transport.downlink_bitrate"
               }

      selection_query =
        link
        |> DataLinkSelection.selected_ref(%{"placement-id" => "placement-bitrate"})
        |> DataLinkSelection.selection_query_from_ref()

      assert selection_query.params["selected_source_endpoint_id"] == "endpoint-beta"
      assert selection_query.params["selected_ground_station_id"] == "dss-63"
      assert selection_query.params["selected_scope_link_id"] == "link-beta"
    end

    test "selected refs use clicked contact identity when contact scope contains multiple contacts" do
      link = %DataLink{
        link_id: "contact:contact-beta:ops-request-1",
        target: :contact,
        target_id: "contact-beta",
        source: :frame,
        context: %{
          scope: %{
            primary: %{
              kind: "contact",
              mode: "many",
              ids: ["contact-alpha", "contact-beta"]
            }
          },
          data: %{
            realm: "flight",
            source_contexts: %{
              operational_observables: %{
                data_source_id: "managed-operational",
                source_binding_id: "ops-binding"
              }
            }
          },
          time: %{mode: "live", axis: "generation_time"},
          logical_source: :operational_observables,
          observable_id: "contacts.phase"
        }
      }

      assert DataLinkSelection.selected_ref(link, %{"placement-id" => "placement-contact"}) ==
               %{
                 "link_id" => "contact:contact-beta:ops-request-1",
                 "target" => "contact",
                 "target_id" => "contact-beta",
                 "target_text" => "contact",
                 "placement_id" => "placement-contact",
                 "source" => "frame",
                 "scope_kind" => "contact",
                 "scope_id" => "contact-beta",
                 "scope_ids" => "contact-alpha,contact-beta",
                 "contact_ids" => "contact-alpha,contact-beta",
                 "realm" => "flight",
                 "time_mode" => "live",
                 "time_axis" => "generation_time",
                 "data_source_id" => "managed-operational",
                 "source_binding_id" => "ops-binding",
                 "observable_id" => "contacts.phase"
               }
    end

    test "selected refs preserve comparison source metadata from data links" do
      link = %DataLink{
        link_id: "comparison:placement-ops",
        target: :comparison_finding,
        target_id: "placement-ops",
        source: :annotation,
        context: %{
          comparison: %{
            widget_id: "widget-ops",
            widget_title: "Transport State",
            widget_type: "status_matrix",
            widget_source: "operational_observables",
            primary_kind: "status_matrix",
            compare_kind: "status_matrix",
            primary_observables: "comms.transport.connection_state:transport-alpha",
            compare_observables: "comms.transport.connection_state:transport-alpha"
          }
        }
      }

      assert DataLinkSelection.selected_ref(link, %{}) == %{
               "link_id" => "comparison:placement-ops",
               "target" => "comparison_finding",
               "target_id" => "placement-ops",
               "target_text" => "comparison finding",
               "source" => "annotation",
               "widget_id" => "widget-ops",
               "widget_title" => "Transport State",
               "widget_type" => "status_matrix",
               "widget_source" => "operational_observables",
               "primary_kind" => "status_matrix",
               "compare_kind" => "status_matrix",
               "primary_observables" => "comms.transport.connection_state:transport-alpha",
               "compare_observables" => "comms.transport.connection_state:transport-alpha"
             }
    end

    test "falls back to link selection context when event params omit selection values" do
      link = %DataLink{
        link_id: "link-2",
        target: :limit_definition,
        target_id: "limit-1",
        source: :annotation,
        context: %{
          "scope" => %{"scope_kind" => "mission", "scope_id" => "mission-1"},
          "selection" => %{"placement_id" => "placement-2", "timestamp_ms" => 55}
        }
      }

      assert DataLinkSelection.selected_ref(link, %{}) == %{
               "link_id" => "link-2",
               "target" => "limit_definition",
               "target_id" => "limit-1",
               "target_text" => "limit definition",
               "timestamp_ms" => 55,
               "placement_id" => "placement-2",
               "source" => "annotation",
               "scope_kind" => "mission",
               "scope_id" => "mission-1"
             }
    end
  end
end
