defmodule Cadence.TestLogFilter do
  @moduledoc false

  @noisy_patterns [
    "CRC mismatch",
    "CCSDS CRC mismatch",
    "Failed to parse JSON packet",
    "DAG step '",
    "DAG: ",
    "[GET_COMMAND] NOT FOUND",
    "Stage ",
    "Max clients ("
  ]

  def filter(%{level: level, msg: msg}, _opts) when level in [:warning, :error] do
    message = format_message(msg)

    if noisy_message?(message) do
      :stop
    else
      :log
    end
  end

  def filter(_event, _opts), do: :log

  defp noisy_message?(message) do
    Enum.any?(@noisy_patterns, &String.contains?(message, &1))
  end

  defp format_message({format, args}) when is_list(args) do
    format
    |> :io_lib.format(args)
    |> IO.iodata_to_binary()
  end

  defp format_message(message) when is_binary(message), do: message
  defp format_message(_message), do: ""
end
