defmodule Cadence.Telemetry.Storage.QuestDB.SQL do
  @moduledoc """
  SQL literal helpers for Cadence-owned QuestDB statements.
  """

  @spec literal(term()) :: binary()
  def literal(nil), do: "NULL"

  def literal(%NaiveDateTime{} = datetime),
    do: quote_string(NaiveDateTime.to_iso8601(datetime) <> "Z")

  def literal(%DateTime{} = datetime), do: datetime |> DateTime.to_iso8601() |> quote_string()
  def literal(value) when is_binary(value), do: quote_string(value)
  def literal(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  def literal(value) when is_integer(value) or is_float(value), do: to_string(value)

  @spec quote_string(binary()) :: binary()
  def quote_string(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "''") <> "'"
  end
end
