defmodule Cadence.Reads.Dashboards.ExplorationQueryTest do
  use ExUnit.Case, async: true
  alias Cadence.Reads.Dashboards.ExplorationQuery
  alias Cadence.Reads.Dashboards.ExplorationRequest

  @now ~U[2026-09-07 00:00:00.000002Z]

  test "relative queries have a server-observed finite window without changing copied selectors" do
    params = %{
      "point_id" => "HK.counter",
      "time_mode" => "last_1h",
      "selection_view" => "all_revisions",
      "limit" => "25"
    }

    assert {:ok, context} = ExplorationQuery.admit(params, @now)
    assert context.query == params
    assert context.time.to == @now
    assert DateTime.diff(context.time.to, context.time.from) == 3600
    assert context.limit == 25
    assert context.data.view == "all_revisions"
  end

  test "range replay source and selected sample identity are preserved exactly" do
    params = %{
      "point_id" => "HK.counter",
      "time_mode" => "replay_run",
      "from" => "2026-09-07T01:00:00.000001+01:00",
      "to" => "2026-09-07T00:00:00.000002Z",
      "replay_run_id" => "run/1",
      "source_binding_id" => "binding/1",
      "data_source_id" => "source/1",
      "scope_kind" => "spacecraft",
      "scope_id" => "sc/1",
      "sample_id" => "sample/1",
      "selected_time" => "2026-09-07T00:00:00.000002Z"
    }

    assert {:ok, context} = ExplorationQuery.admit(params, @now)
    assert context.query == params
    assert context.data.realm == "replay"
    assert context.data.source_mode == "specific"
    assert context.sample_id == "sample/1"
    assert DateTime.diff(context.time.to, context.time.from, :microsecond) == 1
    assert context.scope.primary.ids == ["sc/1"]
  end

  test "normalizes the legacy data view alias but rejects conflicting representations" do
    assert {:ok, %{query: %{"selection_view" => "as_recorded"}}} =
             ExplorationQuery.admit(%{"data_view" => "as_recorded"})

    assert {:error, _} =
             ExplorationQuery.admit(%{
               "data_view" => "as_recorded",
               "selection_view" => "canonical"
             })
  end

  test "invalid selectors never become a broader default query" do
    for params <- [
          %{"organization_id" => "forged"},
          %{"point_id" => "bad\npoint"},
          %{"point_id" => <<255>>},
          %{"point_id" => String.duplicate("é", 129)},
          %{"time_mode" => "unknown"},
          %{"time_mode" => "archive"},
          %{"time_mode" => "latest", "from" => "2026-09-07T00:00:00Z"},
          %{
            "time_mode" => "range",
            "from" => "2026-02-30T00:00:00Z",
            "to" => "2026-03-01T00:00:00Z"
          },
          %{
            "time_mode" => "range",
            "from" => "2026-01-01T00:00:00Z",
            "to" => "2026-03-01T00:00:00Z"
          },
          %{"realm" => "replay"},
          %{"replay_run_id" => "run"},
          %{"time_mode" => "replay_run", "realm" => "flight", "replay_run_id" => "run"},
          %{"scope_kind" => "contact"},
          %{"scope_id" => "foreign"},
          %{"scope_kind" => "spacecraft", "scope_id" => "one", "spacecraft_id" => "two"},
          %{"sample_id" => "sample"},
          %{"selected_time" => "2026-09-07T00:00:00Z"},
          %{"selected_data_source_id" => "source"},
          %{"selected_source_binding_id" => "binding"},
          %{"selected_data_source_id" => "source", "selected_source_binding_id" => "binding"},
          %{"limit" => "1001"},
          %{"limit" => "0"},
          %{"limit" => "+10"},
          %{"limit" => 10},
          %{"validity_state" => "anything"},
          %{"selection_view" => "unknown"}
        ],
        do: assert({:error, :invalid_exploration_context} == ExplorationQuery.admit(params, @now))
  end

  test "selected source pins are navigation state, not execution source selectors" do
    params = %{"point_id" => "HK.counter", "time_mode" => "last_1h"}
    assert {:ok, base} = ExplorationQuery.admit(params, @now)

    selected =
      Map.merge(params, %{
        "sample_id" => "sample",
        "selected_data_source_id" => "historical-source",
        "selected_source_binding_id" => "binding"
      })

    assert {:ok, selection} = ExplorationQuery.admit(selected, @now)
    assert selection.query == selected
    assert selection.data == base.data
    assert {:ok, original_request} = ExplorationRequest.build("org", "mission", base)
    assert {:ok, selected_request} = ExplorationRequest.build("org", "mission", selection)
    assert selected_request == original_request
  end
end
