defmodule Cadence.SemanticRuntime.IdBasis do
  @moduledoc """
  The canonical forms the evidence ids hash (#950, #166, #167): the monitoring evaluation id, the
  alarm transition id and the derived `parameter_update` id are each a `ContentBasis.digest/3` of
  NAMED SCALARS, never a whole struct or map, so a new struct field or default cannot fork an id
  that a replay recomputes.

    * `time/1`: a DateTime as UTC ISO-8601 with microseconds (always six digits), or nil.
    * `value/1`: a value a derived parameter can carry, in a canonical form `ContentBasis`
      encodes: nil, booleans, integers, floats, atoms, text, a non-text binary as tagged bytes, a
      DateTime as a tagged UTC time, a Decimal as its text in a tag, lists and maps of those.
      Anything else (a struct, tuple, pid, function) is `{:error, {:unsupported_value, type}}`:
      the derived output is refused with a reason, never hashed by accident.
  """

  alias Cadence.Platform.ContentBasis

  @doc "A time as canonical text (UTC, microseconds), or nil."
  @spec time(DateTime.t() | nil) :: binary() | nil
  def time(nil), do: nil

  def time(%DateTime{} = time) do
    utc = DateTime.shift_zone!(time, "Etc/UTC")
    {micro, _precision} = utc.microsecond
    DateTime.to_iso8601(%{utc | microsecond: {micro, 6}})
  end

  @doc "A derived value's canonical form for a basis, or the reason it has none."
  @spec value(term()) :: {:ok, term()} | {:error, {:unsupported_value, binary()}}
  def value(value) when is_nil(value) or is_boolean(value), do: {:ok, value}
  def value(value) when is_integer(value) or is_float(value) or is_atom(value), do: {:ok, value}

  def value(value) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: {:ok, ContentBasis.raw_bytes(value)}
  end

  def value(%DateTime{} = value), do: {:ok, %{"$cadence_datetime" => time(value)}}

  def value(%Decimal{} = value), do: {:ok, %{"$cadence_decimal" => Decimal.to_string(value)}}

  def value(value) when is_list(value), do: collect(value, &value/1)

  def value(%_{} = struct), do: {:error, {:unsupported_value, inspect(struct.__struct__)}}

  def value(value) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {key, inner}, {:ok, acc} ->
      with true <- is_binary(key) or is_atom(key),
           {:ok, canonical} <- value(inner) do
        {:cont, {:ok, Map.put(acc, key, canonical)}}
      else
        false -> {:halt, {:error, {:unsupported_value, "map key"}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def value(value), do: {:error, {:unsupported_value, type(value)}}

  defp collect(list, fun) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, canonical} -> {:cont, {:ok, [canonical | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp type(value) when is_tuple(value), do: "tuple"
  defp type(value) when is_pid(value), do: "pid"
  defp type(value) when is_reference(value), do: "reference"
  defp type(value) when is_function(value), do: "function"
  defp type(value) when is_port(value), do: "port"
  defp type(_value), do: "term"
end
