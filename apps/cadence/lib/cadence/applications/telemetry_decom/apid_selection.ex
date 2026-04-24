defmodule Cadence.Applications.TelemetryDecom.APIDSelection do
  @moduledoc false

  @type parse_error ::
          {:invalid_apid_token, binary()}
          | {:invalid_apid_range, binary()}
          | :handled_apids_required

  @spec parse(binary() | [integer() | binary()] | nil) ::
          {:ok, [non_neg_integer()]} | {:error, parse_error()}
  def parse(nil), do: {:error, :handled_apids_required}
  def parse(""), do: {:error, :handled_apids_required}

  def parse(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> parse_tokens()
  end

  def parse(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> parse_tokens()
  end

  @spec format([non_neg_integer()]) :: binary()
  def format(apids) when is_list(apids) do
    Enum.map_join(apids, ", ", &Integer.to_string/1)
  end

  defp parse_tokens([]), do: {:error, :handled_apids_required}

  defp parse_tokens(tokens) do
    with {:ok, apids} <- expand_tokens(tokens) do
      {:ok, apids |> Enum.uniq() |> Enum.sort()}
    end
  end

  defp expand_tokens(tokens) do
    Enum.reduce_while(tokens, {:ok, []}, fn token, {:ok, apids} ->
      case expand_token(token) do
        {:ok, parsed_apids} -> {:cont, {:ok, apids ++ parsed_apids}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp expand_token(token) do
    cond do
      token == "" ->
        {:error, {:invalid_apid_token, token}}

      String.contains?(token, "-") ->
        expand_range(token)

      true ->
        parse_single(token)
    end
  end

  defp expand_range(token) do
    case String.split(token, "-", parts: 2) do
      [start_token, end_token] ->
        with {:ok, start_apid} <- parse_non_negative_integer(String.trim(start_token), token),
             {:ok, end_apid} <- parse_non_negative_integer(String.trim(end_token), token),
             true <- start_apid <= end_apid do
          {:ok, Enum.to_list(start_apid..end_apid)}
        else
          false -> {:error, {:invalid_apid_range, token}}
          {:error, _reason} -> {:error, {:invalid_apid_range, token}}
        end

      _other ->
        {:error, {:invalid_apid_range, token}}
    end
  end

  defp parse_single(token) do
    case parse_non_negative_integer(token, token) do
      {:ok, apid} -> {:ok, [apid]}
      {:error, _reason} -> {:error, {:invalid_apid_token, token}}
    end
  end

  defp parse_non_negative_integer(token, original_token) do
    case Integer.parse(token) do
      {value, ""} when value >= 0 -> {:ok, value}
      _other -> {:error, {:invalid_apid_token, original_token}}
    end
  end
end
