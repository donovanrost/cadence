defmodule CadenceWeb.OpsDashboardShowLive.SelectedDataRefTimeContextTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef

  test "matches selected refs against archive bounds" do
    selected_ref = %{"target" => "telemetry_sample", "timestamp_ms" => 1_500}

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "archive",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "archive",
                 "from" => DateTime.from_unix!(2, :second),
                 "to" => DateTime.from_unix!(3, :second)
               }
             })
           )
  end

  test "matches selected refs against replay run context and bounds" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_500,
      "replay_run_id" => "replay-run-1",
      "time_axis" => "generation_time"
    }

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "replay_run",
                 "axis" => "generation_time",
                 "replay_run_id" => "replay-run-1",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "replay_run",
                 "axis" => "generation_time",
                 "replay_run_id" => "replay-run-2",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "replay_run",
                 "axis" => "generation_time",
                 "replay_run_id" => "replay-run-1",
                 "from" => DateTime.from_unix!(2, :second),
                 "to" => DateTime.from_unix!(3, :second)
               }
             })
           )
  end

  test "derives pause archive ranges from integer and string timestamps" do
    assert SelectedDataRef.archive_range(%{"timestamp_ms" => 1_000}) ==
             {:ok, "1969-12-31T23:57:31.000Z", "1970-01-01T00:02:31.000Z"}

    assert SelectedDataRef.archive_range(%{timestamp_ms: "1000"}) ==
             {:ok, "1969-12-31T23:57:31.000Z", "1970-01-01T00:02:31.000Z"}

    assert SelectedDataRef.archive_range(%{"timestamp_ms" => "bad"}) == :error
  end

  defp runtime_context(overrides) do
    Map.merge(
      %{
        scope_kind: nil,
        scope_id: nil,
        spacecraft_id: nil,
        time_context: %{"mode" => "live"},
        replay_run_id: nil,
        realm: nil,
        data_view: nil,
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        limit_mode: nil,
        data_context: %{}
      },
      overrides
    )
  end
end
