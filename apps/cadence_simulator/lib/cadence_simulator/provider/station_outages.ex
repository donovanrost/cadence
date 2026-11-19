defmodule CadenceSimulator.Provider.StationOutages do
  @moduledoc """
  The `station_outages` fault (S7): per-station availability windows a run reports as if the
  provider knew its own stations were down, in maintenance, or degraded.

  Each window is `%{"id", "ground_station_id", "kind", "starts_at", "ends_at" | nil, "reason"}`.
  `outage` and `maintenance` windows make overlapping opportunities `unavailable` and reject
  bookings; `degraded` windows are only reported. Stations list their windows under
  `availability_windows`.
  """

  @kinds ~w(outage maintenance degraded)
  @blocking ~w(outage maintenance)

  @spec normalize(term()) :: {:ok, [map()]} | {:error, {:invalid, binary()}}
  def normalize(windows) when is_list(windows) do
    windows
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {window, index}, {:ok, acc} ->
      case window(window, index) do
        {:ok, window} -> {:cont, {:ok, [window | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, windows} -> {:ok, Enum.reverse(windows)}
      error -> error
    end
  end

  def normalize(_windows), do: invalid()

  @doc "Windows reported for `station_id`, as the provider API exposes them."
  @spec for_station(map(), binary()) :: [map()]
  def for_station(fault_profile, station_id) do
    fault_profile
    |> windows()
    |> Enum.filter(&(&1["ground_station_id"] == station_id))
    |> Enum.map(&Map.delete(&1, "ground_station_id"))
  end

  @doc "Whether an outage or maintenance window at `station_id` overlaps `[starts_at, ends_at)`."
  @spec blocked?(map(), binary(), DateTime.t(), DateTime.t()) :: boolean()
  def blocked?(fault_profile, station_id, %DateTime{} = starts_at, %DateTime{} = ends_at) do
    fault_profile
    |> windows()
    |> Enum.any?(fn window ->
      window["ground_station_id"] == station_id and window["kind"] in @blocking and
        DateTime.before?(parse!(window["starts_at"]), ends_at) and
        (is_nil(window["ends_at"]) or DateTime.after?(parse!(window["ends_at"]), starts_at))
    end)
  end

  defp windows(fault_profile), do: Map.get(fault_profile || %{}, "station_outages", [])

  defp window(%{} = window, index) do
    station = window["ground_station_id"]
    kind = Map.get(window, "kind", "outage")
    ends_at = window["ends_at"]

    with true <- is_binary(station) and station != "" and kind in @kinds,
         {:ok, starts_at} <- datetime(window["starts_at"]),
         {:ok, ends} <- optional_datetime(ends_at),
         true <- is_nil(ends) or DateTime.after?(ends, starts_at) do
      {:ok,
       %{
         "id" => Map.get(window, "id") || "station-outage-#{index + 1}",
         "ground_station_id" => station,
         "kind" => kind,
         "starts_at" => DateTime.to_iso8601(starts_at),
         "ends_at" => ends && DateTime.to_iso8601(ends),
         "reason" => Map.get(window, "reason")
       }}
    else
      _invalid -> invalid()
    end
  end

  defp window(_window, _index), do: invalid()

  defp optional_datetime(nil), do: {:ok, nil}
  defp optional_datetime(value), do: datetime(value)

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> :error
    end
  end

  defp datetime(_value), do: :error

  defp parse!(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp invalid, do: {:error, {:invalid, "fault_profile.station_outages is invalid"}}
end
