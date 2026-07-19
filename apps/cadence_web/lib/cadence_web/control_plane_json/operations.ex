defmodule CadenceWeb.ControlPlaneJSON.Operations do
  @moduledoc false

  alias Cadence.Contacts.{
    ContactAction,
    LinkAssignment,
    Path,
    PathTemplate,
    ProviderBinding,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    TransportBinding,
    TransportProfile
  }

  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.MissionEvents.Entry, as: MissionEventEntry
  alias Cadence.Reads.MissionHealth
  alias Cadence.Spacecraft

  def spacecraft(%Spacecraft{} = spacecraft) do
    %{
      spacecraft_id: spacecraft.spacecraft_id,
      organization_id: spacecraft.organization_id,
      mission_id: spacecraft.mission_id,
      display_name: spacecraft.display_name,
      scid: spacecraft.scid,
      metadata: spacecraft.metadata
    }
  end

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

  def provider_profile(%ProviderProfile{} = provider_profile) do
    %{
      provider_profile_id: provider_profile.provider_profile_id,
      organization_id: provider_profile.organization_id,
      mission_id: provider_profile.mission_id,
      version: provider_profile.version,
      lifecycle_state: maybe_atom_to_string(provider_profile.lifecycle_state),
      adapter_key: maybe_atom_to_string(provider_profile.adapter_key),
      configuration: json_value(provider_profile.configuration),
      metadata: json_value(provider_profile.metadata)
    }
  end

  def transport_profile(%TransportProfile{} = transport_profile) do
    %{
      transport_profile_id: transport_profile.transport_profile_id,
      organization_id: transport_profile.organization_id,
      mission_id: transport_profile.mission_id,
      version: transport_profile.version,
      lifecycle_state: maybe_atom_to_string(transport_profile.lifecycle_state),
      family_key: maybe_atom_to_string(transport_profile.family_key),
      target_scope: maybe_atom_to_string(transport_profile.target_scope),
      configuration: json_value(transport_profile.configuration),
      metadata: json_value(transport_profile.metadata)
    }
  end

  def path_template(%PathTemplate{} = path_template) do
    %{
      path_template_id: path_template.path_template_id,
      organization_id: path_template.organization_id,
      mission_id: path_template.mission_id,
      version: path_template.version,
      lifecycle_state: maybe_atom_to_string(path_template.lifecycle_state),
      path_id: path_template.path_id,
      direction: maybe_atom_to_string(path_template.direction),
      selection_role: maybe_atom_to_string(path_template.selection_role),
      source_endpoint_ref: path_template.source_endpoint_ref,
      provider_path_ref: path_template.provider_path_ref,
      provider_profile_ids: path_template.provider_profile_ids,
      provider_profile_refs: json_value(path_template.provider_profile_refs),
      transport_profile_ids: path_template.transport_profile_ids,
      transport_profile_refs: json_value(path_template.transport_profile_refs),
      metadata: json_value(path_template.metadata)
    }
  end

  def link_assignment(%LinkAssignment{} = link_assignment) do
    %{
      link_assignment_id: link_assignment.link_assignment_id,
      organization_id: link_assignment.organization_id,
      mission_id: link_assignment.mission_id,
      lifecycle_state: maybe_atom_to_string(link_assignment.lifecycle_state),
      spacecraft_id: link_assignment.spacecraft_id,
      source_endpoint_ref: link_assignment.source_endpoint_ref,
      path_template_id: link_assignment.path_template_id,
      path_template_version: link_assignment.path_template_version,
      direction: maybe_atom_to_string(link_assignment.direction),
      selection_role: maybe_atom_to_string(link_assignment.selection_role),
      provider_path_ref: link_assignment.provider_path_ref,
      provider_profile_refs: json_value(link_assignment.provider_profile_refs),
      transport_profile_refs: json_value(link_assignment.transport_profile_refs),
      metadata: json_value(link_assignment.metadata)
    }
  end

  def link_template_application_result(result) when is_map(result) do
    %{
      applied_count: result.applied_count,
      skipped_count: result.skipped_count,
      failed_count: result.failed_count,
      rows: Enum.map(result.rows, &link_template_application_row/1)
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

  def mission_event(organization_id, %MissionEventEntry{} = mission_event) do
    %{
      mission_event_id: mission_event.mission_event_id,
      organization_id: organization_id,
      mission_id: mission_event.mission_id,
      occurred_at: iso8601(mission_event.occurred_at),
      category: maybe_atom_to_string(mission_event.category),
      kind: maybe_atom_to_string(mission_event.kind),
      severity: maybe_atom_to_string(mission_event.severity),
      status: mission_event.status,
      title: mission_event.title,
      summary: mission_event.summary,
      source_record_kind: maybe_atom_to_string(mission_event.source_record_kind),
      source_record_id: mission_event.source_record_id,
      subject_kind: maybe_atom_to_string(mission_event.subject_kind),
      subject_id: mission_event.subject_id,
      correlation_key: mission_event.correlation_key,
      spacecraft_id: mission_event.spacecraft_id,
      source_endpoint_ref: mission_event.source_endpoint_ref,
      scheduled_contact_id: mission_event.scheduled_contact_id,
      realized_contact_id: mission_event.realized_contact_id,
      path_id: mission_event.path_id,
      capability_instance_id: mission_event.capability_instance_id,
      activation_id: mission_event.activation_id,
      actor: mission_event.actor,
      metadata: mission_event.metadata
    }
  end

  def mission_health(organization_id, %MissionHealth{} = mission_health) do
    %{
      organization_id: organization_id,
      mission_id: mission_health.mission_id,
      total_points: mission_health.total_points,
      violating_points: mission_health.violating_points,
      normalized_state_counts: mission_health.normalized_state_counts,
      worst_normalized_state: maybe_atom_to_string(mission_health.worst_normalized_state),
      updated_at: iso8601(mission_health.updated_at),
      point_buckets: point_buckets(mission_health.point_buckets),
      scope_summaries: Enum.map(mission_health.scope_summaries, &scope_summary/1)
    }
  end

  defp link_template_application_row(row) when is_map(row) do
    %{
      id: row.id,
      spacecraft: spacecraft(row.spacecraft),
      kind: maybe_atom_to_string(row.kind),
      status: maybe_atom_to_string(row.status),
      label: row.label,
      detail: row.detail
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

  defp scope_summary(scope_summary) do
    %{
      scope_id: scope_summary.scope_id,
      scope_kind: maybe_atom_to_string(scope_summary.scope_kind),
      scope_label: scope_summary.scope_label,
      spacecraft_id: scope_summary.spacecraft_id,
      total_points: scope_summary.total_points,
      violating_points: scope_summary.violating_points,
      normalized_state_counts: scope_summary.normalized_state_counts,
      worst_normalized_state: maybe_atom_to_string(scope_summary.worst_normalized_state),
      updated_at: iso8601(scope_summary.updated_at),
      point_buckets: point_buckets(scope_summary.point_buckets)
    }
  end

  defp point_buckets(point_buckets) when is_map(point_buckets) do
    %{
      red: Enum.map(Map.get(point_buckets, :red, []), &limit_event/1),
      yellow: Enum.map(Map.get(point_buckets, :yellow, []), &limit_event/1),
      green: Enum.map(Map.get(point_buckets, :green, []), &limit_event/1),
      blue: Enum.map(Map.get(point_buckets, :blue, []), &limit_event/1)
    }
  end

  defp limit_event(%LimitEvent{} = limit_event) do
    %{
      limit_event_id: limit_event.limit_event_id,
      mission_id: limit_event.mission_id,
      spacecraft_id: limit_event.spacecraft_id,
      point_id: limit_event.point_id,
      point_name: limit_event.point_name,
      source_sample_type: maybe_atom_to_string(limit_event.source_sample_type),
      sample_id: limit_event.sample_id,
      limit_definition_id: limit_event.limit_definition_id,
      limit_definition_version: limit_event.limit_definition_version,
      limit_set_name: limit_event.limit_set_name,
      evaluated_value: limit_event.evaluated_value,
      limit_state: maybe_atom_to_string(limit_event.limit_state),
      normalized_state: maybe_atom_to_string(limit_event.normalized_state),
      violation: limit_event.violation,
      generation_time: iso8601(limit_event.generation_time),
      receipt_time: iso8601(limit_event.receipt_time),
      provenance: limit_event.provenance
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
