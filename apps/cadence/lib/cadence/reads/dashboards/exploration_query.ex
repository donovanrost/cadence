defmodule Cadence.Reads.Dashboards.ExplorationQuery do
  @moduledoc "Finite exploration URL context; parsing does not execute sources or grant authority."

  @keys ~w(point_id spacecraft_id scope_kind scope_id time_mode time_axis from to replay_run_id order limit selection_view data_view validity_state realm logical_source data_source_id source_binding_id source_dashboard_id sample_id selected_time selected_data_source_id selected_source_binding_id question limit_mode)
  @enums %{
    "time_mode" => ~w(latest live last_15m last_1h last_6h last_24h range archive replay_run),
    "time_axis" => ~w(generation_time receipt_time),
    "scope_kind" => ~w(mission spacecraft contact source_endpoint ground_station transport link),
    "order" => ~w(asc desc),
    "selection_view" => ~w(canonical as_recorded all_revisions recomputed),
    "validity_state" => ~w(canonical duplicate conflict superseded advisory),
    "realm" => ~w(flight rehearsal replay simulation),
    "logical_source" => ~w(telemetry operational_observables),
    "question" => ~w(recent_anomalies what_changed missing_history link_degradation),
    "limit_mode" => ~w(observed current recomputed compare)
  }
  @windows %{
    "live" => 900,
    "last_15m" => 900,
    "last_1h" => 3600,
    "last_6h" => 21_600,
    "last_24h" => 86_400
  }

  def admit(params, now \\ DateTime.utc_now())

  def admit(params, %DateTime{} = now)
      when is_map(params) and map_size(params) <= length(@keys) do
    with true <-
           Enum.all?(params, fn {key, value} -> key in @keys and text?(value, 256, true) end),
         {:ok, query} <- aliases(Map.reject(params, fn {_, value} -> value == "" end)),
         true <-
           Enum.all?(@enums, fn {key, values} ->
             not Map.has_key?(query, key) or query[key] in values
           end),
         {:ok, limit} <- limit(query),
         :ok <- scope(query),
         :ok <- replay(query),
         :ok <- selected(query),
         {:ok, time} <- time(query, now) do
      {:ok,
       %{
         query: query,
         point_id: query["point_id"],
         sample_id: query["sample_id"],
         limit: limit,
         order: Map.get(query, "order", "desc"),
         logical_source: Map.get(query, "logical_source", "telemetry"),
         time: time,
         data: %{
           realm:
             Map.get(
               query,
               "realm",
               if(query["time_mode"] == "replay_run", do: "replay", else: "flight")
             ),
           source_mode:
             if(query["data_source_id"] || query["source_binding_id"],
               do: "specific",
               else: "primary"
             ),
           data_source_id: query["data_source_id"],
           source_binding_id: query["source_binding_id"],
           view: Map.get(query, "selection_view", "canonical"),
           validity_state: query["validity_state"],
           replay_run_id: query["replay_run_id"]
         },
         scope: scope_context(query),
         limits: %{semantics_mode: Map.get(query, "limit_mode", "observed")}
       }}
    else
      _ -> {:error, :invalid_exploration_context}
    end
  end

  def admit(_, _), do: {:error, :invalid_exploration_context}

  defp aliases(%{"data_view" => view} = query) do
    if Map.get(query, "selection_view", view) == view,
      do: {:ok, query |> Map.delete("data_view") |> Map.put("selection_view", view)},
      else: :error
  end

  defp aliases(query), do: {:ok, query}

  defp limit(query) do
    value = Map.get(query, "limit", "100")

    case Integer.parse(value) do
      {n, ""} when n in 1..1000 ->
        if Regex.match?(~r/\A[0-9]+\z/, value), do: {:ok, n}, else: :error

      _ ->
        :error
    end
  end

  defp scope(query) do
    cond do
      Map.has_key?(query, "scope_kind") != Map.has_key?(query, "scope_id") ->
        :error

      query["scope_kind"] == "spacecraft" and
          query["spacecraft_id"] not in [nil, query["scope_id"]] ->
        :error

      true ->
        :ok
    end
  end

  defp scope_context(query) do
    primary =
      if query["scope_kind"],
        do: %{kind: query["scope_kind"], mode: "one", ids: [query["scope_id"]]},
        else: nil

    %{primary: primary, spacecraft_id: query["spacecraft_id"]}
  end

  defp replay(query) do
    realm =
      Map.get(
        query,
        "realm",
        if(query["time_mode"] == "replay_run", do: "replay", else: "flight")
      )

    cond do
      query["time_mode"] == "replay_run" and realm != "replay" -> :error
      realm == "replay" and is_nil(query["replay_run_id"]) -> :error
      realm != "replay" and Map.has_key?(query, "replay_run_id") -> :error
      true -> :ok
    end
  end

  defp selected(query) do
    with true <- is_nil(query["sample_id"]) or not is_nil(query["point_id"]),
         true <- is_nil(query["selected_time"]) or not is_nil(query["sample_id"]),
         true <-
           is_nil(query["selected_data_source_id"]) == is_nil(query["selected_source_binding_id"]),
         true <- is_nil(query["selected_data_source_id"]) or not is_nil(query["sample_id"]),
         {:ok, _} <- timestamp(query["selected_time"]) do
      :ok
    else
      _ -> :error
    end
  end

  defp time(query, now) do
    mode = Map.get(query, "time_mode", "latest")
    axis = Map.get(query, "time_axis", "receipt_time")

    with {:ok, from} <- timestamp(query["from"]), {:ok, to} <- timestamp(query["to"]) do
      resolve_time(mode, axis, {from, to}, query, now)
    end
  end

  defp resolve_time("latest", axis, {nil, nil}, _, _),
    do: {:ok, %{mode: "live", axis: axis, from: nil, to: nil}}

  defp resolve_time(mode, axis, {nil, nil}, _, now) when is_map_key(@windows, mode) do
    {:ok,
     %{
       mode: "range",
       axis: axis,
       from: DateTime.add(now, -Map.fetch!(@windows, mode), :second),
       to: now
     }}
  end

  defp resolve_time(mode, axis, {%DateTime{} = from, %DateTime{} = to}, query, _)
       when mode in ~w(range archive replay_run live) do
    duration = DateTime.diff(to, from, :microsecond)

    if duration > 0 and duration <= 31 * 86_400 * 1_000_000 do
      {:ok,
       %{
         mode: if(mode == "replay_run", do: mode, else: "range"),
         axis: axis,
         from: from,
         to: to,
         replay_run_id: query["replay_run_id"]
       }}
    else
      :error
    end
  end

  defp resolve_time(_, _, _, _, _), do: :error

  defp timestamp(nil), do: {:ok, nil}

  defp timestamp(value) when is_binary(value) and byte_size(value) <= 40 do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> :error
    end
  end

  defp timestamp(_), do: :error

  defp text?(value, limit, empty?) when is_binary(value),
    do:
      (empty? or byte_size(value) > 0) and byte_size(value) <= limit and String.valid?(value) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/u, value)

  defp text?(_, _, _), do: false
end
