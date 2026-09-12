defmodule CadenceWeb.OpsWorkspaceURL do
  @moduledoc """
  Admits the dashboard viewer's browser context before domain resolution.

  Only explicit scalar enums and bounded UTC ranges enter the runtime. Identity
  comes from the router. Source/replay selection and drilldown require separate
  resource admission; until then they are rejected, never silently discarded.
  """
  @enums %{
    "time_mode" => ~w(live range archive),
    "time_axis" => ~w(generation_time receipt_time),
    "realm" => ~w(flight rehearsal replay simulation),
    "selection_view" => ~w(canonical as_recorded all_revisions recomputed),
    "limit_mode" => ~w(observed current recomputed compare)
  }
  @keys Map.keys(@enums) ++ ~w(from to mission_id dashboard_id)
  @max_range_seconds 31 * 24 * 60 * 60

  def admit(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @keys)),
         true <- valid_enums?(params),
         {:ok, time} <- time(params) do
      {:ok,
       %{
         time_context: time,
         data_context: put(%{}, :realm, params["realm"]) |> put(:view, params["selection_view"]),
         limit_context: put(%{}, :semantics_mode, params["limit_mode"])
       }}
    else
      _ -> {:error, :invalid_context}
    end
  end

  def admit(_), do: {:error, :invalid_context}

  defp valid_enums?(params) do
    Enum.all?(@enums, fn {key, values} ->
      not Map.has_key?(params, key) or params[key] in values
    end)
  end

  defp time(params) do
    mode = params["time_mode"]
    base = put(%{}, :mode, mode) |> put(:axis, params["time_axis"])

    case {mode, Map.has_key?(params, "from"), Map.has_key?(params, "to")} do
      {mode, true, true} when mode in ["range", "archive"] ->
        with {:ok, from} <- timestamp(params["from"]),
             {:ok, to} <- timestamp(params["to"]),
             duration = DateTime.diff(to, from, :microsecond),
             true <- duration > 0 and duration <= @max_range_seconds * 1_000_000 do
          {:ok, Map.merge(base, %{from: from, to: to})}
        else
          _ -> {:error, :invalid_context}
        end

      {mode, false, false} when mode in [nil, "live"] ->
        {:ok, base}

      _ ->
        {:error, :invalid_context}
    end
  end

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
