defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{
    Document,
    Placement,
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
