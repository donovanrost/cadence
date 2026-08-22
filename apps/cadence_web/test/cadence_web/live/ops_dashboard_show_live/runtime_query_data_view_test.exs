defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryDataViewTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  test "normalizes data-view comparison only when it differs from the active view" do
    assert %{compare_data_view: "all_revisions"} =
             RuntimeQuery.runtime_context_from_params(
               %{"data_view" => "canonical", "compare_data_view" => "all_revisions"},
               scope(),
               mission(),
               [%{spacecraft_id: "sc-1"}],
               ["flight"],
               [data_binding()],
               document()
             )

    assert %{compare_data_view: nil} =
             RuntimeQuery.runtime_context_from_params(
               %{"data_view" => "canonical", "compare_data_view" => "canonical"},
               scope(),
               mission(),
               [%{spacecraft_id: "sc-1"}],
               ["flight"],
               [data_binding()],
               document()
             )

    assert %{compare_data_view: nil} =
             RuntimeQuery.runtime_context_from_params(
               %{"data_view" => "canonical", "compare_data_view" => "unsupported"},
               scope(),
               mission(),
               [%{spacecraft_id: "sc-1"}],
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
