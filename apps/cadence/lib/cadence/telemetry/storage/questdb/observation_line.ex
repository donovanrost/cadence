defmodule Cadence.Telemetry.Storage.QuestDB.ObservationLine do
  @moduledoc "Serializes observation rows for QuestDB HTTP line-protocol ingestion."

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.QuestDB.ObservationRow

  @epoch ~N[1970-01-01 00:00:00]

  @spec encode(ObservationEnvelope.t()) :: binary()
  def encode(%ObservationEnvelope{} = envelope) do
    [{:observed_at, timestamp} | values] =
      Enum.zip(ObservationRow.columns(), ObservationRow.params(envelope))

    fields =
      values
      |> Enum.reject(fn {_column, value} -> is_nil(value) end)
      |> Enum.map_join(",", fn {column, value} -> "#{column}=#{field(value)}" end)

    "telemetry_observations " <> fields <> " #{unix_microseconds(timestamp) * 1_000}\n"
  end

  defp field(%NaiveDateTime{} = value), do: "#{unix_microseconds(value)}t"
  defp field(value) when is_integer(value), do: "#{value}i"
  defp field(value) when is_float(value), do: Float.to_string(value)
  defp field(true), do: "true"
  defp field(false), do: "false"

  defp field(value) when is_binary(value) do
    escaped = String.replace(value, ["\\", "\"", "\n", "\r"], &("\\" <> &1))
    "\"" <> escaped <> "\""
  end

  defp unix_microseconds(timestamp), do: NaiveDateTime.diff(timestamp, @epoch, :microsecond)
end
