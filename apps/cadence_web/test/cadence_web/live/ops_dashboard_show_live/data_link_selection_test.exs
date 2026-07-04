defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  describe "selection query parsing" do
    test "builds selection queries from URL params" do
      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "previous-event-1",
            "relationship_kind" => "source_event"
          }
        ])

      query =
        DataLinkSelection.selection_query_from_params(
          %{
            "selected_link" => " link-1 ",
            "selected_target" => "telemetry_point",
            "selected_id" => "HK.counter",
            "selected_placement" => "placement-1",
            "selected_time" => "12345",
            "selected_data_view" => "canonical",
            "selected_series_role" => "compare",
            "selected_compare_of" => "HK.counter",
            "realm" => "rehearsal",
            "data_source_id" => "questdb-rehearsal",
            "source_binding_id" => "binding-1",
            "time_mode" => "archive",
            "time_axis" => "receipt_time",
            "replay_run_id" => "replay-1",
            "nav_from_link_id" => "source-link-1",
            "nav_from_target" => "telemetry_backfill_lifecycle_event",
            "nav_from_target_id" => "source-event-1",
            "nav_from_label" => "Source event",
            "nav_from_relationship_kind" => "retry_event",
            "nav_from_relationship_label" => "Retry event HK.counter",
            "nav_trail" => nav_trail
          },
          :data_link
        )

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_link" => "link-1",
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "selected_data_view" => "canonical",
               "selected_series_role" => "compare",
               "selected_compare_of" => "HK.counter",
               "realm" => "rehearsal",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "binding-1",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "replay_run_id" => "replay-1",
               "nav_from_link_id" => "source-link-1",
               "nav_from_target" => "telemetry_backfill_lifecycle_event",
               "nav_from_target_id" => "source-event-1",
               "nav_from_label" => "Source event",
               "nav_from_relationship_kind" => "retry_event",
               "nav_from_relationship_label" => "Retry event HK.counter",
               "nav_trail" => nav_trail
             }
    end

    test "drops invalid target-only queries without a link id" do
      assert is_nil(
               DataLinkSelection.selection_query_from_params(
                 %{"selected_target" => "not_a_resolvable_target", "selected_id" => "id-1"},
                 :data_link
               )
             )
    end

    test "does not parse data-link selection while evidence panel is active" do
      assert is_nil(
               DataLinkSelection.selection_query_from_params(
                 %{"selected_link" => "link-1"},
                 :evidence
               )
             )
    end

    test "does not parse data-link selection while versions panel is active" do
      assert DataLinkSelection.panel_from_params(%{"panel" => "versions"}) == :versions

      assert is_nil(
               DataLinkSelection.selection_query_from_params(
                 %{
                   "panel" => "versions",
                   "selected_link" => "link-1",
                   "selected_target" => "telemetry_sample",
                   "selected_id" => "sample-1"
                 },
                 :versions
               )
             )
    end

    test "round trips comparison source metadata through query and event params" do
      query =
        DataLinkSelection.selection_query_from_params(
          %{
            "selected_target" => "comparison_finding",
            "selected_id" => "placement-ops",
            "selected_widget" => "widget-ops",
            "selected_widget_title" => "Transport State",
            "selected_widget_type" => "status_matrix",
            "selected_widget_source" => "operational_observables",
            "selected_primary_kind" => "status_matrix",
            "selected_compare_kind" => "status_matrix",
            "selected_primary_observables" => "comms.transport.connection_state:transport-alpha",
            "selected_compare_observables" => "comms.transport.connection_state:transport-alpha"
          },
          :data_link
        )

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_target" => "comparison_finding",
               "selected_id" => "placement-ops",
               "selected_widget" => "widget-ops",
               "selected_widget_title" => "Transport State",
               "selected_widget_type" => "status_matrix",
               "selected_widget_source" => "operational_observables",
               "selected_primary_kind" => "status_matrix",
               "selected_compare_kind" => "status_matrix",
               "selected_primary_observables" =>
                 "comms.transport.connection_state:transport-alpha",
               "selected_compare_observables" =>
                 "comms.transport.connection_state:transport-alpha"
             }

      assert DataLinkSelection.event_params_from_selection_query(query) == %{
               "widget-id" => "widget-ops",
               "widget-title" => "Transport State",
               "widget-type" => "status_matrix",
               "widget-source" => "operational_observables",
               "primary-kind" => "status_matrix",
               "compare-kind" => "status_matrix",
               "primary-observables" => "comms.transport.connection_state:transport-alpha",
               "compare-observables" => "comms.transport.connection_state:transport-alpha"
             }
    end

    test "builds selection queries from selected refs" do
      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "previous-event-1",
            "relationship_kind" => "source_event"
          }
        ])

      selected_ref = %{
        "link_id" => "link-1",
        "target" => "telemetry_point",
        "target_id" => "HK.counter",
        "placement_id" => "placement-1",
        "timestamp_ms" => 12_345,
        "data_view" => "canonical",
        "series_role" => "compare",
        "compare_of" => "HK.counter",
        "primary_data_management" => "recomputed_analysis",
        "compare_data_management" => "degraded",
        "realm" => "rehearsal",
        "data_source_id" => "questdb-rehearsal",
        "source_binding_id" => "binding-1",
        "time_mode" => "archive",
        "time_axis" => "receipt_time",
        "replay_run_id" => "replay-1",
        "nav_from_link_id" => "source-link-1",
        "nav_from_target" => "telemetry_backfill_lifecycle_event",
        "nav_from_target_id" => "source-event-1",
        "nav_from_label" => "Source event",
        "nav_from_relationship_kind" => "retry_event",
        "nav_from_relationship_label" => "Retry event HK.counter",
        "nav_trail" => nav_trail
      }

      query = DataLinkSelection.selection_query_from_ref(selected_ref)

      assert %SelectionQuery{} = query

      assert SelectionQuery.to_params(query) == %{
               "selected_link" => "link-1",
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "selected_data_view" => "canonical",
               "selected_series_role" => "compare",
               "selected_compare_of" => "HK.counter",
               "selected_primary_data_management" => "recomputed_analysis",
               "selected_compare_data_management" => "degraded",
               "realm" => "rehearsal",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "binding-1",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "replay_run_id" => "replay-1",
               "nav_from_link_id" => "source-link-1",
               "nav_from_target" => "telemetry_backfill_lifecycle_event",
               "nav_from_target_id" => "source-event-1",
               "nav_from_label" => "Source event",
               "nav_from_relationship_kind" => "retry_event",
               "nav_from_relationship_label" => "Retry event HK.counter",
               "nav_trail" => nav_trail
             }
    end
  end

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

    test "keeps selected refs that match the active live runtime context" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "spacecraft_id" => "sc-1",
        "realm" => "rehearsal",
        "data_view" => "canonical",
        "data_source_id" => "questdb-rehearsal",
        "source_binding_id" => "binding-1",
        "limit_mode" => "observed"
      }

      runtime_context =
        runtime_context(%{
          scope_kind: "spacecraft",
          scope_id: "sc-1",
          spacecraft_id: "sc-1",
          realm: "rehearsal",
          data_view: "canonical",
          data_source_id: "questdb-rehearsal",
          source_binding_id: "binding-1",
          limit_mode: "observed"
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context) ==
               selected_ref

      assert DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context
             )
    end

    test "drops selected refs when runtime data context changes" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "data_source_id" => "questdb-rehearsal"
      }

      runtime_context = runtime_context(%{data_source_id: "questdb-flight"})

      refute DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context)

      refute DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context
             )
    end

    test "keeps setup resource refs when selected resource scope differs from dashboard runtime scope" do
      selected_ref = %{
        "target" => "transport",
        "target_id" => "transport-alpha",
        "scope_kind" => "transport",
        "scope_id" => "transport-alpha",
        "transport_id" => "transport-alpha",
        "realm" => "flight",
        "data_source_id" => "managed-operational",
        "source_binding_id" => "ops-binding"
      }

      runtime_context =
        runtime_context(%{
          scope_kind: "mission",
          scope_id: "mission-1",
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context) ==
               selected_ref

      assert DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context
             )
    end

    test "drops setup resource refs when same-kind runtime scope changes away from selected resource" do
      selected_ref = %{
        "target" => "link",
        "target_id" => "link-beta",
        "scope_kind" => "link",
        "scope_id" => "link-beta",
        "scope_ids" => "link-alpha,link-beta",
        "scope_link_id" => "link-beta",
        "realm" => "flight",
        "data_source_id" => "managed-operational",
        "source_binding_id" => "ops-binding"
      }

      matching_runtime_context =
        runtime_context(%{
          scope_kind: "link",
          scope_id: "link-alpha",
          scope_ids: ["link-alpha", "link-beta"],
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        })

      changed_runtime_context =
        runtime_context(%{
          scope_kind: "link",
          scope_id: "link-alpha",
          scope_ids: ["link-alpha", "link-gamma"],
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               matching_runtime_context
             ) == selected_ref

      refute DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               changed_runtime_context
             )

      refute DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               changed_runtime_context
             )
    end

    test "matches selected refs against archive time bounds" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_500
      }

      runtime_context =
        runtime_context(%{
          time_context: %{
            "mode" => "archive",
            "from" => DateTime.from_unix!(1, :second),
            "to" => DateTime.from_unix!(2, :second)
          }
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context) ==
               selected_ref

      runtime_context =
        runtime_context(%{
          time_context: %{
            "mode" => "archive",
            "from" => DateTime.from_unix!(2, :second),
            "to" => DateTime.from_unix!(3, :second)
          }
        })

      refute DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context)
    end

    test "requires query-restored telemetry refs to match concrete scope" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "spacecraft_id" => "sc-1"
      }

      assert DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context(%{
                 scope_kind: "spacecraft",
                 scope_id: "sc-1",
                 spacecraft_id: "sc-1"
               })
             )

      refute DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context(%{
                 scope_kind: "spacecraft",
                 scope_id: "sc-2",
                 spacecraft_id: "sc-2"
               })
             )
    end

    test "keeps stale-selection queries when selected ref survives runtime context" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "data_source_id" => "questdb-flight"
      }

      decision =
        DataLinkSelection.stale_selection_decision(
          %{"data_source_id" => "questdb-flight"},
          selected_ref,
          %{"selected_target" => "telemetry_sample"},
          runtime_context(%{data_source_id: "questdb-flight"})
        )

      assert decision == %{action: :keep, query: %{"data_source_id" => "questdb-flight"}}
    end

    test "keeps replay selections only when replay context and time bounds match" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_500,
        "time_axis" => "generation_time",
        "replay_run_id" => "replay-run-1"
      }

      matching_context =
        runtime_context(%{
          time_context: %{
            "mode" => "replay_run",
            "axis" => "generation_time",
            "replay_run_id" => "replay-run-1",
            "from" => DateTime.from_unix!(1, :second),
            "to" => DateTime.from_unix!(2, :second)
          }
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, matching_context) ==
               selected_ref

      refute DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               runtime_context(%{
                 time_context: %{
                   "mode" => "replay_run",
                   "axis" => "generation_time",
                   "replay_run_id" => "replay-run-2",
                   "from" => DateTime.from_unix!(1, :second),
                   "to" => DateTime.from_unix!(2, :second)
                 }
               })
             )

      refute DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               runtime_context(%{
                 time_context: %{
                   "mode" => "replay_run",
                   "axis" => "generation_time",
                   "replay_run_id" => "replay-run-1",
                   "from" => DateTime.from_unix!(2, :second),
                   "to" => DateTime.from_unix!(3, :second)
                 }
               })
             )
    end

    test "clears selection query keys when selected ref becomes stale" do
      decision =
        DataLinkSelection.stale_selection_decision(
          %{
            "data_source_id" => "questdb-flight",
            "selected_target" => "telemetry_sample",
            "selected_id" => "sample-1"
          },
          %{
            "target" => "telemetry_sample",
            "target_id" => "sample-1",
            "timestamp_ms" => 1_234,
            "data_source_id" => "questdb-rehearsal"
          },
          %{"selected_target" => "telemetry_sample"},
          runtime_context(%{data_source_id: "questdb-flight"})
        )

      assert decision.action == :clear_stale
      assert decision.query["data_source_id"] == "questdb-flight"

      assert Map.take(decision.query, Map.keys(DataLinkSelection.clear_selection_query())) ==
               DataLinkSelection.clear_selection_query()
    end

    test "clears scoped setup-resource query keys when same-kind scope changes away from selected resource" do
      decision =
        DataLinkSelection.stale_selection_decision(
          %{
            "scope_kind" => "link",
            "scope_ids" => "link-alpha,link-gamma",
            "selected_target" => "link",
            "selected_id" => "link-beta",
            "selected_scope_kind" => "link",
            "selected_scope_id" => "link-beta",
            "selected_scope_ids" => "link-alpha,link-beta",
            "selected_scope_link_id" => "link-beta"
          },
          %{
            "target" => "link",
            "target_id" => "link-beta",
            "scope_kind" => "link",
            "scope_id" => "link-beta",
            "scope_ids" => "link-alpha,link-beta",
            "scope_link_id" => "link-beta"
          },
          %{"selected_target" => "link"},
          runtime_context(%{
            scope_kind: "link",
            scope_id: "link-alpha",
            scope_ids: ["link-alpha", "link-gamma"]
          })
        )

      assert decision.action == :clear_stale
      assert decision.query["scope_kind"] == "link"
      assert decision.query["scope_ids"] == "link-alpha,link-gamma"

      assert Map.take(decision.query, Map.keys(DataLinkSelection.clear_selection_query())) ==
               DataLinkSelection.clear_selection_query()
    end

    test "clears selection query keys without stale UI action when no selection exists" do
      decision =
        DataLinkSelection.stale_selection_decision(
          %{"spacecraft_id" => nil},
          nil,
          nil,
          runtime_context(%{})
        )

      assert decision.action == :none

      assert Map.take(decision.query, Map.keys(DataLinkSelection.clear_selection_query())) ==
               DataLinkSelection.clear_selection_query()
    end
  end

  describe "evidence query parsing" do
    test "builds evidence queries from URL params only when evidence kind is present" do
      query =
        DataLinkSelection.evidence_query_from_params(
          %{
            "selected_evidence_kind" => "source_warning",
            "selected_placement" => "placement-1",
            "selected_observable" => "HK.counter",
            "selected_realm" => "backfill"
          },
          :evidence
        )

      assert %EvidenceQuery{} = query

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "source_warning",
               "selected_placement" => "placement-1",
               "selected_observable" => "HK.counter",
               "selected_realm" => "backfill"
             }

      assert is_nil(
               DataLinkSelection.evidence_query_from_params(
                 %{"selected_observable" => "HK.counter"},
                 :evidence
               )
             )
    end

    test "round trips evidence event params through query params" do
      event_params = %{
        "kind" => "source_warning",
        "placement-id" => "placement-1",
        "observable-id" => "HK.counter",
        "warning-code" => "late_sample",
        "source-evidence-state" => "context_only",
        "cache-evidence-status" => "hit",
        "realm" => "backfill",
        "requested-source-binding-id" => "binding-1"
      }

      query = DataLinkSelection.evidence_query_from_event_params(event_params)

      assert %EvidenceQuery{} = query

      assert EvidenceQuery.to_params(query) == %{
               "selected_evidence_kind" => "source_warning",
               "selected_placement" => "placement-1",
               "selected_observable" => "HK.counter",
               "selected_warning_code" => "late_sample",
               "selected_source_evidence_state" => "context_only",
               "selected_cache_evidence_status" => "hit",
               "selected_realm" => "backfill",
               "selected_requested_source_binding" => "binding-1"
             }

      assert DataLinkSelection.event_params_from_evidence_query(query) == event_params
    end
  end

  describe "evidence presentation" do
    test "builds missing evidence inspectors from evidence queries" do
      inspector =
        DataLinkSelection.missing_evidence_inspector(%{
          "selected_evidence_kind" => "source_warning",
          "selected_placement" => "placement-1",
          "selected_observable" => "HK.counter",
          "selected_warning_code" => "late_sample",
          "selected_source_request" => "request-1",
          "selected_realm" => "backfill",
          "selected_requested_data_view" => "canonical"
        })

      assert inspector.kind == "source_warning"
      assert inspector.kind_text == "source_warning"
      assert inspector.subject == "late_sample"
      assert inspector.status == :missing
      assert inspector.status_text == "missing"
      assert inspector.title == "Missing Evidence"
      assert inspector.evidence == []
      assert inspector.links == []

      assert %{label: "Warning", value: "late_sample"} in inspector.subject_rows
      assert %{label: "Source request", value: "request-1"} in inspector.subject_rows
      assert %{label: "Realm", value: "backfill"} in inspector.detail_rows
      assert %{label: "Requested data view", value: "canonical"} in inspector.detail_rows
    end

    test "derives evidence metadata from panel before query state" do
      panel =
        {:evidence,
         %{
           kind: :source_warning,
           status: :missing,
           subject_rows: [%{label: "Source request", value: "request-from-panel"}],
           detail_rows: [
             %{label: "Logical source", value: "telemetry"},
             %{label: "Realm", value: "flight"},
             %{label: "Data source", value: "questdb-flight"},
             %{label: "Source binding", value: "binding-flight"},
             %{label: "Time mode", value: "replay_run"},
             %{label: "Time axis", value: "source_time"},
             %{label: "Replay run", value: "replay-1"},
             %{label: "Requested realm", value: "simulation"},
             %{label: "Requested data view", value: "all_revisions"},
             %{label: "Requested data source", value: "questdb-sim"},
             %{label: "Requested source binding", value: "binding-sim"},
             %{label: "Requested dataset", value: "sim-dataset"},
             %{label: "Requested validity", value: "valid"}
           ]
         }}

      query = %{
        "selected_evidence_kind" => "source_health",
        "selected_source_request" => "request-from-query",
        "selected_data_source" => "questdb-query",
        "selected_source_binding" => "binding-query"
      }

      assert DataLinkSelection.evidence_state(panel, query) == "missing"
      assert DataLinkSelection.evidence_kind(panel, query) == "source_warning"
      assert DataLinkSelection.evidence_source_request(panel, query) == "request-from-panel"
      assert DataLinkSelection.evidence_logical_source(panel, query) == "telemetry"
      assert DataLinkSelection.evidence_realm(panel, query) == "flight"
      assert DataLinkSelection.evidence_data_source_id(panel, query) == "questdb-flight"
      assert DataLinkSelection.evidence_source_binding_id(panel, query) == "binding-flight"
      assert DataLinkSelection.evidence_time_mode(panel, query) == "replay_run"
      assert DataLinkSelection.evidence_time_axis(panel, query) == "source_time"
      assert DataLinkSelection.evidence_replay_run_id(panel, query) == "replay-1"
      assert DataLinkSelection.evidence_requested_realm(panel, query) == "simulation"
      assert DataLinkSelection.evidence_requested_data_view(panel, query) == "all_revisions"
      assert DataLinkSelection.evidence_requested_data_source_id(panel, query) == "questdb-sim"
      assert DataLinkSelection.evidence_requested_source_binding_id(panel, query) == "binding-sim"
      assert DataLinkSelection.evidence_requested_dataset(panel, query) == "sim-dataset"
      assert DataLinkSelection.evidence_requested_validity_state(panel, query) == "valid"
    end

    test "derives query-only evidence metadata before panel hydration" do
      query = %{
        "selected_evidence_kind" => "source_health",
        "selected_source_request" => "request-1",
        "selected_logical_source" => "limits",
        "selected_realm" => "rehearsal",
        "selected_data_source" => "questdb-rehearsal",
        "selected_source_binding" => "binding-rehearsal",
        "selected_time_mode" => "replay_run",
        "selected_time_axis" => "receipt_time",
        "selected_replay_run_id" => "replay-1",
        "selected_requested_realm" => "simulation",
        "selected_requested_data_view" => "all_revisions",
        "selected_requested_data_source" => "questdb-sim",
        "selected_requested_source_binding" => "binding-sim",
        "selected_requested_dataset" => "sim-dataset",
        "selected_requested_validity_state" => "valid"
      }

      assert DataLinkSelection.evidence_state(nil, query) == "query_only"
      assert DataLinkSelection.evidence_kind(nil, query) == "source_health"
      assert DataLinkSelection.evidence_source_request(nil, query) == "request-1"
      assert DataLinkSelection.evidence_logical_source(nil, query) == "limits"
      assert DataLinkSelection.evidence_realm(nil, query) == "rehearsal"
      assert DataLinkSelection.evidence_data_source_id(nil, query) == "questdb-rehearsal"
      assert DataLinkSelection.evidence_source_binding_id(nil, query) == "binding-rehearsal"
      assert DataLinkSelection.evidence_time_mode(nil, query) == "replay_run"
      assert DataLinkSelection.evidence_time_axis(nil, query) == "receipt_time"
      assert DataLinkSelection.evidence_replay_run_id(nil, query) == "replay-1"
      assert DataLinkSelection.evidence_requested_realm(nil, query) == "simulation"
      assert DataLinkSelection.evidence_requested_data_view(nil, query) == "all_revisions"
      assert DataLinkSelection.evidence_requested_data_source_id(nil, query) == "questdb-sim"
      assert DataLinkSelection.evidence_requested_source_binding_id(nil, query) == "binding-sim"
      assert DataLinkSelection.evidence_requested_dataset(nil, query) == "sim-dataset"
      assert DataLinkSelection.evidence_requested_validity_state(nil, query) == "valid"
      assert DataLinkSelection.evidence_state(nil, nil) == "none"
    end
  end

  describe "panel query helpers" do
    test "builds compact current queries from runtime context and selected refs" do
      query =
        base_query_attrs(%{
          selected_ref: %{
            "link_id" => "link-1",
            "target" => "telemetry_point",
            "target_id" => "HK.counter",
            "placement_id" => "placement-1",
            "timestamp_ms" => 12_345
          },
          selection_query: %{
            "selected_link" => "stale-link",
            "selected_target" => "limit_event",
            "selected_id" => "stale-id"
          },
          scope_kind: "spacecraft",
          scope_id: "sc-1",
          time_mode: "live",
          realm: "flight",
          default_realm: "flight",
          data_view: "canonical",
          default_data_view: "canonical",
          limit_mode: "observed"
        })
        |> DataLinkSelection.current_query()
        |> DataLinkSelection.compact_query()

      assert query == %{
               "spacecraft_id" => "sc-1",
               "selected_link" => "link-1",
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "panel" => "data_link"
             }
    end

    test "builds current queries for non-default runtime context" do
      query =
        base_query_attrs(%{
          scope_kind: "contact",
          scope_id: "contact-1",
          time_mode: "archive",
          time_from: "2026-01-01T00:00:00Z",
          time_to: "2026-01-01T00:05:00Z",
          realm: "rehearsal",
          default_realm: "flight",
          data_view: "as_recorded",
          default_data_view: "canonical",
          data_source_id: "questdb-rehearsal",
          source_binding_id: nil,
          default_source_binding_id: "binding-flight",
          limit_mode: "observed"
        })
        |> DataLinkSelection.current_query()
        |> DataLinkSelection.compact_query()

      assert query == %{
               "scope_kind" => "contact",
               "scope_id" => "contact-1",
               "time_mode" => "archive",
               "from" => "2026-01-01T00:00:00Z",
               "to" => "2026-01-01T00:05:00Z",
               "realm" => "rehearsal",
               "data_view" => "as_recorded",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "primary"
             }
    end

    test "marks evidence as the active panel when evidence query is present" do
      query =
        base_query_attrs(%{
          selected_ref: %{
            "link_id" => "link-1",
            "target" => "telemetry_point",
            "target_id" => "HK.counter"
          },
          evidence_query: %{
            "selected_evidence_kind" => "source_warning",
            "selected_source_request" => "request-1"
          }
        })
        |> DataLinkSelection.current_query()
        |> DataLinkSelection.compact_query()

      assert query["selected_link"] == "link-1"
      assert query["selected_evidence_kind"] == "source_warning"
      assert query["selected_source_request"] == "request-1"
      assert query["panel"] == "evidence"
    end

    test "panel query clears the opposite panel state" do
      data_link_query =
        DataLinkSelection.panel_query(
          :data_link,
          SelectionQuery.new(%{"selected_target" => "telemetry_point"})
        )

      assert data_link_query["panel"] == "data_link"
      assert data_link_query["selected_target"] == "telemetry_point"
      assert Map.has_key?(data_link_query, "selected_evidence_kind")
      assert is_nil(data_link_query["selected_evidence_kind"])

      evidence_query =
        DataLinkSelection.panel_query(:evidence, %{"selected_evidence_kind" => "warning"})

      assert evidence_query["panel"] == "evidence"
      assert evidence_query["selected_evidence_kind"] == "warning"
      assert Map.has_key?(evidence_query, "selected_target")
      assert is_nil(evidence_query["selected_target"])
    end

    test "current panel query prefers evidence over data-link state" do
      assert DataLinkSelection.current_panel_query(
               SelectionQuery.new(%{"selected_id" => "point-1"}),
               %{}
             ) == %{
               "panel" => "data_link"
             }

      assert DataLinkSelection.current_panel_query(
               %{"selected_id" => "point-1"},
               %{"selected_evidence_kind" => "warning"}
             ) == %{"panel" => "evidence"}
    end
  end

  describe "synthetic links and context" do
    test "builds synthetic links from query params with compact context" do
      assert %DataLink{
               link_id: "direct:telemetry_point:HK.counter",
               label: "telemetry point",
               target: :telemetry_point,
               target_id: "HK.counter",
               context: %{
                 time: %{mode: "fixed", axis: "receipt_time", replay_run_id: "replay-1"},
                 data: %{realm: "backfill", replay_run_id: "replay-1"},
                 selection: %{placement_id: "placement-1", timestamp_ms: 12_345}
               },
               presentation: :side_panel,
               source: :annotation
             } =
               DataLinkSelection.synthetic_link_from_query(%{
                 "selected_target" => "telemetry_point",
                 "selected_id" => "HK.counter",
                 "time_mode" => "fixed",
                 "time_axis" => "receipt_time",
                 "replay_run_id" => "replay-1",
                 "realm" => "backfill",
                 "selected_placement" => "placement-1",
                 "selected_time" => 12_345
               })
    end

    test "builds source-watermark event synthetic links with source context" do
      assert %DataLink{
               link_id: "direct:source_watermark_event:watermark-event-1",
               label: "source watermark event",
               target: :source_watermark_event,
               target_id: "watermark-event-1",
               context: %{
                 time: %{mode: "archive", axis: "occurred_at", replay_run_id: "replay-1"},
                 data: %{
                   realm: "flight",
                   data_source_id: "events-projection",
                   source_binding_id: "events-binding",
                   replay_run_id: "replay-1"
                 },
                 selection: %{placement_id: "placement-1", timestamp_ms: 12_345}
               },
               presentation: :side_panel,
               source: :annotation
             } =
               DataLinkSelection.synthetic_link_from_query(%{
                 "selected_target" => "source_watermark_event",
                 "selected_id" => "watermark-event-1",
                 "time_mode" => "archive",
                 "time_axis" => "occurred_at",
                 "replay_run_id" => "replay-1",
                 "realm" => "flight",
                 "data_source_id" => "events-projection",
                 "source_binding_id" => "events-binding",
                 "selected_placement" => "placement-1",
                 "selected_time" => 12_345
               })
    end

    test "adds selection context and lets link context override runtime context" do
      link = %DataLink{
        target: :telemetry_point,
        target_id: "HK.counter",
        context: %{data: %{realm: "link-realm"}}
      }

      link =
        link
        |> DataLinkSelection.with_selection_context(%{
          "placement-id" => "placement-1",
          "timestamp-ms" => "12345",
          "series-role" => "compare",
          "compare-of" => "HK.counter",
          "time-mode" => "archive",
          "time-axis" => "receipt_time",
          "data-view" => "canonical",
          "comparison-state" => "increased",
          "comparison-delta" => "+2",
          "primary-data-management" => "recomputed_analysis",
          "compare-data-management" => "degraded"
        })
        |> DataLinkSelection.with_runtime_context(%{
          data: %{realm: "runtime-realm", view: "canonical"},
          limit: %{semantics_mode: "observed"}
        })

      assert link.context == %{
               data: %{realm: "link-realm", view: "canonical"},
               time: %{mode: "archive", axis: "receipt_time"},
               limit: %{semantics_mode: "observed"},
               selection: %{
                 placement_id: "placement-1",
                 timestamp_ms: 12_345,
                 series_role: "compare",
                 compare_of: "HK.counter"
               },
               comparison: %{
                 state: "increased",
                 delta: "+2",
                 primary_data_management: "recomputed_analysis",
                 compare_data_management: "degraded"
               }
             }
    end

    test "adds navigation breadcrumb context from related-link event params" do
      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "dropped-event-1",
            "relationship_kind" => "source_event"
          },
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "previous-event-1",
            "label" => "Previous event",
            "relationship_kind" => "source_event"
          },
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "source-event-1",
            "label" => "Source event",
            "relationship_kind" => "retry_event"
          },
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "target-event-1",
            "label" => "Target event",
            "relationship_kind" => "correction_request",
            "realm" => "flight",
            "data_view" => "canonical",
            "data_source_id" => "questdb-flight",
            "source_binding_id" => "binding-flight",
            "time_mode" => "archive",
            "time_axis" => "receipt_time",
            "replay_run_id" => "replay-1"
          }
        ])

      link = %DataLink{
        link_id: "target-link-1",
        target: :telemetry_backfill_lifecycle_event,
        target_id: "target-event-1"
      }

      link =
        DataLinkSelection.with_selection_context(link, %{
          "nav-from-link-id" => "source-link-1",
          "nav-from-target" => "telemetry_backfill_lifecycle_event",
          "nav-from-target-id" => "source-event-1",
          "nav-from-label" => "Source event",
          "nav-from-relationship-kind" => "retry_event",
          "nav-from-relationship-label" => "Retry event HK.counter",
          "nav-trail" => nav_trail
        })

      assert link.context.navigation.from == %{
               link_id: "source-link-1",
               target: "telemetry_backfill_lifecycle_event",
               target_id: "source-event-1",
               label: "Source event",
               relationship_kind: "retry_event",
               relationship_label: "Retry event HK.counter"
             }

      assert [
               %{target_id: "previous-event-1"},
               %{target_id: "source-event-1"},
               %{
                 target_id: "target-event-1",
                 realm: "flight",
                 data_view: "canonical",
                 data_source_id: "questdb-flight",
                 source_binding_id: "binding-flight",
                 time_mode: "archive",
                 time_axis: "receipt_time",
                 replay_run_id: "replay-1"
               }
             ] = link.context.navigation.trail

      selected_ref = DataLinkSelection.selected_ref(link, %{})

      assert Map.drop(selected_ref, ["nav_trail"]) == %{
               "link_id" => "target-link-1",
               "target" => "telemetry_backfill_lifecycle_event",
               "target_id" => "target-event-1",
               "target_text" => "telemetry backfill lifecycle event",
               "source" => "field",
               "nav_from_link_id" => "source-link-1",
               "nav_from_target" => "telemetry_backfill_lifecycle_event",
               "nav_from_target_id" => "source-event-1",
               "nav_from_label" => "Source event",
               "nav_from_relationship_kind" => "retry_event",
               "nav_from_relationship_label" => "Retry event HK.counter"
             }

      assert [
               %{"target_id" => "previous-event-1"},
               %{"target_id" => "source-event-1"},
               %{
                 "target_id" => "target-event-1",
                 "realm" => "flight",
                 "data_view" => "canonical",
                 "data_source_id" => "questdb-flight",
                 "source_binding_id" => "binding-flight",
                 "time_mode" => "archive",
                 "time_axis" => "receipt_time",
                 "replay_run_id" => "replay-1"
               }
             ] = Jason.decode!(selected_ref["nav_trail"])
    end

    test "preserves explicit marker data context into selected refs" do
      link = %DataLink{
        link_id: "link-1",
        target: :telemetry_point,
        target_id: "HK.counter",
        source: :annotation,
        context: %{
          data: %{realm: "flight", view: "canonical", data_source_id: "runtime-source"},
          time: %{mode: "live", axis: "generation_time"}
        }
      }

      event_params = %{
        "placement-id" => "placement-1",
        "timestamp-ms" => "12345",
        "realm" => "replay",
        "data-view" => "all_revisions",
        "data-source-id" => "marker-source",
        "source-binding-id" => "marker-binding",
        "time-mode" => "replay_run",
        "time-axis" => "generation_time",
        "replay-run-id" => "replay-run-1"
      }

      selected_ref =
        link
        |> DataLinkSelection.with_selection_context(event_params)
        |> DataLinkSelection.with_runtime_context(%{
          data: %{realm: "flight", view: "canonical", data_source_id: "runtime-source"},
          time: %{mode: "live", axis: "generation_time"}
        })
        |> DataLinkSelection.selected_ref(event_params)

      assert selected_ref == %{
               "link_id" => "link-1",
               "target" => "telemetry_point",
               "target_id" => "HK.counter",
               "target_text" => "telemetry point",
               "timestamp_ms" => 12_345,
               "placement_id" => "placement-1",
               "source" => "annotation",
               "realm" => "replay",
               "time_mode" => "replay_run",
               "time_axis" => "generation_time",
               "data_view" => "all_revisions",
               "replay_run_id" => "replay-run-1",
               "data_source_id" => "marker-source",
               "source_binding_id" => "marker-binding"
             }
    end
  end

  defp runtime_context(overrides) do
    Map.merge(
      %{
        scope_kind: nil,
        scope_id: nil,
        spacecraft_id: nil,
        time_context: %{"mode" => "live"},
        replay_run_id: nil,
        realm: nil,
        data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        limit_mode: nil,
        data_context: %{}
      },
      overrides
    )
  end

  defp base_query_attrs(overrides) do
    Map.merge(
      %{
        selected_ref: nil,
        selection_query: nil,
        evidence_query: nil,
        scope_kind: nil,
        scope_id: nil,
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        data_source_id: nil,
        source_binding_id: nil,
        default_source_binding_id: nil,
        limit_mode: "observed"
      },
      overrides
    )
  end
end
