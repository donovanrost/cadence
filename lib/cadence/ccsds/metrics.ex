defmodule Cadence.CCSDS.Metrics do
  @moduledoc """
  Lightweight counters for CCSDS uplink/downlink processing steps.
  """

  @table_name :cadence_ccsds_metrics

  def inc(mission_id, transport_id, profile, metric, amount \\ 1) do
    ensure_table()
    key = {mission_id, transport_id, profile, metric}
    :ets.update_counter(@table_name, key, {2, amount}, {key, 0})
    :ok
  end

  def get_stats(mission_id) do
    ensure_table()

    mission_id
    |> select_rows()
    |> build_stats()
  end

  defp select_rows(mission_id) do
    :ets.select(@table_name, [
      {{{mission_id, :"$1", :"$2", :"$3"}, :"$4"}, [], [{{:"$1", :"$2", :"$3", :"$4"}}]}
    ])
  end

  defp build_stats(rows) do
    Enum.reduce(rows, %{}, fn {transport_id, profile, metric, count}, acc ->
      update_transport_stats(acc, transport_id, profile, metric, count)
    end)
  end

  defp update_transport_stats(acc, transport_id, profile, metric, count) do
    Map.update(acc, transport_id, %{profile => %{metric => count}}, fn transport_stats ->
      update_profile_stats(transport_stats, profile, metric, count)
    end)
  end

  defp update_profile_stats(interface_stats, profile, metric, count) do
    Map.update(interface_stats, profile, %{metric => count}, fn profile_stats ->
      Map.put(profile_stats, metric, count)
    end)
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
