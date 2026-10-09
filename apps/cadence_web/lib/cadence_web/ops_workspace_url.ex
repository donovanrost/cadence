defmodule CadenceWeb.OpsWorkspaceURL do
  @moduledoc """
  Admits the dashboard viewer's browser context before domain resolution.

  Only explicit scalar enums, Grafana-style time bounds and a single spacecraft
  scope enter the runtime. Identity comes from the router; the spacecraft must
  still be checked against the mission by the page adapter. Source/replay
  selection and drilldown require separate resource admission; until then they
  are rejected, never silently discarded.

  Time bounds follow `Cadence.Dashboards.TimeRange`: `from=now-6h&to=now` is a
  live sliding window, absolute ISO-8601 bounds are a frozen range.
  """
  alias Cadence.Dashboards.TimeRange

  @enums %{
    "time_mode" => ~w(live range archive),
    "time_axis" => ~w(generation_time receipt_time),
    "realm" => ~w(flight rehearsal replay simulation),
    "selection_view" => ~w(canonical as_recorded all_revisions recomputed),
    "limit_mode" => ~w(observed current recomputed compare)
  }
  @keys Map.keys(@enums) ++ ~w(from to spacecraft mission_id dashboard_id)
  @max_range_seconds 31 * 24 * 60 * 60

  def admit(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @keys)),
         true <- valid_enums?(params),
         {:ok, time} <- time(params),
         {:ok, scope} <- scope(params["spacecraft"]) do
      {:ok,
       %{
         time_context: time,
         scope_context: scope,
         data_context: put(%{}, :realm, params["realm"]) |> put(:view, params["selection_view"]),
         limit_context: put(%{}, :semantics_mode, params["limit_mode"])
       }}
    else
      _ -> {:error, :invalid_context}
    end
  end

  def admit(_), do: {:error, :invalid_context}

  @doc "The spacecraft selected by an admitted runtime, if any."
  def spacecraft(%{scope_context: %{spacecraft_id: id}}), do: id
  def spacecraft(_runtime), do: nil

  defp valid_enums?(params) do
    Enum.all?(@enums, fn {key, values} ->
      not Map.has_key?(params, key) or params[key] in values
    end)
  end

  defp time(params) do
    mode = params["time_mode"]
    base = put(%{}, :mode, mode) |> put(:axis, params["time_axis"])

    case {Map.get(params, "from"), Map.get(params, "to")} do
      {nil, nil} when mode in [nil, "live"] -> {:ok, base}
      {from, to} when is_binary(from) and is_binary(to) -> bounded(base, mode, from, to)
      _ -> {:error, :invalid_context}
    end
  end

  defp bounded(base, mode, from, to) do
    if relative?(from) or relative?(to),
      do: sliding(base, mode, from, to),
      else: absolute(base, mode, from, to)
  end

  # Relative bounds must describe a window ending now; frozen relative ranges
  # would silently change meaning on every refresh.
  defp sliding(base, mode, from, to) when mode in [nil, "live"] do
    case TimeRange.resolve(from, to, DateTime.utc_now()) do
      {:ok, {:sliding, seconds}} ->
        {:ok, Map.merge(base, %{mode: "live", window_seconds: seconds})}

      _ ->
        {:error, :invalid_context}
    end
  end

  defp sliding(_base, _mode, _from, _to), do: {:error, :invalid_context}

  defp absolute(base, mode, from, to) when mode in [nil, "range", "archive"] do
    with {:ok, from} <- timestamp(from),
         {:ok, to} <- timestamp(to),
         duration = DateTime.diff(to, from, :microsecond),
         true <- duration > 0 and duration <= @max_range_seconds * 1_000_000 do
      {:ok, Map.merge(base, %{mode: mode || "range", from: from, to: to})}
    else
      _ -> {:error, :invalid_context}
    end
  end

  defp absolute(_base, _mode, _from, _to), do: {:error, :invalid_context}

  defp relative?(value), do: String.starts_with?(value, "now")

  defp scope(nil), do: {:ok, %{}}

  defp scope(id) when is_binary(id) and byte_size(id) in 1..256 do
    if String.valid?(id),
      do: {:ok, %{primary: %{kind: "spacecraft", mode: "one", ids: [id]}, spacecraft_id: id}},
      else: {:error, :invalid_context}
  end

  defp scope(_), do: {:error, :invalid_context}

  defp timestamp(value) when is_binary(value) and byte_size(value) <= 40 do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> {:ok, time}
      _ -> {:error, :invalid_context}
    end
  end

  defp timestamp(_), do: {:error, :invalid_context}
  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
