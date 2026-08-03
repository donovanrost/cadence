defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQuerySourceTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, Document}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  test "normalizes runtime query to selected active source binding" do
    slow_binding =
      data_binding(%{
        binding_id: "rehearsal-slow",
        data_source_id: "questdb-rehearsal",
        realm: :rehearsal,
        priority: 10
      })

    fast_binding =
      data_binding(%{
        binding_id: "rehearsal-fast",
        data_source_id: "questdb-rehearsal",
        realm: :rehearsal,
        priority: 1
      })

    assert RuntimeQuery.normalize_runtime_query(
             %{
               "realm" => "rehearsal",
               "data_source_id" => "questdb-rehearsal",
               "data_view" => "all_revisions",
               "compare_data_view" => "canonical"
             },
             ["flight", "rehearsal"],
             [data_binding(), slow_binding, fast_binding],
             document()
           ) == %{
             "time_mode" => nil,
             "time_axis" => nil,
             "from" => nil,
             "to" => nil,
             "replay_run_id" => nil,
             "realm" => "rehearsal",
             "data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "data_source_id" => "questdb-rehearsal",
             "source_binding_id" => "rehearsal-fast",
             "limit_mode" => nil,
             "hidden_markers" => nil
           }
  end

  test "normalizes primary source binding override against document defaults" do
    assert RuntimeQuery.normalize_runtime_query(
             %{"source_binding_id" => "primary"},
             ["flight"],
             [data_binding()],
             document()
           ) == %{
             "time_mode" => nil,
             "time_axis" => nil,
             "from" => nil,
             "to" => nil,
             "replay_run_id" => nil,
             "realm" => nil,
             "data_view" => nil,
             "compare_data_view" => nil,
             "data_source_id" => nil,
             "source_binding_id" => "primary",
             "limit_mode" => nil,
             "hidden_markers" => nil
           }
  end

  test "stringifies document data defaults for runtime default comparison" do
    assert RuntimeQuery.document_data_defaults(%Document{
             defaults: %{
               data: %{
                 realm: "rehearsal",
                 source_mode: "specific",
                 source_contexts: %{
                   telemetry: %{source_binding_id: "rehearsal-binding"}
                 }
               }
             }
           }) == %{
             "realm" => "rehearsal",
             "source_mode" => "specific",
             "source_contexts" => %{
               "telemetry" => %{"source_binding_id" => "rehearsal-binding"}
             }
           }
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
