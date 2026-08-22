defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivity do
  @moduledoc false

  alias Cadence.Dashboards.LifecycleEvent

  def build(%LifecycleEvent{event_type: :health_snapshot_captured, payload: payload}) do
    payload = payload_map(payload)
    snapshot = payload |> map_value("snapshot") |> payload_map()
    counts = snapshot |> map_value("counts") |> payload_map()
    placements = snapshot |> map_value("placement_ids") |> payload_map()

    %{
      present?: snapshot != %{},
      capture_schema: value_text(map_value(payload, "schema")),
      snapshot_schema:
        value_text(map_value(payload, "snapshot_schema") || map_value(snapshot, "schema")),
      snapshot_id: value_text(snapshot_id_from_payload(payload)),
      state: value_text(map_value(payload, "health_state") || map_value(snapshot, "state")),
      severity:
        value_text(map_value(payload, "health_severity") || map_value(snapshot, "severity")),
      source: value_text(map_value(payload, "source")),
      captured_reason: value_text(map_value(payload, "captured_reason")),
      counts: count_rows(snapshot, counts),
      placements: placement_rows(placements),
      snapshot_json: Jason.encode!(snapshot)
    }
  end

  def build(%LifecycleEvent{}), do: %{present?: false}
  def build(_event), do: %{present?: false}

  def snapshot_id(%LifecycleEvent{event_type: :health_snapshot_captured, payload: payload}) do
    payload
    |> payload_map()
    |> snapshot_id_from_payload()
  end

  def snapshot_id(_event), do: nil

  defp snapshot_id_from_payload(payload) do
    map_value(payload, "snapshot_id") ||
      payload
      |> map_value("snapshot")
      |> payload_map()
      |> map_value("snapshot_id")
  end

  defp count_rows(snapshot, counts) do
    [
      {"widgets", "Widgets", map_value(counts, "widgets") || map_value(snapshot, "widget_count")},
      {"ready", "Ready", map_value(counts, "ready")},
      {"affected", "Affected", map_value(counts, "affected")},
      {"blocked", "Blocked", map_value(counts, "blocked")},
      {"stale", "Stale", map_value(counts, "stale")},
      {"degraded", "Degraded", map_value(counts, "degraded")}
    ]
    |> Enum.map(fn {key, label, value} ->
      %{key: key, label: label, value: count_text(value)}
    end)
  end

  defp placement_rows(placements) do
    [
      {"affected", "Affected", map_value(placements, "affected")},
      {"blocked", "Blocked", map_value(placements, "blocked")},
      {"stale", "Stale", map_value(placements, "stale")},
      {"degraded", "Degraded", map_value(placements, "degraded")}
    ]
    |> Enum.map(fn {key, label, ids} ->
      ids = value_list(ids)

      %{
        key: key,
        label: label,
        ids: ids,
        ids_attr: Enum.join(ids, ","),
        ids_text: Enum.join(ids, ", ")
      }
    end)
    |> Enum.reject(&(&1.ids == []))
  end

  defp payload_map(value) when is_map(value), do: value
  defp payload_map(_value), do: %{}

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || atom_key_value(map, key)
  end

  defp map_value(_map, _key), do: nil

  defp atom_key_value(map, key) do
    Enum.find_value(map, fn
      {atom_key, value} when is_atom(atom_key) ->
        if Atom.to_string(atom_key) == key, do: value

      _entry ->
        nil
    end)
  end

  defp value_text(nil), do: ""
  defp value_text(value) when is_binary(value), do: value
  defp value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp value_text(value), do: to_string(value)

  defp count_text(nil), do: "0"
  defp count_text(value) when is_integer(value), do: Integer.to_string(value)
  defp count_text(value) when is_binary(value), do: value
  defp count_text(value), do: to_string(value)

  defp value_list(value) when is_list(value), do: Enum.map(value, &value_text/1)

  defp value_list(value) when is_binary(value) and value != "",
    do: String.split(value, ",", trim: true)

  defp value_list(_value), do: []
end
