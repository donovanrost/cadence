defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlsContextTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls
  alias Phoenix.LiveView.Socket

  test "set_runtime_context normalizes params and patches the route query" do
    socket =
      socket(%{
        dashboard_data_realms: ["flight", "rehearsal"],
        dashboard_data_bindings: [
          data_binding(),
          data_binding(%{
            binding_id: "rehearsal-fast",
            data_source_id: "questdb-rehearsal",
            realm: :rehearsal
          })
        ]
      })

    socket =
      RuntimeControls.set_runtime_context(
        socket,
        %{
          "realm" => "rehearsal",
          "data_source_id" => "questdb-rehearsal",
          "data_view" => "all_revisions",
          "ignored" => "value"
        },
        patch_opts()
      )

    assert Map.take(socket.assigns.patched_query, [
             "time_mode",
             "from",
             "to",
             "replay_run_id",
             "realm",
             "data_view",
             "data_source_id",
             "source_binding_id",
             "limit_mode"
           ]) == %{
             "time_mode" => nil,
             "from" => nil,
             "to" => nil,
             "replay_run_id" => nil,
             "realm" => "rehearsal",
             "data_view" => "all_revisions",
             "data_source_id" => "questdb-rehearsal",
             "source_binding_id" => "rehearsal-fast",
             "limit_mode" => nil
           }
  end

  test "set_context patches generic mission scope query" do
    socket =
      RuntimeControls.set_context(
        socket(),
        %{"scope_kind" => "mission", "scope_id" => "mission-1"},
        patch_opts()
      )

    assert socket.assigns.context_query == ""

    assert Map.take(socket.assigns.patched_query, [
             "spacecraft_id",
             "scope_kind",
             "scope_id"
           ]) == %{
             "spacecraft_id" => nil,
             "scope_kind" => "mission",
             "scope_id" => "mission-1"
           }
  end

  test "set_context patches durable multi-select scope query" do
    socket =
      RuntimeControls.set_context(
        socket(),
        %{
          "scope_kind" => "source_endpoint",
          "scope_ids" => ["endpoint-alpha", "endpoint-beta"]
        },
        patch_opts()
      )

    assert socket.assigns.context_query == ""

    assert Map.take(socket.assigns.patched_query, [
             "spacecraft_id",
             "scope_kind",
             "scope_id",
             "scope_ids"
           ]) == %{
             "spacecraft_id" => nil,
             "scope_kind" => "source_endpoint",
             "scope_id" => nil,
             "scope_ids" => "endpoint-alpha,endpoint-beta"
           }
  end

  test "set_context uses operational resource validation before stale selection decisions" do
    selected_ref = %{
      "target" => "telemetry_point",
      "target_id" => "HK.counter",
      "scope_kind" => "spacecraft",
      "scope_id" => "sc-1",
      "realm" => "flight"
    }

    socket =
      RuntimeControls.set_context(
        socket(%{
          dashboard_selected_data_ref: selected_ref,
          dashboard_selection_query: %{"selected_id" => "HK.counter"},
          dashboard_selection_state: "active"
        }),
        %{"scope_kind" => "transport", "scope_id" => "missing-transport"},
        Keyword.put(
          patch_opts(),
          :valid_operational_resource_scope?,
          fn _scope, _mission, scope_kind, scope_id ->
            scope_kind == "transport" and scope_id == "transport-alpha"
          end
        )
      )

    assert socket.assigns.dashboard_selected_data_ref == selected_ref
    assert socket.assigns.dashboard_selection_state == "active"
    assert socket.assigns.patched_query["scope_kind"] == "transport"
    assert socket.assigns.patched_query["scope_id"] == "missing-transport"
    assert socket.assigns.patched_query["selected_id"] == nil
  end

  test "set_context keeps spacecraft context on the legacy spacecraft query param" do
    socket = RuntimeControls.set_context(socket(), "sc-1", patch_opts())

    assert Map.take(socket.assigns.patched_query, [
             "spacecraft_id",
             "scope_kind",
             "scope_id",
             "scope_ids"
           ]) == %{
             "spacecraft_id" => "sc-1",
             "scope_kind" => nil,
             "scope_id" => nil,
             "scope_ids" => nil
           }
  end

  defp patch_opts do
    [
      patch: fn socket, query -> assign(socket, :patched_query, query) end,
      valid_contact?: fn _scope, _mission, _contact_id -> false end
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
            dashboard_data_realms: ["flight"],
            dashboard_data_bindings: [data_binding()],
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_evidence_query: nil,
            context_scope_kind: nil,
            context_scope_id: nil,
            dashboard_time_mode: "live",
            dashboard_time_from: nil,
            dashboard_time_to: nil,
            dashboard_replay_run_id: nil,
            dashboard_data_realm: "flight",
            dashboard_data_view: "canonical",
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_limit_mode: "observed",
            dashboard_selection_state: "none",
            panel: nil
          },
          assigns
        )
    }
  end

  defp document do
    %Document{
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
