defmodule CadenceWeb.OpsDashboardShowLive.RouteHydrationTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery
  alias CadenceWeb.OpsDashboardShowLive.RouteHydration
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

  test "handle_params returns the socket unchanged before a document is loaded" do
    socket = socket(%{dashboard_document: nil})

    assert RouteHydration.handle_params(socket, %{}, opts()) == socket
  end

  test "handle_params returns the socket unchanged while editing" do
    socket = socket(%{edit_mode?: true})

    assert RouteHydration.handle_params(socket, %{}, opts()) == socket
  end

  test "handle_params opens dashboard editor focus from readiness params" do
    socket =
      RouteHydration.handle_params(
        socket(),
        %{
          "panel" => "dashboard_editor",
          "selected_placement" => "placement-ground-state",
          "selected_publish_issue" =>
            "error:unready_publish_source_request:placement-ground-state:unsupported_observable_scope:ground.station.connection_state",
          "source_empty_reason" => "unsupported_observable_scope",
          "unsupported_observables" => "ground.station.connection_state, contacts.phase",
          "requested_observables" => "ground.station.connection_state",
          "requested_sampling" => "raw_series",
          "supported_sampling" => "latest, event_history",
          "requested_products" => "link_rf",
          "requested_source_products" => "link_rf_metric_history",
          "supported_products" => "link_rf_metric_history, operational_metric_history",
          "requested_product_families" => "link_rf"
        },
        editor_opts()
      )

    assert socket.assigns.entered_edit_mode? == true
    assert socket.assigns.edit_mode? == true
    assert socket.assigns.panel == {:edit_placement, "placement-ground-state"}
    assert socket.assigns.opened_widget_config_placement_id == "placement-ground-state"
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_evidence_query == nil

    assert socket.assigns.dashboard_editor_focus == %{
             placement_id: "placement-ground-state",
             publish_issue_id:
               "error:unready_publish_source_request:placement-ground-state:unsupported_observable_scope:ground.station.connection_state",
             source_empty_reason: "unsupported_observable_scope",
             unsupported_observables: ["ground.station.connection_state", "contacts.phase"],
             requested_observables: ["ground.station.connection_state"],
             requested_sampling: "raw_series",
             supported_sampling: ["latest", "event_history"],
             requested_products: ["link_rf"],
             requested_source_products: ["link_rf_metric_history"],
             supported_products: ["link_rf_metric_history", "operational_metric_history"],
             requested_product_families: ["link_rf"]
           }
  end

  test "handle_params hydrates query params and resolves the initial engine result" do
    socket =
      RouteHydration.handle_params(
        socket(),
        %{
          "scope_kind" => "mission",
          "scope_id" => "mission-1",
          "time_mode" => "archive",
          "from" => "2026-06-25T11:55:00Z",
          "to" => "2026-06-25T12:00:00Z",
          "panel" => "data_link",
          "selected_target" => "telemetry_sample",
          "selected_id" => "sample-1",
          "selected_placement" => "placement-1",
          "selected_time" => "1782388800000",
          "realm" => "rehearsal",
          "data_source_id" => "questdb-rehearsal",
          "source_binding_id" => "rehearsal-binding",
          "time_axis" => "receipt_time",
          "replay_run_id" => "replay-run-1"
        },
        opts()
      )

    assert socket.assigns.resolved_mode == :initial
    assert socket.assigns.resolve_opts == [reason: :runtime_context_changed]
    assert socket.assigns.context_scope_kind == "mission"
    assert socket.assigns.context_scope_id == "mission-1"
    assert socket.assigns.dashboard_time_mode == "archive"
    assert socket.assigns.dashboard_time_from == "2026-06-25T11:55:00Z"
    assert socket.assigns.dashboard_time_to == "2026-06-25T12:00:00Z"

    assert %SelectionQuery{} = socket.assigns.dashboard_selection_query

    assert SelectionQuery.to_params(socket.assigns.dashboard_selection_query) == %{
             "selected_target" => "telemetry_sample",
             "selected_id" => "sample-1",
             "selected_placement" => "placement-1",
             "selected_time" => 1_782_388_800_000,
             "realm" => "rehearsal",
             "data_source_id" => "questdb-rehearsal",
             "source_binding_id" => "rehearsal-binding",
             "time_mode" => "archive",
             "time_axis" => "receipt_time",
             "replay_run_id" => "replay-run-1"
           }

    assert socket.assigns.dashboard_evidence_query == nil
    assert socket.assigns.chart_epoch == 1
    assert %DateTime{} = socket.assigns.dashboard_runtime_context_since
  end

  test "handle_params resolves a context change when an engine result already exists" do
    socket =
      socket()
      |> assign_current_runtime_context(%{"scope_kind" => "mission", "scope_id" => "mission-1"})
      |> assign(:dashboard_engine_result, %{status: :ok})

    socket =
      RouteHydration.handle_params(
        socket,
        %{"scope_kind" => "spacecraft", "scope_id" => "sc-1"},
        opts()
      )

    assert socket.assigns.resolved_mode == :context_change
    assert socket.assigns.resolve_opts == [reason: :runtime_context_changed]
    assert socket.assigns.context_scope_kind == "spacecraft"
    assert socket.assigns.context_scope_id == "sc-1"
  end

  test "handle_params hydrates selection when context is unchanged and engine result exists" do
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
          "panel" => "evidence",
          "selected_evidence_kind" => "source_warning",
          "selected_placement" => "placement-1",
          "selected_warning_code" => "stale_source"
        },
        opts()
      )

    assert socket.assigns.hydrated? == true
    refute Map.has_key?(socket.assigns, :resolved_mode)
    assert socket.assigns.dashboard_selection_query == nil

    assert %EvidenceQuery{} = socket.assigns.dashboard_evidence_query

    assert EvidenceQuery.to_params(socket.assigns.dashboard_evidence_query) == %{
             "selected_evidence_kind" => "source_warning",
             "selected_placement" => "placement-1",
             "selected_warning_code" => "stale_source"
           }
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

  defp editor_opts do
    opts()
    |> Keyword.merge(
      enter_edit_mode: fn socket, _opts ->
        socket
        |> assign(:entered_edit_mode?, true)
        |> assign(:edit_mode?, true)
      end,
      open_widget_config: fn socket, placement_id ->
        socket
        |> assign(:opened_widget_config_placement_id, placement_id)
        |> assign(:panel, {:edit_placement, placement_id})
      end
    )
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
