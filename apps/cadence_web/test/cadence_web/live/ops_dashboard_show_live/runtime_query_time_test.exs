defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryTimeTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, Document}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  test "invalid archive time params fall back to live with validation state" do
    for {params, validation} <- [
          {%{"time_mode" => "archive", "from" => "not-a-time", "to" => "2026-06-17T12:05:00Z"},
           "invalid_time_bound"},
          {%{
             "time_mode" => "archive",
             "from" => "2026-06-17T12:05:00Z",
             "to" => "2026-06-17T12:00:00Z"
           }, "time_range_reversed"}
        ] do
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

      assert context.time_mode == "live"
      assert context.time_from == nil
      assert context.time_to == nil
      assert context.time_axis == "generation_time"
      assert context.time_context == %{"mode" => "live", "axis" => "generation_time"}
      assert context.time_validation == validation

      assert %{
               "time_mode" => nil,
               "time_axis" => nil,
               "from" => nil,
               "to" => nil
             } =
               RuntimeQuery.normalize_runtime_query(
                 params,
                 ["flight"],
                 [data_binding()],
                 document()
               )
    end
  end

  test "sliding relative bounds keep live mode with a window" do
    params = %{"from" => "now-6h", "to" => "now"}

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

    assert context.time_mode == "live"
    assert context.time_from == "now-6h"
    assert context.time_to == "now"
    assert context.time_validation == "ok"

    assert context.time_context == %{
             "mode" => "live",
             "axis" => "generation_time",
             "window_seconds" => 21_600
           }

    assert %{"time_mode" => nil, "from" => "now-6h", "to" => "now"} =
             RuntimeQuery.normalize_runtime_query(
               params,
               ["flight"],
               [data_binding()],
               document()
             )
  end

  test "absolute bounds without time_mode infer archive" do
    params = %{"from" => "2026-06-17T12:00:00Z", "to" => "2026-06-17T12:05:00Z"}

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

    assert context.time_mode == "archive"
    assert context.time_from == "2026-06-17T12:00:00Z"
    assert context.time_to == "2026-06-17T12:05:00Z"
    assert context.time_axis == "receipt_time"
    assert context.time_validation == "ok"
  end

  test "oversized or invalid sliding windows fall back to live" do
    for {params, validation} <- [
          {%{"from" => "now-7d", "to" => "now"}, "window_too_large"},
          {%{"from" => "now-6x", "to" => "now"}, "invalid_time_bound"},
          {%{"from" => "now-6h", "to" => nil}, "time_range_required"}
        ] do
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

      assert context.time_mode == "live"
      assert context.time_from == nil
      assert context.time_context == %{"mode" => "live", "axis" => "generation_time"}
      assert context.time_validation == validation
    end
  end

  defp scope do
    %{organization_id: "org-1"}
  end

  defp mission do
    %{mission_id: "mission-1"}
  end

  defp document do
    %Document{
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "telemetry" => %{
              "source_binding_id" => "flight-binding"
            }
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
