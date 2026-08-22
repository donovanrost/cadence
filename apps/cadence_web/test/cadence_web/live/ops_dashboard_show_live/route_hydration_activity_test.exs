defmodule CadenceWeb.OpsDashboardShowLive.RouteHydrationActivityTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RouteHydration
  alias Phoenix.LiveView.Socket

  test "handle_params hydrates review activity placement focus" do
    socket =
      socket()
      |> assign_current_runtime_context(%{"scope_kind" => "mission", "scope_id" => "mission-1"})
      |> assign(:dashboard_engine_result, %{status: :ok})

    socket =
      RouteHydration.handle_params(
        socket,
        %{
          "scope_kind" => "mission",
          "scope_id" => "mission-1",
          "panel" => "versions",
          "activity_filter" => "open_comparison_reviews",
          "activity_event" => "dashboard-lifecycle-event-1",
          "selected_placement" => "placement-1",
          "selected_publish_issue" => "error:invalid-grid"
        },
        opts()
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :open_comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == "dashboard-lifecycle-event-1"
    assert socket.assigns.dashboard_review_placement_id == "placement-1"
    assert socket.assigns.dashboard_selected_publish_issue_id == "error:invalid-grid"
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.hydrated? == true
  end

  test "handle_params preserves source return readiness refresh intent" do
    socket =
      socket()
      |> assign_current_runtime_context(%{"scope_kind" => "mission", "scope_id" => "mission-1"})
      |> assign(:dashboard_engine_result, %{status: :ok})

    socket =
      RouteHydration.handle_params(
        socket,
        %{
          "scope_kind" => "mission",
          "scope_id" => "mission-1",
          "panel" => "versions",
          "activity_filter" => "publish_readiness",
          "activity_event" => "dashboard-lifecycle-event-readiness",
          "refresh_readiness" => "source_return"
        },
        opts()
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :publish_readiness
    assert socket.assigns.dashboard_activity_event_id == "dashboard-lifecycle-event-readiness"
    assert socket.assigns.dashboard_readiness_return_intent == "source_return"
    assert socket.assigns.hydrated? == true
  end

  test "handle_params hydrates supported dashboard activity filters" do
    socket =
      socket()
      |> assign_current_runtime_context(%{"scope_kind" => "mission", "scope_id" => "mission-1"})
      |> assign(:dashboard_engine_result, %{status: :ok})

    socket =
      RouteHydration.handle_params(
        socket,
        %{
          "scope_kind" => "mission",
          "scope_id" => "mission-1",
          "panel" => "versions",
          "activity_filter" => "health_snapshots",
          "activity_event" => "dashboard-lifecycle-event-health",
          "selected_placement" => "review-placement"
        },
        opts()
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :health_snapshots
    assert socket.assigns.dashboard_activity_event_id == "dashboard-lifecycle-event-health"
    assert socket.assigns.dashboard_review_placement_id == nil
    assert socket.assigns.hydrated? == true
  end

  defp opts do
    [
      resolve_engine: fn socket, mode, resolve_opts ->
        socket
        |> assign(:resolved_mode, mode)
        |> assign(:resolve_opts, resolve_opts)
      end,
      hydrate_selection: fn socket -> assign(socket, :hydrated?, true) end,
      valid_contact?: fn _scope, _mission, contact_id -> contact_id == "contact-1" end
    ]
  end

  defp assign_current_runtime_context(socket, params) do
    RouteHydration.assign_runtime_context(
      socket,
      RouteHydration.runtime_context_from_params(socket, params, opts())
    )
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            spacecraft: [%{spacecraft_id: "sc-1"}],
            dashboard_document: document(),
            dashboard_data_realms: ["flight", "rehearsal"],
            dashboard_data_bindings: [
              data_binding(),
              data_binding(%{
                binding_id: "rehearsal-binding",
                data_source_id: "questdb-rehearsal",
                dataset: "rehearsal",
                realm: :rehearsal
              })
            ],
            dashboard_scope_context: nil,
            dashboard_time_context: nil,
            dashboard_data_context: nil,
            dashboard_limit_context: nil,
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_evidence_query: nil,
            dashboard_activity_filter: nil,
            dashboard_review_placement_id: nil,
            dashboard_engine_result: nil,
            chart_epoch: 0,
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
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "flight-binding"}
          },
          "view" => "canonical"
        }
      }
    }
  end

  defp data_binding(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        binding_id: "flight-binding",
        data_source_id: "questdb-flight",
        dataset: "flight",
        realm: :flight,
        logical_source: :telemetry,
        priority: 0,
        status: :active
      })

    struct!(DataBinding, attrs)
  end
end
