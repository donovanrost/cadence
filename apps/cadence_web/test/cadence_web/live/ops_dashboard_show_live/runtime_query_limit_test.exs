defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryLimitTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, Document}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  test "accepts supported limit semantics modes into runtime context" do
    for limit_mode <- ["observed", "current", "recomputed", "compare"] do
      assert %{limit_mode: ^limit_mode, limit_context: %{"semantics_mode" => ^limit_mode}} =
               RuntimeQuery.runtime_context_from_params(
                 %{"limit_mode" => limit_mode},
                 scope(),
                 mission(),
                 [%{spacecraft_id: "sc-1"}],
                 ["flight"],
                 [data_binding()],
                 document()
               )
    end
  end

  test "records unsupported limit mode fallback metadata without changing engine semantics" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{"limit_mode" => "projected"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert %{limit_mode: "observed", limit_context: %{"semantics_mode" => "observed"}} =
             context

    assert context.limit_mode_fallback == %{
             "requested_mode" => "projected",
             "applied_mode" => "observed",
             "reason" => "unsupported_limit_semantics_mode",
             "supported_modes" => ["observed", "current", "recomputed", "compare"]
           }
  end

  test "normalizes non-default supported limit semantics mode" do
    assert %{"limit_mode" => "recomputed"} =
             RuntimeQuery.normalize_runtime_query(
               %{"limit_mode" => "recomputed"},
               ["flight"],
               [data_binding()],
               document()
             )

    assert %{"limit_mode" => nil} =
             RuntimeQuery.normalize_runtime_query(
               %{"limit_mode" => "observed"},
               ["flight"],
               [data_binding()],
               document()
             )
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
