defmodule Cadence.Runtime.Transport.COP1.Metrics do
  @moduledoc """
  Lightweight COP-1 metrics keyed by mission/interface/scid/vcid.
  """

  @table_name :cadence_cop1_metrics

  def inc(mission_id, interface_id, scid, vcid, metric, amount \\ 1) do
    ensure_table()
    key = {mission_id, interface_id, scid, vcid, metric}
    :ets.update_counter(@table_name, key, {2, amount}, {key, 0})
    :ok
  end

  def set_gauge(mission_id, interface_id, scid, vcid, metric, value)
      when is_integer(value) do
    ensure_table()
    key = {mission_id, interface_id, scid, vcid, metric}
    :ets.insert(@table_name, {key, value})
    :ok
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
