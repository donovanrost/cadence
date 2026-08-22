defmodule CadenceWeb.OpsDashboardShowLive.RouteHydrationRuntimeContextTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, Placement, WidgetDef}

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RouteHydration
  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext
  alias Phoenix.LiveView.Socket

  test "runtime context hydration rejects stale operational resource URL scopes" do
    context =
      RouteHydration.runtime_context_from_params(
        socket(),
        %{"scope_kind" => "transport", "scope_id" => "missing-transport"},
        Keyword.put(
          opts(),
          :valid_operational_resource_scope?,
          fn _scope, _mission, scope_kind, scope_id ->
            scope_kind == "transport" and scope_id == "transport-alpha"
          end
        )
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "spacecraft"
    assert context.scope_id == nil
    assert context.scope_ids == []
  end

  test "assign_runtime_context clears stale data selections" do
    socket =
      socket(%{
        dashboard_selected_data_ref: %{
          "target" => "telemetry_sample",
          "target_id" => "sample-1",
          "scope_kind" => "mission",
          "scope_id" => "mission-1",
          "realm" => "flight",
          "data_view" => "canonical",
          "data_source_id" => "questdb-flight",
          "source_binding_id" => "flight-binding"
        }
      })

    runtime_context =
      RouteHydration.runtime_context_from_params(socket, %{
        "scope_kind" => "mission",
        "scope_id" => "mission-1",
        "realm" => "rehearsal",
        "source_binding_id" => "rehearsal-binding"
      })

    socket = RouteHydration.assign_runtime_context(socket, runtime_context)

    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_data_realm == "rehearsal"
    assert socket.assigns.dashboard_source_binding_id == "rehearsal-binding"
    assert socket.assigns.chart_epoch == 1
  end

  test "assign_runtime_context refreshes repeated render items from runtime scope" do
    socket =
      socket(%{
        dashboard_document: repeated_document(),
        dashboard_render_items: []
      })

    socket =
      RouteHydration.assign_runtime_context(
        socket,
        runtime_context(%{
          scope_kind: "spacecraft",
          scope_id: "sc-1",
          scope_context: %{
            "primary" => %{
              "kind" => "spacecraft",
              "mode" => "many",
              "ids" => ["sc-1", "sc-2"]
            }
          },
          spacecraft_id: "sc-1"
        })
      )

    assert Enum.map(socket.assigns.dashboard_render_items, & &1.placement_id) == [
             "placement-repeat__repeat__spacecraft__sc-1",
             "placement-repeat__repeat__spacecraft__sc-2"
           ]

    socket =
      RouteHydration.assign_runtime_context(
        socket,
        runtime_context(%{
          scope_kind: "spacecraft",
          scope_id: "sc-3",
          scope_context: %{
            "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc-3"]}
          },
          spacecraft_id: "sc-3"
        })
      )

    assert Enum.map(socket.assigns.dashboard_render_items, & &1.placement_id) == [
             "placement-repeat__repeat__spacecraft__sc-3"
           ]
  end

  defp opts do
    [
      resolve_engine: fn socket, mode, resolve_opts ->
        socket
        |> Phoenix.Component.assign(:resolved_mode, mode)
        |> Phoenix.Component.assign(:resolve_opts, resolve_opts)
      end,
      hydrate_selection: fn socket -> Phoenix.Component.assign(socket, :hydrated?, true) end,
      valid_contact?: fn _scope, _mission, contact_id -> contact_id == "contact-1" end
    ]
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

  defp repeated_document do
    %Document{
      dashboard_id: "dashboard-repeat",
      organization_id: "org-1",
      mission_id: "mission-1",
      grid: %{columns: 12, row_height_px: 64, gap_px: 8},
      placements: [
        %Placement{
          placement_id: "placement-repeat",
          layout: %{x: 0, y: 0, w: 4, h: 3},
          repeat: %{axis: :scope, over: :spacecraft, layout: :wrap_grid, max_instances: 12},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.status_matrix",
            title: "Spacecraft Status",
            binding: %{observables: ["HK.counter"], scope_mode: :repeat}
          }
        }
      ]
    }
  end

  defp runtime_context(attrs) do
    RuntimeContext.new(
      Map.merge(
        %{
          scope_kind: nil,
          scope_id: nil,
          scope_context: nil,
          spacecraft_id: nil,
          time_mode: "live",
          time_validation: "ok",
          realm: "flight",
          data_view: "canonical",
          compare_data_view: nil,
          data_source_id: nil,
          source_binding_id: nil,
          limit_mode: "observed",
          limit_mode_fallback: nil,
          time_context: %{"mode" => "live", "axis" => "generation_time"},
          data_context: %{"realm" => "flight", "view" => "canonical"},
          limit_context: %{"semantics_mode" => "observed"}
        },
        attrs
      )
    )
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
