defmodule CadenceWeb.API.ContactJSON do
  @moduledoc "Contact lifecycle response serialization boundary."

  alias Cadence.Contacts.{
    ContactAction,
    Path,
    ProviderBinding,
    RealizedContact,
    ScheduledContact,
    TransportBinding
  }

  def scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    %{
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      organization_id: scheduled_contact.organization_id,
      mission_id: scheduled_contact.mission_id,
      source_endpoint_refs: scheduled_contact.source_endpoint_refs,
      contact_intents: Enum.map(scheduled_contact.contact_intents, &Atom.to_string/1),
      link_assignment_refs: json_value(scheduled_contact.link_assignment_refs),
      path_template_ids: scheduled_contact.path_template_ids,
      path_template_refs: json_value(scheduled_contact.path_template_refs),
      paths: Enum.map(scheduled_contact.paths, &contact_path/1),
      starts_at: iso8601(scheduled_contact.starts_at),
      ends_at: iso8601(scheduled_contact.ends_at),
      provider_contact_ref: scheduled_contact.provider_contact_ref,
      current_revision: scheduled_contact.current_revision,
      lifecycle_state: Atom.to_string(scheduled_contact.lifecycle_state),
      realized_contact_id: scheduled_contact.realized_contact_id,
      metadata: scheduled_contact.metadata
    }
  end

  def realized_contact(%RealizedContact{} = realized_contact) do
    %{
      realized_contact_id: realized_contact.realized_contact_id,
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      source_endpoint_refs: realized_contact.source_endpoint_refs,
      contact_intents: Enum.map(realized_contact.contact_intents, &Atom.to_string/1),
      paths: Enum.map(realized_contact.paths, &contact_path/1),
      clock_mode: Atom.to_string(realized_contact.clock_mode),
      initial_time: iso8601(realized_contact.initial_time),
      lifecycle_state: Atom.to_string(realized_contact.lifecycle_state),
      realized_at: iso8601(realized_contact.realized_at),
      metadata: realized_contact.metadata
    }
  end

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

  def contact_action(%ContactAction{} = contact_action) do
    %{
      contact_action_id: contact_action.contact_action_id,
      organization_id: contact_action.organization_id,
      mission_id: contact_action.mission_id,
      scheduled_contact_id: contact_action.scheduled_contact_id,
      realized_contact_id: contact_action.realized_contact_id,
      action_kind: Atom.to_string(contact_action.action_kind),
      reason: contact_action.reason,
      actor: contact_action.actor,
      metadata: contact_action.metadata,
      occurred_at: iso8601(contact_action.occurred_at)
    }
  end

  defp contact_path(%Path{} = path) do
    %{
      path_id: path.path_id,
      direction: maybe_atom_to_string(path.direction),
      selection_role: maybe_atom_to_string(path.selection_role),
      source_endpoint_ref: path.source_endpoint_ref,
      provider_path_ref: path.provider_path_ref,
      provider_bindings: Enum.map(path.provider_bindings, &provider_binding/1),
      transport_bindings: Enum.map(path.transport_bindings, &transport_binding/1),
      metadata: path.metadata
    }
  end

  defp provider_binding(%ProviderBinding{} = provider_binding) do
    %{
      provider_binding_id: provider_binding.provider_binding_id,
      adapter_key: maybe_atom_to_string(provider_binding.adapter_key),
      configuration: json_value(provider_binding.configuration),
      metadata: json_value(provider_binding.metadata)
    }
  end

  defp transport_binding(%TransportBinding{} = transport_binding) do
    %{
      transport_binding_id: transport_binding.transport_binding_id,
      family_key: maybe_atom_to_string(transport_binding.family_key),
      target_scope: maybe_atom_to_string(transport_binding.target_scope),
      configuration: transport_binding.configuration,
      metadata: transport_binding.metadata
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
