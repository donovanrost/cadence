defmodule CadenceWeb.API.ContactJSON do
  @moduledoc "Legacy realized-contact runtime snapshot serialization boundary."

  def realized_contact_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      realized_contact_id: snapshot_value(snapshot, :realized_contact_id),
      mission_id: snapshot_value(snapshot, :mission_id),
      source_endpoint_refs: snapshot_value(snapshot, :source_endpoint_refs, []),
      contact_intents: snapshot_value(snapshot, :contact_intents, []),
      clock_mode: snapshot_atom_string(snapshot, :clock_mode),
      initial_time: snapshot_iso8601(snapshot, :initial_time),
      metadata: snapshot_json(snapshot, :metadata, %{}),
      path_count: snapshot_value(snapshot, :path_count, 0),
      paths: snapshot_list(snapshot, :paths, &path_runtime_snapshot/1),
      downlink_combiner: snapshot_json(snapshot, :downlink_combiner, %{})
    }
  end

  def path_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      realized_contact_id: snapshot_value(snapshot, :realized_contact_id),
      mission_id: snapshot_value(snapshot, :mission_id),
      path_id: snapshot_value(snapshot, :path_id),
      direction: snapshot_atom_string(snapshot, :direction),
      selection_role: snapshot_atom_string(snapshot, :selection_role),
      source_endpoint_ref: snapshot_value(snapshot, :source_endpoint_ref),
      provider_path_ref: snapshot_value(snapshot, :provider_path_ref),
      metadata: snapshot_json(snapshot, :metadata, %{}),
      provider_runtime_count: snapshot_value(snapshot, :provider_runtime_count, 0),
      provider_runtimes:
        snapshot_list(snapshot, :provider_runtimes, &provider_runtime_snapshot/1),
      transport_runtime_count: snapshot_value(snapshot, :transport_runtime_count, 0),
      transport_runtimes:
        snapshot_list(snapshot, :transport_runtimes, &transport_runtime_snapshot/1)
    }
  end

  defp provider_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      provider_binding_id: snapshot_value(snapshot, :provider_binding_id),
      adapter_key: snapshot_atom_string(snapshot, :adapter_key),
      direction: snapshot_atom_string(snapshot, :direction),
      mode: snapshot_atom_string(snapshot, :mode),
      host: snapshot_value(snapshot, :host),
      configured_port: snapshot_value(snapshot, :configured_port),
      port: snapshot_value(snapshot, :port),
      connected?: snapshot_value(snapshot, :connected?, false),
      ingress_protocol_family: snapshot_atom_string(snapshot, :ingress_protocol_family),
      fixed_message_bytes: snapshot_value(snapshot, :fixed_message_bytes),
      ingress_transport_binding_id: snapshot_value(snapshot, :ingress_transport_binding_id),
      source_ref: snapshot_value(snapshot, :source_ref),
      ingress_metadata: snapshot_json(snapshot, :ingress_metadata, %{}),
      uplink_bytes_sent: snapshot_value(snapshot, :uplink_bytes_sent, 0),
      uplink_payload_count: snapshot_value(snapshot, :uplink_payload_count, 0),
      downlink_bytes_received: snapshot_value(snapshot, :downlink_bytes_received, 0),
      downlink_message_count: snapshot_value(snapshot, :downlink_message_count, 0),
      last_delivery_at: snapshot_iso8601(snapshot, :last_delivery_at),
      last_ingress_at: snapshot_iso8601(snapshot, :last_ingress_at),
      last_ingress_error: snapshot_value(snapshot, :last_ingress_error)
    }
  end

  defp transport_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      mission_id: snapshot_value(snapshot, :mission_id),
      realized_contact_id: snapshot_value(snapshot, :realized_contact_id),
      path_id: snapshot_value(snapshot, :path_id),
      activation_id: snapshot_value(snapshot, :activation_id),
      binding_set_id: snapshot_value(snapshot, :binding_set_id),
      binding_set_version: snapshot_value(snapshot, :binding_set_version),
      capability_instance_id: snapshot_value(snapshot, :capability_instance_id),
      family_key: snapshot_atom_string(snapshot, :family_key),
      scope_ref: snapshot_value(snapshot, :scope_ref),
      partition_key: snapshot_value(snapshot, :partition_key),
      clock_mode: snapshot_atom_string(snapshot, :clock_mode),
      current_time: snapshot_iso8601(snapshot, :current_time),
      timer_count: snapshot_value(snapshot, :timer_count, 0),
      timers: snapshot_json(snapshot, :timers, []),
      state: snapshot_json(snapshot, :state, %{}),
      output_count: snapshot_value(snapshot, :output_count, 0),
      outputs: snapshot_json(snapshot, :outputs, [])
    }
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value

  defp snapshot_value(snapshot, key, default \\ nil) when is_map(snapshot) and is_atom(key) do
    Map.get(snapshot, key, Map.get(snapshot, Atom.to_string(key), default))
  end

  defp snapshot_atom_string(snapshot, key, default \\ nil) do
    snapshot |> snapshot_value(key, default) |> maybe_atom_to_string()
  end

  defp snapshot_iso8601(snapshot, key, default \\ nil) do
    snapshot |> snapshot_value(key, default) |> iso8601()
  end

  defp snapshot_json(snapshot, key, default) do
    snapshot |> snapshot_value(key, default) |> json_value()
  end

  defp snapshot_list(snapshot, key, mapper, default \\ []) when is_function(mapper, 1) do
    snapshot
    |> snapshot_value(key, default)
    |> Enum.map(mapper)
  end

  defp json_value(%DateTime{} = datetime), do: iso8601(datetime)

  defp json_value(%{} = map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_value(value)} end)
  end

  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
