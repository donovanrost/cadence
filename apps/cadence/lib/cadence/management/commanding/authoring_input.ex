defmodule Cadence.Management.Commanding.AuthoringInput do
  @moduledoc "Finite human command authoring inputs; actors and derived command fields are server-owned."

  alias Cadence.Ids
  alias Cadence.Management.Commanding.ArgumentDocument

  @max_priority 2_147_483_647

  def preview(
        %{
          "expected_basis" => basis,
          "source_endpoint_ref" => endpoint,
          "command_id" => command,
          "argument_values_json" => arguments_json,
          "priority" => priority,
          "not_before" => not_before,
          "expires_at" => expires_at
        } = input
      )
      when map_size(input) == 7 do
    with true <- digest?(basis),
         {:ok, _} <- Ids.path_segment(endpoint),
         {:ok, _} <- Ids.path_segment(command),
         true <- is_integer(priority) and priority in 0..@max_priority,
         {:ok, arguments} <- ArgumentDocument.decode(arguments_json),
         {:ok, not_before} <- timestamp(not_before),
         {:ok, expires_at} <- timestamp(expires_at),
         :ok <- timing(not_before, expires_at) do
      {:ok,
       %{
         expected_basis: basis,
         source_endpoint_ref: endpoint,
         command_id: command,
         argument_values: arguments,
         priority: priority,
         not_before: not_before,
         expires_at: expires_at
       }}
    else
      _ -> {:error, :invalid_command_authoring_input}
    end
  end

  def preview(_), do: {:error, :invalid_command_authoring_input}

  def create(%{"expected_preview" => preview} = input) when map_size(input) == 1 do
    if digest?(preview),
      do: {:ok, preview},
      else: {:error, :invalid_command_authoring_input}
  end

  def create(_), do: {:error, :invalid_command_authoring_input}

  defp digest?(value),
    do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp timestamp(nil), do: {:ok, nil}

  defp timestamp(value) when is_binary(value) and byte_size(value) <= 32 do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} -> {:ok, datetime}
      _ -> {:error, :invalid_command_time}
    end
  end

  defp timestamp(_), do: {:error, :invalid_command_time}

  defp timing(_, nil), do: :ok
  defp timing(nil, %DateTime{}), do: :ok

  defp timing(%DateTime{} = not_before, %DateTime{} = expires_at) do
    if DateTime.compare(not_before, expires_at) == :lt,
      do: :ok,
      else: {:error, :invalid_command_time_order}
  end
end
