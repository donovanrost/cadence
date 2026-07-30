defmodule CadenceWeb.API.CommsJSON do
  @moduledoc "Spacecraft and communications response serialization boundary."

  alias Cadence.Contacts.{
    LinkAssignment,
    PathTemplate,
    ProviderProfile,
    TransportProfile
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @spec source_endpoint(SourceEndpoint.t()) :: map()
  def source_endpoint(%SourceEndpoint{} = source_endpoint) do
    %{
      source_endpoint_id: source_endpoint.source_endpoint_id,
      organization_id: source_endpoint.organization_id,
      mission_id: source_endpoint.mission_id,
      spacecraft_id: source_endpoint.spacecraft_id,
      source_ref: source_endpoint.source_ref,
      scid: source_endpoint.scid,
      display_name: source_endpoint.display_name,
      metadata: source_endpoint.metadata
    }
  end

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

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value
  defp json_value(%DateTime{} = datetime), do: iso8601(datetime)

  defp json_value(%{} = map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_value(value)} end)
  end

  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
