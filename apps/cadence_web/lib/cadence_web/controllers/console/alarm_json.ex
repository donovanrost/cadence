defmodule CadenceWeb.Console.AlarmJSON do
  @moduledoc "Wire shape of the console alarm list. Contract: docs/apogee/api/ops.md."

  alias CadenceWeb.Console.WireValue

  @threshold_keys ~w(red_low yellow_low yellow_high red_high)

  @spec list(map()) :: map()
  def list(%{observed_at: observed_at, summary: summary, alarms: alarms}) do
    %{observed_at: observed_at, summary: summary, alarms: Enum.map(alarms, &alarm/1)}
  end

  defp alarm(row) do
    %{
      id: row.id,
      spacecraft_id: row.spacecraft_id,
      point: %{
        id: row.point_id,
        name: row.point_name,
        subsystem: row.subsystem,
        unit: row.unit,
        description: row.description
      },
      severity: Atom.to_string(row.severity),
      active: row.active?,
      condition: row.limit_state && to_string(row.limit_state),
      value: WireValue.encode(row.evaluated_value),
      limit_set_name: row.limit_set_name,
      thresholds: thresholds(row.thresholds),
      first_crossed_at: row.first_crossed_at,
      generation_time: row.generation_time,
      received_at: row.receipt_time
    }
  end

  defp thresholds(nil), do: nil

  defp thresholds(thresholds) do
    Map.new(@threshold_keys, &{&1, WireValue.encode(Map.get(thresholds, &1))})
  end
end
