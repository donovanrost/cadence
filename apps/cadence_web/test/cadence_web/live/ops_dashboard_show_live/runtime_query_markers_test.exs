defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RouteQuery
  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  test "hidden_markers param round-trips through context, assigns, and query" do
    params = %{"hidden_markers" => "limits,contacts,bogus"}

    context =
      RuntimeQuery.runtime_context_from_params(
        params,
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert context.hidden_marker_categories == ["contacts", "limits"]

    field_assigns = RuntimeContext.field_assigns(context)
    assert field_assigns.dashboard_hidden_marker_categories == ["contacts", "limits"]

    assert %{"hidden_markers" => "contacts,limits"} =
             RuntimeQuery.normalize_runtime_query(
               params,
               ["flight"],
               [data_binding()],
               document()
             )
  end

  test "checkbox map shape normalizes with false meaning hidden" do
    params = %{"markers" => %{"limits" => "false", "contacts" => "true"}}

    assert %{"hidden_markers" => "limits"} =
             RuntimeQuery.normalize_runtime_query(
               params,
               ["flight"],
               [data_binding()],
               document()
             )
  end

  test "absent or invalid hidden_markers means all visible and no param emitted" do
    for params <- [%{}, %{"hidden_markers" => "bogus"}, %{"hidden_markers" => ""}] do
      context =
        RuntimeQuery.runtime_context_from_params(
          params,
          scope(),
          mission(),
          [%{spacecraft_id: "sc-1"}],
          ["flight"],
          [data_binding()],
          document()
        )

      assert context.hidden_marker_categories == []

      assert %{"hidden_markers" => nil} =
               RuntimeQuery.normalize_runtime_query(
                 params,
                 ["flight"],
                 [data_binding()],
                 document()
               )
    end
  end

  test "current_query preserves hidden markers from assigns" do
    assigns = %{
      dashboard_document: document(),
      dashboard_data_realms: ["flight"],
      dashboard_data_bindings: [data_binding()],
      dashboard_hidden_marker_categories: ["contacts"],
      dashboard_time_mode: "live",
      dashboard_data_realm: "flight",
      dashboard_data_view: "canonical",
      dashboard_limit_mode: "observed"
    }

    assert %{"hidden_markers" => "contacts"} = RuntimeQuery.current_query(assigns)
    assert "hidden_markers" in RouteQuery.runtime_query_keys()
  end

  defp scope, do: %{organization_id: "org-1"}
  defp mission, do: %{mission_id: "mission-1"}

  defp document do
    %Document{
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{"telemetry" => %{"source_binding_id" => "flight-binding"}},
          "view" => "canonical"
        }
      }
    }
  end

  defp data_binding do
    %DataBinding{
      binding_id: "flight-binding",
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end
end
