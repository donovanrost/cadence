defmodule CadenceWeb.OpsDiagnosticsURLTest do
  use ExUnit.Case, async: true
  alias CadenceWeb.OpsDiagnosticsURL

  test "view selection is separate from exact admitted runtime query" do
    query = %{
      "time_mode" => "range",
      "from" => "2026-09-07T01:00:00.123456+01:00",
      "to" => "2026-09-07T01:00:00Z",
      "realm" => "rehearsal",
      "selection_view" => "as_recorded",
      "limit_mode" => "compare"
    }

    params =
      Map.merge(query, %{
        "mission_id" => "mission",
        "dashboard_id" => "dashboard",
        "collection" => "frames",
        "row" => String.duplicate("a", 64),
        "filter" => "é"
      })

    assert {:ok, admitted} = OpsDiagnosticsURL.admit(params)
    assert admitted.runtime_query == query

    assert admitted.selection == %{
             collection: "frames",
             row: String.duplicate("a", 64),
             filter: "é"
           }

    assert admitted.runtime.time_context.from == ~U[2026-09-07 00:00:00.123456Z]
    refute Map.has_key?(admitted.runtime, :selection)

    assert {:ok, defaults} = OpsDiagnosticsURL.admit(%{})
    assert defaults.selection == %{collection: "plan", row: nil, filter: ""}
    assert defaults.runtime_query == %{}
    assert defaults.runtime == %{time_context: %{}, data_context: %{}, limit_context: %{}}
  end

  test "malformed selections and unsupported context fail rather than being dropped" do
    for params <- [
          nil,
          %{"collection" => "other"},
          %{"collection" => ["plan"]},
          %{"row" => "raw-identity"},
          %{"row" => String.duplicate("a", 64) <> "\n"},
          %{"row" => String.duplicate("A", 64)},
          %{"filter" => String.duplicate("é", 129)},
          %{"filter" => "control\t"},
          %{"filter" => %{}},
          %{"filter" => <<255>>},
          %{"source_binding_id" => "other"},
          %{"replay_run_id" => "other"},
          %{"organization_id" => "foreign"},
          %{"runtime" => %{}},
          %{"time_mode" => "range"},
          %{"time_mode" => "live", "from" => "2026-09-07T00:00:00Z"}
        ] do
      assert {:error, :invalid_context} = OpsDiagnosticsURL.admit(params)
    end

    assert {:ok, _} = OpsDiagnosticsURL.admit(%{"filter" => String.duplicate("é", 128)})
  end
end
