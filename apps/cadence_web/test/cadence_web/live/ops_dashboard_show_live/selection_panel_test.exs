defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanelTest do
  use Cadence.DataCase, async: false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{
    DataBinding,
    DataLink,
    Document,
    EvidenceRef,
    Field,
    Frame,
    PlacementFrames
  }

  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

  test "hydrates missing evidence from a query" do
    socket =
      socket(%{
        dashboard_engine_result: nil,
        dashboard_evidence_query: %{
          "selected_evidence_kind" => "frame",
          "selected_observable" => "HK.counter"
        }
      })

    socket = SelectionPanel.hydrate_evidence_from_query(socket)

    assert {:evidence, inspector} = socket.assigns.panel
    assert inspector.status == :missing
    assert inspector.kind == "frame"
    assert inspector.subject == "HK.counter"
  end

  test "open_evidence resolves frame interval evidence from dashboard engine result" do
    frame = %Frame{
      frame_id: "source-request-1:HK.counter",
      source: :telemetry,
      shape: :scalar,
      fields: [
        %Field{
          name: "HK.counter",
          kind: :number,
          values: [12.4],
          metadata: %{
            evidence: [
              %EvidenceRef{
                kind: :application_binding_interval,
                id: "application-binding-interval-1",
                source: :operational_event,
                confidence: :selected,
                observed_at: ~U[2026-06-21 20:30:00Z]
              }
            ]
          }
        }
      ],
      meta: %{
        observable_id: "HK.counter",
        evidence: [
          %EvidenceRef{
            kind: :source_binding_interval,
            id: "source-binding-interval-1",
            source: :telemetry,
            confidence: :selected,
            observed_at: ~U[2026-06-21 20:30:00Z]
          },
          %EvidenceRef{
            kind: :binding_set_interval,
            id: "binding-set-interval-1",
            source: :operational_event,
            confidence: :selected,
            observed_at: ~U[2026-06-21 20:30:00Z]
          }
        ],
        source_binding_interval: %{
          binding_id: "flight-telemetry",
          data_binding_event_id: "source-binding-event-1",
          data_source_id: "mission-questdb-v1",
          active_from: ~U[2026-06-21 20:00:00Z]
        }
      }
    }

    socket =
      socket(%{
        dashboard_engine_result: %{
          frames_by_placement: %{"placement-counter" => %PlacementFrames{primary: [frame]}}
        }
      })

    socket =
      SelectionPanel.open_evidence(
        socket,
        %{
          "kind" => "frame",
          "placement-id" => "placement-counter",
          "observable-id" => "HK.counter"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:evidence, inspector} = socket.assigns.panel
    assert inspector.kind == :frame
    assert inspector.subject == "source-request-1:HK.counter"

    assert %{
             kind_text: "source binding interval",
             source: :telemetry,
             confidence: :selected,
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               inspector.evidence,
               :source_binding_interval,
               "source-binding-interval-1"
             )

    assert %{
             kind_text: "binding set interval",
             source: :operational_event,
             confidence: :selected,
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               inspector.evidence,
               :binding_set_interval,
               "binding-set-interval-1"
             )

    assert %{
             kind_text: "application binding interval",
             source: :operational_event,
             confidence: :selected,
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               inspector.evidence,
               :application_binding_interval,
               "application-binding-interval-1"
             )

    assert %{value: "source-binding-event-1"} =
             Enum.find(inspector.detail_rows, &(&1.label == "Source binding interval"))

    assert socket.assigns.patched_query["panel"] == "evidence"
    assert socket.assigns.patched_query["selected_evidence_kind"] == "frame"
    assert socket.assigns.patched_query["selected_placement"] == "placement-counter"
    assert socket.assigns.patched_query["selected_observable"] == "HK.counter"
  end

  test "clears stale selected data while preserving the runtime query decision" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        data_link_action_outcome: %{action: :late_data_policy},
        dashboard_selected_data_ref: %{
          "target" => "telemetry_sample",
          "target_id" => "sample-1",
          "timestamp_ms" => 1_700_000_000_000,
          "realm" => "flight"
        },
        dashboard_selection_query: %{
          "selected_target" => "telemetry_sample",
          "selected_id" => "sample-1",
          "selected_time" => 1_700_000_000_000
        },
        dashboard_selection_state: "active",
        dashboard_evidence_query: nil
      })

    runtime_context = %{
      scope_kind: nil,
      scope_id: nil,
      spacecraft_id: nil,
      time_context: %{
        "mode" => "archive",
        "from" => DateTime.from_unix!(1_700_000_500, :second),
        "to" => DateTime.from_unix!(1_700_000_800, :second)
      },
      replay_run_id: nil,
      realm: "flight",
      data_view: nil,
      data_source_id: nil,
      source_binding_id: nil,
      limit_mode: nil,
      data_context: %{}
    }

    {socket, query} =
      SelectionPanel.stale_selection_checked_runtime_query(
        socket,
        %{"time_mode" => "archive"},
        runtime_context
      )

    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "stale_context"
    assert socket.assigns.data_link_action_outcome == nil

    assert Map.take(query, ["selected_target", "selected_id", "selected_time"]) == %{
             "selected_target" => nil,
             "selected_id" => nil,
             "selected_time" => nil
           }
  end

  test "keeps selected data when it still matches runtime context" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_700_000_000_000,
      "realm" => "flight"
    }

    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: selected_ref,
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    runtime_context = %{
      scope_kind: nil,
      scope_id: nil,
      spacecraft_id: nil,
      time_context: %{"mode" => "live"},
      replay_run_id: nil,
      realm: "flight",
      data_view: nil,
      data_source_id: nil,
      source_binding_id: nil,
      limit_mode: nil,
      data_context: %{}
    }

    {updated_socket, query} =
      SelectionPanel.stale_selection_checked_runtime_query(
        socket,
        %{"time_mode" => "live"},
        runtime_context
      )

    assert updated_socket.assigns.dashboard_selected_data_ref == selected_ref
    assert updated_socket.assigns.dashboard_selection_state == "active"
    assert query == %{"time_mode" => "live"}
  end

  test "hydrate_selection_from_query preserves outcomes scoped to the same selection" do
    link = data_link()

    query =
      SelectionQuery.new(%{
        "selected_link" => link.link_id,
        "selected_target" => "telemetry_point",
        "selected_id" => "HK.counter",
        "realm" => "flight"
      })

    outcome = %{action: :stage_transition, target_event_id: "event-1"}

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_selection_query: query,
        data_link_action_outcome: outcome,
        data_link_action_outcome_query: SelectionQuery.to_params(query),
        dashboard_engine_result: %{
          frames_by_placement: %{
            "placement-1" =>
              PlacementFrames.new(%{
                primary: [
                  Frame.new(%{
                    source: :telemetry,
                    shape: :scalar,
                    meta: %{links: [link]}
                  })
                ]
              })
          }
        },
        dashboard_time_mode: "live",
        dashboard_time_context: %{"mode" => "live"},
        dashboard_data_realm: "flight"
      })

    socket = SelectionPanel.hydrate_selection_from_query(socket, [])

    assert {:data_link, _inspector} = socket.assigns.panel
    assert socket.assigns.data_link_action_outcome == outcome
  end

  test "hydrate_selection_from_query resolves copied selected-link URLs after frames arrive" do
    link = data_link()

    query =
      SelectionQuery.new(%{
        "selected_link" => link.link_id,
        "selected_placement" => "placement-1",
        "selected_time" => 1_781_697_600_000,
        "time_mode" => "live",
        "time_axis" => "generation_time",
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      })

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_selection_query: query,
        dashboard_engine_result: %{frames_by_placement: %{}},
        dashboard_time_mode: "live",
        dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "questdb-flight",
        dashboard_source_binding_id: "binding-flight",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "questdb-flight",
          "source_binding_id" => "binding-flight"
        }
      })

    missing_socket = SelectionPanel.hydrate_selection_from_query(socket, [])

    assert {:data_link, missing_inspector} = missing_socket.assigns.panel
    assert missing_inspector.status == :missing
    assert missing_inspector.link_id == link.link_id
    assert missing_socket.assigns.dashboard_selected_data_ref == nil
    assert missing_socket.assigns.dashboard_selection_state == "query_only"

    hydrated_socket =
      missing_socket
      |> assign(:dashboard_engine_result, %{
        frames_by_placement: %{
          "placement-1" =>
            PlacementFrames.new(%{
              primary: [
                Frame.new(%{
                  source: :telemetry,
                  shape: :scalar,
                  meta: %{links: [link]}
                })
              ]
            })
        }
      })
      |> SelectionPanel.hydrate_selection_from_query([])

    assert {:data_link, inspector} = hydrated_socket.assigns.panel
    assert inspector.status == :context_only
    assert hydrated_socket.assigns.dashboard_selection_state == "active"

    assert hydrated_socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => link.link_id,
             "target" => "telemetry_point",
             "target_id" => "HK.counter",
             "target_text" => "telemetry point",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "placement-1",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc-1",
             "spacecraft_id" => "sc-1",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed",
             "observable_id" => "HK.counter"
           }
  end

  test "extracts observable ids from atom-keyed and string-keyed selected refs" do
    assert SelectionPanel.selected_data_ref_observable_id(
             socket(%{dashboard_selected_data_ref: %{observable_id: "HK.counter"}})
           ) == "HK.counter"

    assert SelectionPanel.selected_data_ref_observable_id(
             socket(%{dashboard_selected_data_ref: %{"point_id" => "HK.voltage"}})
           ) == "HK.voltage"
  end

  test "data link index falls back to runtime result frames when cached assign is missing" do
    placement_frames = %PlacementFrames{}

    socket =
      socket(%{
        dashboard_engine_result: %{
          "frames_by_placement" => %{"placement-1" => placement_frames}
        },
        dashboard_engine_frames_by_placement: nil
      })

    assert SelectionPanel.data_link_index(socket).frames_by_placement == %{
             "placement-1" => placement_frames
           }
  end

  test "open_data_link preserves resolved source context into selected refs and route query" do
    link = data_link()

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_data_realms: ["flight"],
        dashboard_data_bindings: [data_binding()],
        dashboard_engine_result: %{
          frames_by_placement: %{
            "placement-1" =>
              PlacementFrames.new(%{
                primary: [
                  Frame.new(%{
                    source: :telemetry,
                    shape: :scalar,
                    meta: %{links: [link]}
                  })
                ]
              })
          }
        },
        context_scope_kind: "spacecraft",
        context_scope_id: "sc-1",
        context_spacecraft_id: "sc-1",
        dashboard_scope_context: %{
          "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc-1"]}
        },
        dashboard_time_mode: "live",
        dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "questdb-flight",
        dashboard_source_binding_id: "binding-flight",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "questdb-flight",
          "source_binding_id" => "binding-flight"
        },
        dashboard_limit_mode: "observed",
        dashboard_limit_context: %{"semantics_mode" => "observed"},
        data_link_action_outcome: %{action: :revision_decision}
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        link.link_id,
        %{
          "placement-id" => "placement-1",
          "timestamp-ms" => "1781697600000",
          "series-role" => "primary",
          "time-mode" => "archive",
          "time-axis" => "receipt_time"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.context_rows
    assert %{label: "Data source", value: "questdb-flight"} in inspector.context_rows
    assert %{label: "Source binding", value: "binding-flight"} in inspector.context_rows

    assert socket.assigns.dashboard_selection_state == "active"
    assert socket.assigns.data_link_action_outcome == nil

    assert socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => link.link_id,
             "target" => "telemetry_point",
             "target_id" => "HK.counter",
             "target_text" => "telemetry point",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "placement-1",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc-1",
             "spacecraft_id" => "sc-1",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "receipt_time",
             "series_role" => "primary",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed",
             "observable_id" => "HK.counter"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_placement",
             "selected_time",
             "selected_series_role",
             "time_mode",
             "time_axis"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => link.link_id,
             "selected_target" => "telemetry_point",
             "selected_id" => "HK.counter",
             "selected_placement" => "placement-1",
             "selected_time" => 1_781_697_600_000,
             "selected_series_role" => "primary",
             "time_mode" => "archive",
             "time_axis" => "receipt_time"
           }
  end

  test "put_historical_workflow_link_selection clears stale outcomes by default" do
    link = direct_backfill_event_link()

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        data_link_action_outcome: %{action: :retry_job}
      })

    socket =
      SelectionPanel.put_historical_workflow_link_selection(
        socket,
        %{
          "selected_target" => "telemetry_backfill_lifecycle_event",
          "selected_id" => "backfill-event-1"
        },
        link,
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :telemetry_backfill_lifecycle_event
    assert socket.assigns.data_link_action_outcome == nil
  end

  test "put_historical_workflow_link_selection preserves outcomes for action result selections" do
    link = direct_backfill_event_link()
    outcome = %{action: :retry_job, target_event_id: "backfill-event-1"}

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        data_link_action_outcome: outcome
      })

    socket =
      SelectionPanel.put_historical_workflow_link_selection(
        socket,
        %{
          "selected_target" => "telemetry_backfill_lifecycle_event",
          "selected_id" => "backfill-event-1"
        },
        link,
        preserve_data_link_action_outcome?: true,
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :telemetry_backfill_lifecycle_event
    assert socket.assigns.data_link_action_outcome == outcome

    assert socket.assigns.data_link_action_outcome_query == %{
             "selected_target" => "telemetry_backfill_lifecycle_event",
             "selected_id" => "backfill-event-1"
           }
  end

  test "open_data_link resolves direct source-watermark event links from event params" do
    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_data_realms: ["flight"],
        dashboard_data_bindings: [data_binding()],
        dashboard_engine_result: %{frames_by_placement: %{}},
        dashboard_time_mode: "archive",
        dashboard_time_context: %{"mode" => "archive", "axis" => "occurred_at"},
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "events-projection",
        dashboard_source_binding_id: "events-binding",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "events-projection",
          "source_binding_id" => "events-binding"
        }
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        "direct:source_watermark_event:watermark-event-1",
        %{
          "target" => "source_watermark_event",
          "target-id" => "watermark-event-1",
          "placement-id" => "data-management",
          "timestamp-ms" => "1781697600000",
          "time-mode" => "archive",
          "time-axis" => "occurred_at",
          "realm" => "flight",
          "data-source-id" => "events-projection",
          "source-binding-id" => "events-binding"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :source_watermark_event
    assert inspector.target_id == "watermark-event-1"

    assert socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => "direct:source_watermark_event:watermark-event-1",
             "target" => "source_watermark_event",
             "target_id" => "watermark-event-1",
             "target_text" => "source watermark event",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "data-management",
             "source" => "annotation",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "data_source_id" => "events-projection",
             "source_binding_id" => "events-binding"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_placement",
             "selected_time",
             "time_mode",
             "time_axis",
             "realm",
             "data_source_id",
             "source_binding_id"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => "direct:source_watermark_event:watermark-event-1",
             "selected_target" => "source_watermark_event",
             "selected_id" => "watermark-event-1",
             "selected_placement" => "data-management",
             "selected_time" => 1_781_697_600_000,
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "realm" => "flight",
             "data_source_id" => "events-projection",
             "source_binding_id" => "events-binding"
           }
  end

  test "open_data_link opens operational resource links from chart point metadata" do
    link = %DataLink{
      link_id: "transport:transport-alpha:ops-request-1",
      label: "Transport",
      target: :transport,
      target_id: "transport-alpha",
      source: :frame,
      context: %{
        organization_id: "org-1",
        mission_id: "mission-1",
        source_request_id: "ops-request-1",
        logical_source: :operational_observables,
        observable_id: "link.snr_db",
        scope: %{primary: %{kind: "link", mode: "one", ids: ["link-alpha"]}},
        data: %{
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        },
        operational_resource: %{
          resource_id: "link-alpha",
          scope_kind: :link,
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14",
          link_id: "link-alpha",
          adapter_key: :rf_adapter
        }
      }
    }

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_engine_result: %{
          frames_by_placement: %{
            "placement-rf" =>
              PlacementFrames.new(%{
                primary: [
                  Frame.new(%{
                    source: :operational_observables,
                    shape: :wide,
                    meta: %{links: [link]}
                  })
                ]
              })
          }
        },
        dashboard_data_realm: "flight",
        dashboard_data_source_id: "managed-operational",
        dashboard_source_binding_id: "ops-binding",
        dashboard_data_context: %{
          "realm" => "flight",
          "data_source_id" => "managed-operational",
          "source_binding_id" => "ops-binding"
        }
      })

    socket =
      SelectionPanel.open_data_link(
        socket,
        link.link_id,
        %{
          "target" => "transport",
          "target-id" => "transport-alpha",
          "placement-id" => "placement-rf",
          "timestamp-ms" => "1781697720000",
          "series-role" => "primary",
          "time-mode" => "archive",
          "time-axis" => "occurred_at",
          "realm" => "flight",
          "data-source-id" => "managed-operational",
          "source-binding-id" => "ops-binding"
        },
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :transport
    assert inspector.target_id == "transport-alpha"

    assert socket.assigns.dashboard_selected_data_ref == %{
             "link_id" => "transport:transport-alpha:ops-request-1",
             "target" => "transport",
             "target_id" => "transport-alpha",
             "target_text" => "transport",
             "timestamp_ms" => 1_781_697_720_000,
             "placement_id" => "placement-rf",
             "source" => "frame",
             "scope_kind" => "link",
             "scope_id" => "link-alpha",
             "realm" => "flight",
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "series_role" => "primary",
             "data_source_id" => "managed-operational",
             "source_binding_id" => "ops-binding",
             "transport_id" => "transport-alpha",
             "source_endpoint_id" => "endpoint-alpha",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-alpha",
             "observable_id" => "link.snr_db"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_link",
             "selected_target",
             "selected_id",
             "selected_placement",
             "selected_time",
             "selected_series_role",
             "selected_scope_kind",
             "selected_scope_id",
             "selected_transport_id",
             "selected_source_endpoint_id",
             "selected_ground_station_id",
             "selected_scope_link_id",
             "time_mode",
             "time_axis",
             "realm",
             "data_source_id",
             "source_binding_id"
           ]) == %{
             "panel" => "data_link",
             "selected_link" => "transport:transport-alpha:ops-request-1",
             "selected_target" => "transport",
             "selected_id" => "transport-alpha",
             "selected_placement" => "placement-rf",
             "selected_time" => 1_781_697_720_000,
             "selected_series_role" => "primary",
             "selected_scope_kind" => "link",
             "selected_scope_id" => "link-alpha",
             "selected_transport_id" => "transport-alpha",
             "selected_source_endpoint_id" => "endpoint-alpha",
             "selected_ground_station_id" => "dss-14",
             "selected_scope_link_id" => "link-alpha",
             "time_mode" => "archive",
             "time_axis" => "occurred_at",
             "realm" => "flight",
             "data_source_id" => "managed-operational",
             "source_binding_id" => "ops-binding"
           }
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            panel: nil,
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_selection_state: "none",
            dashboard_evidence_query: nil,
            dashboard_engine_result: nil,
            dashboard_engine_frames_by_placement: nil,
            dashboard_data_realms: [],
            dashboard_data_bindings: [],
            dashboard_document: nil,
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            context_scope_kind: nil,
            context_scope_id: nil,
            context_spacecraft_id: nil,
            dashboard_scope_context: %{},
            dashboard_time_mode: "live",
            dashboard_time_from: nil,
            dashboard_time_to: nil,
            dashboard_replay_run_id: nil,
            dashboard_time_context: %{},
            dashboard_data_realm: nil,
            dashboard_data_view: nil,
            dashboard_compare_data_view: nil,
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_data_context: %{},
            dashboard_limit_mode: nil,
            dashboard_limit_context: %{},
            data_link_action_outcome: nil,
            data_link_action_outcome_query: nil
          },
          assigns
        )
    }
  end

  defp direct_backfill_event_link do
    %DataLink{
      link_id: "direct:telemetry_backfill_lifecycle_event:backfill-event-1",
      label: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "backfill-event-1",
      source: :annotation,
      context: %{data: %{realm: "flight"}}
    }
  end

  defp data_link do
    %DataLink{
      link_id: "telemetry_point:HK.counter:request-1",
      label: "Telemetry point",
      target: :telemetry_point,
      target_id: "HK.counter",
      source: :frame,
      context: %{
        organization_id: "org-1",
        mission_id: "mission-1",
        source_request_id: "request-1",
        logical_source: :telemetry,
        observable_id: "HK.counter",
        scope: %{
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
        },
        time: %{mode: "live", axis: "generation_time"},
        data: %{
          realm: "flight",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        limit: %{semantics_mode: "observed"}
      }
    }
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "binding-flight"}
          }
        }
      }
    }
  end

  defp data_binding do
    %DataBinding{
      binding_id: "binding-flight",
      logical_source: :telemetry,
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      priority: 0
    }
  end

  defp evidence_ref_summary(evidence, kind, id) do
    Enum.find(evidence, &(&1.kind == kind and &1.id == id))
  end
end
