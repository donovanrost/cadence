defmodule CadenceWeb.API.CommsParams do
  @moduledoc "Spacecraft and communications configuration request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.Contacts.{
    KnownAtom,
    LinkAssignment,
    PathTemplate,
    ProviderProfile,
    TransportProfile
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @spec source_endpoint(binary(), binary(), map()) :: {:ok, SourceEndpoint.t()} | {:error, term()}
  def source_endpoint(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    source_endpoint(organization_id, mission_id, nil, params)
  end

  @spec source_endpoint(binary(), binary(), binary() | nil, map()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def source_endpoint(organization_id, mission_id, scoped_spacecraft_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, scid} <- optional_integer(params, "scid"),
         {:ok, spacecraft_id} <- resolve_spacecraft_id(params, scoped_spacecraft_id) do
      {:ok,
       SourceEndpoint.new(%{
         source_endpoint_id: string_value(params, "source_endpoint_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         spacecraft_id: spacecraft_id,
         source_ref: string_value(params, "source_ref"),
         scid: scid,
         display_name: string_value(params, "display_name"),
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec spacecraft(binary(), binary(), map()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def spacecraft(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, display_name} <- required_string(params, "display_name"),
         {:ok, scid} <- non_neg_integer(params, "scid", nil) do
      {:ok,
       Spacecraft.new(%{
         spacecraft_id: string_value(params, "spacecraft_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         display_name: display_name,
         scid: scid,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec provider_profile(binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def provider_profile(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, adapter_key} <- provider_adapter_key(params),
         {:ok, configuration} <- optional_map(params, "configuration", %{}) do
      {:ok,
       ProviderProfile.new(%{
         provider_profile_id: string_value(params, "provider_profile_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         adapter_key: adapter_key,
         configuration: configuration,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec provider_profile_patch(map()) :: {:ok, map()} | {:error, term()}
  def provider_profile_patch(params) when is_map(params) do
    with {:ok, adapter_key} <- provider_adapter_key(params),
         {:ok, configuration} <- optional_patch_map(params, "configuration"),
         {:ok, metadata} <- optional_patch_map(params, "metadata") do
      {:ok,
       %{}
       |> maybe_put_attr(:adapter_key, adapter_key)
       |> maybe_put_attr(:configuration, configuration)
       |> maybe_put_attr(:metadata, metadata)}
    end
  end

  @spec transport_profile(binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def transport_profile(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, family_key} <- transport_family_key(params),
         {:ok, target_scope} <- transport_target_scope(params),
         {:ok, configuration} <- optional_map(params, "configuration", %{}) do
      {:ok,
       TransportProfile.new(%{
         transport_profile_id: string_value(params, "transport_profile_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         family_key: family_key,
         target_scope: target_scope,
         configuration: configuration,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec transport_profile_patch(map()) :: {:ok, map()} | {:error, term()}
  def transport_profile_patch(params) when is_map(params) do
    with {:ok, family_key} <- optional_transport_family_key(params, "family_key"),
         {:ok, target_scope} <- optional_transport_target_scope(params, "target_scope"),
         {:ok, configuration} <- optional_patch_map(params, "configuration"),
         {:ok, metadata} <- optional_patch_map(params, "metadata") do
      {:ok,
       %{}
       |> maybe_put_attr(:family_key, family_key)
       |> maybe_put_attr(:target_scope, target_scope)
       |> maybe_put_attr(:configuration, configuration)
       |> maybe_put_attr(:metadata, metadata)}
    end
  end

  @spec path_template(binary(), binary(), map()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def path_template(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, direction} <- direction(params),
         {:ok, selection_role} <- selection_role(params),
         {:ok, provider_profile_ids} <- optional_string_list(params, "provider_profile_ids"),
         {:ok, provider_profile_refs} <-
           optional_versioned_ref_list(params, "provider_profile_refs", "provider_profile_id"),
         {:ok, transport_profile_ids} <- optional_string_list(params, "transport_profile_ids"),
         {:ok, transport_profile_refs} <-
           optional_versioned_ref_list(params, "transport_profile_refs", "transport_profile_id") do
      {:ok,
       PathTemplate.new(%{
         path_template_id: string_value(params, "path_template_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         path_id: string_value(params, "path_id"),
         direction: direction,
         selection_role: selection_role,
         source_endpoint_ref: nil,
         provider_path_ref: string_value(params, "provider_path_ref"),
         provider_profile_ids: provider_profile_ids,
         provider_profile_refs: provider_profile_refs,
         transport_profile_ids: transport_profile_ids,
         transport_profile_refs: transport_profile_refs,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec path_template_patch(map()) :: {:ok, map()} | {:error, term()}
  def path_template_patch(params) when is_map(params) do
    with {:ok, direction} <- optional_direction(params, "direction"),
         {:ok, selection_role} <- optional_selection_role(params, "selection_role"),
         {:ok, provider_path_ref} <- optional_patch_nullable_string(params, "provider_path_ref"),
         {:ok, provider_profile_ids} <- optional_patch_string_list(params, "provider_profile_ids"),
         {:ok, provider_profile_refs} <-
           optional_patch_versioned_ref_list(
             params,
             "provider_profile_refs",
             "provider_profile_id"
           ),
         {:ok, transport_profile_ids} <-
           optional_patch_string_list(params, "transport_profile_ids"),
         {:ok, transport_profile_refs} <-
           optional_patch_versioned_ref_list(
             params,
             "transport_profile_refs",
             "transport_profile_id"
           ),
         {:ok, metadata} <- optional_patch_map(params, "metadata") do
      {:ok,
       %{}
       |> maybe_put_attr(:path_id, string_value(params, "path_id"))
       |> maybe_put_attr(:direction, direction)
       |> maybe_put_attr(:selection_role, selection_role)
       |> maybe_put_attr(:provider_path_ref, provider_path_ref)
       |> maybe_put_attr(:provider_profile_ids, provider_profile_ids)
       |> maybe_put_attr(:provider_profile_refs, provider_profile_refs)
       |> maybe_put_attr(:transport_profile_ids, transport_profile_ids)
       |> maybe_put_attr(:transport_profile_refs, transport_profile_refs)
       |> maybe_put_attr(:metadata, metadata)}
    end
  end

  @spec link_assignment(binary(), binary(), map()) :: {:ok, LinkAssignment.t()} | {:error, term()}
  def link_assignment(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, spacecraft_id} <- required_string(params, "spacecraft_id"),
         {:ok, source_endpoint_ref} <- required_string(params, "source_endpoint_ref"),
         {:ok, path_template_id} <- required_string(params, "path_template_id"),
         {:ok, path_template_version} <- positive_integer(params, "path_template_version", 1),
         {:ok, direction} <- direction(params),
         {:ok, selection_role} <- selection_role(params),
         {:ok, provider_profile_refs} <-
           optional_versioned_ref_list(params, "provider_profile_refs", "provider_profile_id"),
         {:ok, transport_profile_refs} <-
           optional_versioned_ref_list(params, "transport_profile_refs", "transport_profile_id") do
      {:ok,
       LinkAssignment.new(%{
         link_assignment_id: string_value(params, "link_assignment_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         spacecraft_id: spacecraft_id,
         source_endpoint_ref: source_endpoint_ref,
         path_template_id: path_template_id,
         path_template_version: path_template_version,
         direction: direction,
         selection_role: selection_role,
         provider_path_ref: string_value(params, "provider_path_ref"),
         provider_profile_refs: provider_profile_refs,
         transport_profile_refs: transport_profile_refs,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec link_assignment_delete(map()) :: {:ok, map()} | {:error, term()}
  def link_assignment_delete(params) when is_map(params) do
    optional_map(params, "metadata", %{})
  end

  @spec link_template_application(map()) :: {:ok, map()} | {:error, term()}
  def link_template_application(params) when is_map(params) do
    with {:ok, target_mode} <- link_template_application_target_mode(params),
         {:ok, spacecraft_ids} <- optional_string_list(params, "spacecraft_ids"),
         {:ok, path_template_version} <-
           optional_positive_integer(params, "path_template_version") do
      case {target_mode, spacecraft_ids} do
        {"selected", []} ->
          {:error, {:invalid_param, "spacecraft_ids", :required}}

        _other ->
          {:ok,
           %{
             "target_mode" => target_mode,
             "spacecraft_ids" => spacecraft_ids,
             "spacecraft_query" => string_value(params, "spacecraft_query"),
             "path_template_version" => path_template_version,
             "provider_path_ref_pattern" =>
               string_value(params, "provider_path_ref_pattern") || "{spacecraft_id}-{direction}",
             "display_name_pattern" =>
               string_value(params, "display_name_pattern") || "{spacecraft_name} {direction}"
           }}
      end
    end
  end

  @spec resource_version(map(), binary()) :: {:ok, pos_integer()} | {:error, term()}
  def resource_version(params, key \\ "version") when is_map(params) and is_binary(key) do
    positive_integer(params, key, nil)
  end

  defp provider_adapter_key(params) do
    case Map.get(params, "adapter_key") do
      nil ->
        {:ok, nil}

      value ->
        try do
          {:ok, KnownAtom.provider_adapter_key!(value)}
        rescue
          ArgumentError -> {:error, {:invalid_param, "adapter_key", :unknown_atom}}
        end
    end
  end
end
