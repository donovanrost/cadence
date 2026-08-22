defmodule Cadence.Telemetry.LatestProjectionOrder do
  @moduledoc """
  Shared ordering policy for latest/current telemetry projections.

  Latest projections are source-time-first: compare `generation_time` when
  present, fall back to `receipt_time`, then break ties by receipt time and a
  stable row id. This keeps late-arriving historical observations from
  replacing current state while still making same-time retries deterministic.
  """

  @type comparison :: :lt | :eq | :gt

  @spec newer?(map() | struct(), map() | struct(), atom()) :: boolean()
  def newer?(candidate, current, id_field) when is_atom(id_field) do
    compare(candidate, current, id_field) == :gt
  end

  @spec compare(map() | struct(), map() | struct(), atom()) :: comparison()
  def compare(left, right, id_field) when is_atom(id_field) do
    compare_keys(sort_key(left, id_field), sort_key(right, id_field))
  end

  @spec sort_key(map() | struct(), atom()) :: {DateTime.t() | nil, DateTime.t() | nil, term()}
  def sort_key(value, id_field) when is_atom(id_field) do
    {projection_time(value), attr(value, :receipt_time), attr(value, id_field)}
  end

  @spec projection_time(map() | struct()) :: DateTime.t() | nil
  def projection_time(value) do
    attr(value, :generation_time) || attr(value, :receipt_time)
  end

  @spec compare_keys(tuple(), tuple()) :: comparison()
  def compare_keys({time_a, receipt_a, id_a}, {time_b, receipt_b, id_b}) do
    case compare_datetimes(time_a, time_b) do
      :eq ->
        case compare_datetimes(receipt_a, receipt_b) do
          :eq -> compare_ids(id_a, id_b)
          other -> other
        end

      other ->
        other
    end
  end

  defp compare_datetimes(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_datetimes(%DateTime{}, nil), do: :gt
  defp compare_datetimes(nil, %DateTime{}), do: :lt
  defp compare_datetimes(nil, nil), do: :eq

  defp compare_ids(left, right) when left > right, do: :gt
  defp compare_ids(left, right) when left < right, do: :lt
  defp compare_ids(_left, _right), do: :eq

  defp attr(%_{} = value, key), do: value |> Map.from_struct() |> attr(key)

  defp attr(value, key) when is_map(value),
    do: Map.get(value, key, Map.get(value, to_string(key)))

  defp attr(_value, _key), do: nil
end
