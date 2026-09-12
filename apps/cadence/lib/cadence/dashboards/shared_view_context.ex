defmodule Cadence.Dashboards.SharedViewContext do
  @moduledoc "Finite admission of persisted share/snapshot context; never browser overrides."
  alias Cadence.Dashboards.AuthoringInput

  @enums %{
    "time_mode" => ~w(live range archive replay_run),
    "time_axis" => ~w(generation_time receipt_time),
    "realm" => ~w(flight rehearsal replay simulation),
    "data_view" => ~w(canonical as_recorded all_revisions recomputed),
    "limit_mode" => ~w(observed current recomputed compare),
    "scope_kind" => ~w(mission spacecraft contact ground_station source_endpoint transport link)
  }
  @ids ~w(spacecraft_id scope_id replay_run_id data_source_id source_binding_id selected_id)
  @keys Map.keys(@enums) ++ @ids ++ ~w(from to selected_target)

  def admit(value, mission) when is_map(value) do
    with true <- Enum.all?(value, &valid_field?/1),
         {:ok, time} <- time(value),
         {:ok, scope} <- scope(value, mission),
         true <- paired?(value, "selected_target", "selected_id") do
      {:ok,
       %{
         time_context: time,
         scope_context: scope,
         data_context:
           compact(%{
             realm: value["realm"],
             view: value["data_view"],
             data_source_id: value["data_source_id"],
             source_binding_id: value["source_binding_id"],
             replay_run_id: value["replay_run_id"]
           }),
         limit_context: compact(%{semantics_mode: value["limit_mode"]}),
         interaction_context: Map.take(value, ~w(selected_target selected_id))
       }}
    else
      _ -> {:error, :invalid_context}
    end
  end

  def admit(_, _), do: {:error, :invalid_context}

  defp valid_field?({key, value}) do
    cond do
      key not in @keys ->
        false

      Map.has_key?(@enums, key) ->
        value in @enums[key]

      key in @ids ->
        AuthoringInput.id?(value)

      key == "selected_target" ->
        is_binary(value) and byte_size(value) <= 64 and Regex.match?(~r/^[a-z][a-z0-9_]*$/, value)

      true ->
        is_binary(value) and byte_size(value) <= 40
    end
  end

  defp time(v) do
    explicit_mode = v["time_mode"] || if(v["from"] || v["to"], do: "range")

    base =
      compact(%{mode: explicit_mode, axis: v["time_axis"], replay_run_id: v["replay_run_id"]})

    admit_time(explicit_mode || "live", v, base)
  end

  defp admit_time(mode, v, base) do
    case {mode, v["from"], v["to"]} do
      {mode, from, to} when mode in ["range", "archive"] ->
        with {:ok, a, _} <- DateTime.from_iso8601(from),
             {:ok, b, _} <- DateTime.from_iso8601(to),
             duration = DateTime.diff(b, a, :microsecond),
             true <- duration > 0 and duration <= 31 * 86_400_000_000,
             true <- is_nil(v["replay_run_id"]) do
          {:ok, Map.merge(base, %{from: a, to: b})}
        else
          _ -> {:error, :invalid_context}
        end

      {"live", nil, nil} when not is_map_key(v, "replay_run_id") ->
        {:ok, base}

      {"replay_run", nil, nil} when is_map_key(v, "replay_run_id") ->
        {:ok, base}

      _ ->
        {:error, :invalid_context}
    end
  rescue
    _ -> {:error, :invalid_context}
  end

  defp scope(v, _mission)
       when not is_map_key(v, "scope_kind") and not is_map_key(v, "scope_id") and
              not is_map_key(v, "spacecraft_id"),
       do: {:ok, %{}}

  defp scope(v, mission) do
    {kind, id} = primary(v, mission)

    valid =
      is_binary(id) and (kind != "mission" or id == mission) and
        same_spacecraft?(v["spacecraft_id"], kind, id)

    if valid,
      do: {:ok, %{primary: %{kind: kind, mode: "one", ids: [id]}}},
      else: {:error, :invalid_context}
  end

  defp primary(v, mission) do
    kind = v["scope_kind"] || if(v["spacecraft_id"], do: "spacecraft", else: "mission")
    {kind, v["scope_id"] || v["spacecraft_id"] || if(kind == "mission", do: mission)}
  end

  defp same_spacecraft?(nil, _, _), do: true
  defp same_spacecraft?(spacecraft, kind, id), do: kind == "spacecraft" and id == spacecraft

  defp paired?(v, a, b), do: Map.has_key?(v, a) == Map.has_key?(v, b)
  defp compact(v), do: Map.reject(v, fn {_, value} -> is_nil(value) end)
end
