defmodule Cadence.Application.Missions.MissionConfigMetrics do
  @moduledoc """
  Lightweight counters for mission configuration validation signals.
  """

  @table_name :cadence_mission_config_metrics

  @spec inc(binary(), atom(), non_neg_integer()) :: :ok
  def inc(mission_id, metric, amount \\ 1)
      when is_binary(mission_id) and is_atom(metric) and is_integer(amount) and amount >= 0 do
    ensure_table()
    key = {mission_id, metric}
    :ets.update_counter(@table_name, key, {2, amount}, {key, 0})
    :ok
  end

  @spec get_stats(binary()) :: map()
  def get_stats(mission_id) when is_binary(mission_id) do
    ensure_table()

    :ets.select(@table_name, [
      {{{mission_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Map.new()
  end

  defp ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ref ->
        :ok
    end
  end
end
