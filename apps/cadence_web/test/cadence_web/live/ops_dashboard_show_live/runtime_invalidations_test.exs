defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    Document,
    Placement,
    PlannedSourceRequest,
    ResolveWarning,
    SourceWatermark,
    WidgetDef
  }

  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidations
  alias Phoenix.LiveView.Socket

  test "matching allowed invalidations emit a decision, record a notice, and resolve the engine" do
    test_pid = self()

    socket =
      RuntimeInvalidations.handle_invalidation(
        socket(),
        invalidation(:dashboard_version_changed),
        opts(test_pid)
      )

    assert_received {:decision, :dashboard_version_changed, decision, emit_opts}
    assert decision.matches? == true
    assert decision.dashboard_matches? == true
    assert decision.context_matches? == true
    assert decision.refresh_allowed? == true
    assert decision.decision_status == :refresh_allowed
    assert decision.affected_placement_count == 1
    assert decision.affected_placement_ids == ["placement-1"]
    assert decision.affected_widget_type_ids == ["cadence.value_tile"]
    assert decision.affected_impact_reasons == [:dashboard_document]
    assert is_binary(emit_opts[:invalidation_event_id])

    assert socket.assigns.dashboard_last_runtime_invalidation.boundary ==
             :dashboard_version_changed

    assert socket.assigns.resolved_mode == :context_change
    assert socket.assigns.resolve_opts[:reason] == :runtime_invalidation
    assert socket.assigns.resolve_opts[:remount_charts_after_resolve?] == false
  end

  test "catalog revision invalidations refresh live dashboard plans" do
    test_pid = self()

    socket =
      RuntimeInvalidations.handle_invalidation(
        socket(),
        invalidation(:catalog_revision_changed,
          logical_source: :telemetry,
          observable: "HK.counter"
        ),
        opts(test_pid)
      )

    assert_received {:decision, :catalog_revision_changed, decision, _emit_opts}
    assert decision.matches? == true
    assert decision.context_matches? == true
    assert decision.refresh_allowed? == true
    assert decision.decision_status == :refresh_allowed
    assert decision.affected_placement_ids == ["placement-1"]
    assert decision.affected_impact_reasons == [:primary_source]

    assert socket.assigns.dashboard_last_runtime_invalidation.boundary ==
             :catalog_revision_changed

    assert socket.assigns.dashboard_last_runtime_invalidation.refresh_action == :refresh_plan
    assert socket.assigns.resolved_mode == :context_change
  end

  test "matching invalidations capture current selection impact in the decision" do
    test_pid = self()

    RuntimeInvalidations.handle_invalidation(
      socket(%{
        dashboard_selected_data_ref: %{
          "link_id" => "telemetry-sample-link",
          "target" => "telemetry_sample",
          "target_id" => "sample-1",
          "placement_id" => "placement-1",
          "observable_id" => "HK.counter",
          "data_view" => "all_revisions"
        },
        dashboard_selection_state: "active"
      }),
      invalidation(:catalog_revision_changed,
        logical_source: :telemetry,
        observable: "HK.counter"
      ),
      opts(test_pid)
    )

    assert_received {:decision, :catalog_revision_changed, decision, _emit_opts}
    assert decision.selection_state == "active"
    assert decision.selected_link_id == "telemetry-sample-link"
    assert decision.selected_target == "telemetry_sample"
    assert decision.selected_target_id == "sample-1"
    assert decision.selected_placement_id == "placement-1"
    assert decision.selected_observable_id == "HK.counter"
    assert decision.selected_data_view == "all_revisions"
    assert decision.selection_affected? == true
    assert decision.selection_impact_reason == :affected_placement
  end

  test "matching invalidations capture source cache evidence audit in the decision" do
    test_pid = self()

    RuntimeInvalidations.handle_invalidation(
      socket(%{dashboard_engine_result: engine_result()}),
      invalidation(:catalog_revision_changed,
        logical_source: :telemetry,
        observable: "HK.counter"
      ),
      opts(test_pid)
    )

    assert_received {:decision, :catalog_revision_changed, decision, _emit_opts}

    assert decision.source_cache_evidence_state_summary == %{
             total: 2,
             resolved: 0,
             context_only: 2,
             missing: 0
           }

    assert decision.source_cache_evidence_target_ids == []
    assert decision.source_cache_evidence_request_ids == ["req-1"]
  end

  test "matching invalidations capture source execution audit in the decision" do
    test_pid = self()

    RuntimeInvalidations.handle_invalidation(
      socket(%{dashboard_engine_result: source_execution_engine_result()}),
      invalidation(:source_health_changed,
        logical_source: :telemetry,
        observable: "HK.counter"
      ),
      opts(test_pid)
    )

    assert_received {:decision, :source_health_changed, decision, _emit_opts}

    assert decision.source_execution_retryable_count == 2
    assert decision.source_execution_actionable_count == 1
    assert decision.source_execution_degraded_count == 1

    assert decision.source_execution_status_summary == %{
             cache_stale: 1,
             source_degraded: 1
           }

    assert decision.source_execution_runtime_action_summary == %{
             refresh_source_result: 1,
             wait_for_source_health: 1
           }

    assert decision.source_execution_degraded_identities == [
             "telemetry:req-circuit:source_degraded"
           ]

    assert decision.source_execution_degraded_actions == [
             "telemetry:req-circuit:wait_for_source_health:inspect_source_health"
           ]
  end

  test "matching invalidations in edit mode emit a decision without assigning or resolving" do
    test_pid = self()

    socket =
      RuntimeInvalidations.handle_invalidation(
        socket(%{edit_mode?: true}),
        invalidation(:dashboard_version_changed),
        opts(test_pid)
      )

    assert_received {:decision, :dashboard_version_changed, decision, _emit_opts}
    assert decision.matches? == true
    assert decision.refresh_allowed? == false
    assert decision.refresh_reason == :edit_mode
    assert decision.decision_status == :refresh_suppressed

    # Edit mode pauses all data-driven assigns so no patch reaches the DOM
    # that GridStack is mutating; even the notice strip stays untouched.
    assert socket.assigns.dashboard_last_runtime_invalidation == nil
    refute Map.has_key?(socket.assigns, :resolved_mode)
  end

  test "nonmatching invalidations emit a filtered decision without notice or resolve" do
    test_pid = self()

    socket =
      RuntimeInvalidations.handle_invalidation(
        socket(),
        invalidation(:dashboard_version_changed, organization_id: "other-org"),
        opts(test_pid)
      )

    assert_received {:decision, :dashboard_version_changed, decision, _emit_opts}
    assert decision.matches? == false
    assert decision.dashboard_matches? == false
    assert decision.context_reason == :scope_mismatch
    assert decision.decision_status == :filtered

    assert socket.assigns.dashboard_last_runtime_invalidation == nil
    refute Map.has_key?(socket.assigns, :resolved_mode)
  end

  test "context_from_assigns keeps the invalidation policy input narrow" do
    assert RuntimeInvalidations.context_from_assigns(socket().assigns) == %{
             data_realm: "flight",
             engine_result: nil,
             time_context: %{"mode" => "live", "axis" => "generation_time"},
             time_mode: "live",
             replay_run_id: nil,
             context_since: ~U[2026-06-25 12:00:00Z],
             edit_mode?: false
           }
  end

  defp opts(test_pid) do
    [
      emit_decision: fn event, decision, emit_opts ->
        send(test_pid, {:decision, event.boundary, decision, emit_opts})
        :ok
      end,
      resolve_engine: fn socket, mode, resolve_opts ->
        socket
        |> assign(:resolved_mode, mode)
        |> assign(:resolve_opts, resolve_opts)
      end
    ]
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            dashboard_document: document(),
            dashboard_last_runtime_invalidation: nil,
            dashboard_data_realm: "flight",
            dashboard_engine_result: nil,
            dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
            dashboard_time_mode: "live",
            dashboard_replay_run_id: nil,
            dashboard_runtime_context_since: ~U[2026-06-25 12:00:00Z],
            edit_mode?: false
          },
          assigns
        )
    }
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      placements: [
        %Placement{
          placement_id: "placement-1",
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            title: "Counter",
            binding: %{
              source: :telemetry,
              observables: ["HK.counter"],
              overlays: [:limits, :quality]
            }
          }
        }
      ]
    }
  end

  defp engine_result do
    %{
      resolve_mode: :context_change,
      plan_metadata: %{
        cache: %{
          source_result_cache_by_request_id: %{
            "req-1" => %{
              status: :stale,
              reasons: [:source_degraded],
              key: %{
                parts: %{
                  request: %{
                    request_id: "req-1",
                    logical_source: :telemetry,
                    observables: ["HK.counter"]
                  },
                  source_binding: %{binding_id: "flight-binding", realm: :flight},
                  data_source: %{data_source_id: "questdb-flight"}
                }
              }
            }
          },
          frame_cache_by_placement: %{
            "placement-1" => %{
              "req-1" => %{
                status: :miss,
                source_result_cache_status: :stale,
                key: %{
                  parts: %{
                    source_result_request: %{
                      request_id: "req-1",
                      logical_source: :telemetry,
                      observables: ["HK.counter"]
                    },
                    source_result_binding: %{binding_id: "flight-binding", realm: :flight},
                    source_result_data_source: %{data_source_id: "questdb-flight"}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  defp source_execution_engine_result do
    %DashboardResolveResult{
      dashboard_id: "dashboard-1",
      resolve_mode: :context_change,
      planned_source_requests: [
        source_request("req-stale"),
        source_request("req-circuit")
      ],
      watermarks: [
        source_watermark("req-stale"),
        source_watermark("req-circuit")
      ],
      plan_metadata: %{
        source_request_count: 2,
        executed_source_request_count: 1,
        skipped_source_request_count: 1,
        returned_frame_count: 0,
        cache: %{
          source_result_cache_by_request_id: %{
            "req-stale" => %{status: :stale, reasons: [:source_degraded]},
            "req-circuit" => %{status: :disabled}
          }
        }
      },
      dashboard_warnings: [
        %ResolveWarning{
          code: :source_degraded,
          severity: :warning,
          details: %{
            source_request_id: "req-circuit",
            logical_source: :telemetry,
            source_binding_id: "flight-binding",
            data_source_id: "questdb-flight",
            realm: :flight,
            circuit_state: :open,
            failure_count: 2,
            failure_threshold: 2
          }
        }
      ]
    }
  end

  defp source_request(request_id) do
    %PlannedSourceRequest{
      request_id: request_id,
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{
        realm: :flight,
        source_contexts: %{
          telemetry: %{
            data_source_id: "questdb-flight",
            source_binding_id: "flight-binding",
            view: :canonical
          }
        }
      },
      metadata: %{
        capability_provenance: %{
          source_binding_id: "flight-binding",
          data_source_id: "questdb-flight",
          realm: :flight,
          dataset: "flight"
        }
      }
    }
  end

  defp source_watermark(request_id) do
    %SourceWatermark{
      logical_source: :telemetry,
      request_id: request_id,
      source_binding_id: "flight-binding",
      data_source_id: "questdb-flight",
      realm: :flight,
      dataset: "flight",
      confidence: :authoritative,
      freshness_state: :fresh
    }
  end

  defp invalidation(boundary, attrs \\ []) do
    filters =
      attrs
      |> Enum.into(%{})
      |> Map.put_new(:organization_id, "org-1")
      |> Map.put_new(:mission_id, "mission-1")
      |> Map.put_new(:dashboard_id, "dashboard-1")

    Event.new(
      boundary,
      [:plan],
      filters,
      %{},
      %{plans: 1, total: 1},
      occurred_at: ~U[2026-06-25 12:00:01Z]
    )
  end
end
