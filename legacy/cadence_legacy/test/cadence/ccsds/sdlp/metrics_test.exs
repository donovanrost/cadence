defmodule Cadence.CCSDS.SDLP.MetricsTest do
  use Cadence.PureCase, async: false

  alias Cadence.CCSDS.SDLP.Metrics

  @table_name :cadence_sdlp_metrics

  setup do
    case Process.whereis(Cadence.ETS.Owner) do
      nil -> start_supervised!(Cadence.ETS.Owner)
      _pid -> :ok
    end

    delete_table(@table_name)
    on_exit(fn -> delete_table(@table_name) end)
    :ok
  end

  test "concurrent first use does not race named table creation" do
    scope = random_id()
    parent = self()

    tasks =
      for _ <- 1..32 do
        Task.async(fn ->
          send(parent, :ready)

          receive do
            :go -> Metrics.inc(scope, :tm, :segmentation_calls)
          end
        end)
      end

    Enum.each(tasks, fn _task -> assert_receive :ready, 1_000 end)
    Enum.each(tasks, fn task -> send(task.pid, :go) end)

    assert Enum.map(tasks, &Task.await(&1, 1_000)) == List.duplicate(:ok, length(tasks))
    assert get_in(Metrics.get_stats(scope), [:tm, :segmentation, :calls]) == 32
  end

  defp delete_table(table_name) do
    case :ets.whereis(table_name) do
      :undefined -> :ok
      tid -> :ets.delete(tid)
    end
  end
end
