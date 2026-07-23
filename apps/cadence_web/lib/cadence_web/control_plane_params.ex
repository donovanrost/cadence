defmodule CadenceWeb.ControlPlaneParams do
  @moduledoc false

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Catalog.Artifact

  alias CadenceWeb.ControlPlaneParams.{Commanding, Parser}

  import Parser

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance,
    Selector,
    SelectorMatch,
    SelectorScope
  }

  alias Cadence.Contacts.{
    KnownAtom,
    LinkAssignment,
    Path,
    PathTemplate,
    ProviderBinding,
    ProviderProfile,
    ScheduledContact,
    TransportBinding,
    TransportProfile
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @contact_intent_values [
    :telemetry_downlink,
    :command_window,
    :tracking,
    :health_check,
    :maintenance
  ]

  @spec bootstrap_admin_session(map()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def bootstrap_admin_session(params) when is_map(params) do
    with {:ok, email} <- required_string(params, "email"),
         {:ok, password} <- required_string(params, "password") do
      {:ok, {email, password}}
    end
  end

  @spec durable_session(map()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def durable_session(params) when is_map(params) do
    with {:ok, email} <- required_string(params, "email"),
         {:ok, password} <- required_string(params, "password") do
      {:ok, {email, password}}
    end
  end

  @spec organization_invitation_acceptance(map()) ::
          {:ok, %{display_name: binary(), password: binary()}} | {:error, term()}
  def organization_invitation_acceptance(params) when is_map(params) do
    with {:ok, display_name} <- required_string(params, "display_name"),
         {:ok, password} <- required_string(params, "password"),
         {:ok, password_confirmation} <- required_string(params, "password_confirmation"),
         :ok <- validate_password_confirmation(password, password_confirmation) do
      {:ok, %{display_name: display_name, password: password}}
    end
  end

  @spec organization(map()) :: {:ok, Organization.t()} | {:error, term()}
  def organization(params) when is_map(params) do
    with {:ok, slug} <- required_string(params, "slug"),
         {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Organization.new(%{
         organization_id: string_value(params, "organization_id"),
         slug: slug,
         display_name: display_name,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec mission(binary(), map()) :: {:ok, Mission.t()} | {:error, term()}
  def mission(organization_id, params) when is_binary(organization_id) and is_map(params) do
    with {:ok, slug} <- required_string(params, "slug"),
         {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Mission.new(%{
         mission_id: string_value(params, "mission_id"),
         organization_id: organization_id,
         slug: slug,
         display_name: display_name,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec service_identity(binary(), map()) :: {:ok, ServiceIdentity.t()} | {:error, term()}
  def service_identity(organization_id, params)
      when is_binary(organization_id) and is_map(params) do
    with {:ok, display_name} <- required_string(params, "display_name"),
         {:ok, capabilities} <- capabilities(params, []),
         {:ok, lifecycle_state} <- service_identity_lifecycle_state(params) do
      {:ok,
       ServiceIdentity.new(%{
         service_identity_id: string_value(params, "service_identity_id"),
         organization_id: organization_id,
         mission_id: string_value(params, "mission_id"),
         display_name: display_name,
         capabilities: capabilities,
         lifecycle_state: lifecycle_state,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec bootstrap_service_identity(binary(), map()) ::
          {:ok, ServiceIdentity.t()} | {:error, term()}
  def bootstrap_service_identity(organization_id, bootstrap_params)
      when is_binary(organization_id) and is_map(bootstrap_params) do
    service_identity_params = Map.get(bootstrap_params, "service_identity", %{})

    with {:ok, display_name} <- required_string(service_identity_params, "display_name"),
         {:ok, capabilities} <- capabilities(service_identity_params, [:organization_admin]),
         {:ok, lifecycle_state} <- service_identity_lifecycle_state(service_identity_params) do
      {:ok,
       ServiceIdentity.new(%{
         service_identity_id: string_value(service_identity_params, "service_identity_id"),
         organization_id: organization_id,
         display_name: display_name,
         capabilities: capabilities,
         lifecycle_state: lifecycle_state,
         metadata: map_value(service_identity_params, "metadata")
       })}
    end
  end

  @spec bootstrap_mission(binary(), map()) :: {:ok, Mission.t() | nil} | {:error, term()}
  def bootstrap_mission(organization_id, bootstrap_params)
      when is_binary(organization_id) and is_map(bootstrap_params) do
    case Map.get(bootstrap_params, "mission") do
      nil -> {:ok, nil}
      mission_params when is_map(mission_params) -> mission(organization_id, mission_params)
      _other -> {:error, {:invalid_param, "mission", :map}}
    end
  end

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

  @spec packet_definition(binary(), binary(), map()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def packet_definition(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, packet_name} <- required_string(params, "packet_name"),
         {:ok, apid} <- required_integer(params, "apid"),
         {:ok, version} <- positive_integer(params, "version", 1),
         {:ok, fields} <- field_definitions(params) do
      {:ok,
       PacketDefinition.new(%{
         packet_definition_id: string_value(params, "packet_definition_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         packet_name: packet_name,
         apid: apid,
         version: version,
         fields: fields
       })}
    end
  end

  @spec catalog_importer_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_importer_filters(params) when is_map(params) do
    with {:ok, catalog_family} <- optional_catalog_family(params, "catalog_family") do
      {:ok, [] |> maybe_put_opt(:catalog_family, catalog_family)}
    end
  end

  @spec catalog_artifact(binary(), binary(), map(), keyword()) ::
          {:ok, Artifact.t()} | {:error, term()}
  def catalog_artifact(organization_id, mission_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) and
             is_list(opts) do
    with {:ok, artifact_name} <- required_string(params, "artifact_name"),
         {:ok, catalog_family} <- required_catalog_family(params, "catalog_family"),
         {:ok, format_key} <- required_string(params, "format_key"),
         {:ok, source_artifact} <- required_json_term(params, "source_artifact") do
      {:ok,
       Artifact.new(%{
         artifact_id: string_value(params, "artifact_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         catalog_database_id: string_value(params, "catalog_database_id"),
         catalog_family: catalog_family,
         artifact_name: artifact_name,
         format_key: format_key,
         format_version: string_value(params, "format_version"),
         media_type: string_value(params, "media_type"),
         source_artifact: source_artifact,
         uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec catalog_artifact_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_artifact_filters(params) when is_map(params) do
    with {:ok, catalog_family} <- optional_catalog_family(params, "catalog_family") do
      {:ok, [] |> maybe_put_opt(:catalog_family, catalog_family)}
    end
  end

  @spec catalog_import_run_request(map(), keyword()) ::
          {:ok, {binary(), binary(), keyword()}} | {:error, term()}
  def catalog_import_run_request(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, artifact_id} <- required_string(params, "artifact_id"),
         {:ok, importer_key} <- required_string(params, "importer_key") do
      {:ok,
       {artifact_id, importer_key,
        []
        |> Keyword.put(:requested_by, Keyword.get(opts, :requested_by, %{}))
        |> maybe_put_opt(:catalog_database_id, string_value(params, "catalog_database_id"))
        |> Keyword.put(:metadata, map_value(params, "metadata"))}}
    end
  end

  @spec catalog_import_run_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_import_run_filters(params) when is_map(params) do
    with {:ok, status} <- optional_import_run_status(params, "status") do
      {:ok,
       []
       |> maybe_put_opt(:artifact_id, string_value(params, "artifact_id"))
       |> maybe_put_opt(:status, status)}
    end
  end

  @spec catalog_telemetry_snapshot_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_telemetry_snapshot_filters(params) when is_map(params) do
    {:ok,
     []
     |> maybe_put_opt(:artifact_id, string_value(params, "artifact_id"))
     |> maybe_put_opt(:import_run_id, string_value(params, "import_run_id"))}
  end

  @spec catalog_command_snapshot_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def catalog_command_snapshot_filters(params) when is_map(params) do
    {:ok,
     []
     |> maybe_put_opt(:artifact_id, string_value(params, "artifact_id"))
     |> maybe_put_opt(:import_run_id, string_value(params, "import_run_id"))}
  end

  @spec binding_set(binary(), binary(), map()) :: {:ok, BindingSet.t()} | {:error, term()}
  def binding_set(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, version} <- positive_integer(params, "version", 1),
         {:ok, capability_instances} <- capability_instances(params),
         {:ok, rules} <- binding_rules(params) do
      {:ok,
       BindingSet.new(%{
         binding_set_id: string_value(params, "binding_set_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         version: version,
         capability_instances: capability_instances,
         rules: rules
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

  @spec scheduled_contact(binary(), binary(), map()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def scheduled_contact(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, source_endpoint_refs} <- optional_string_list(params, "source_endpoint_refs"),
         {:ok, contact_intents} <-
           optional_allowed_atom_list(params, "contact_intents", @contact_intent_values),
         {:ok, link_assignment_refs} <-
           optional_ref_list(params, "link_assignment_refs", "link_assignment_id"),
         {:ok, path_template_ids} <- optional_string_list(params, "path_template_ids"),
         {:ok, path_template_refs} <-
           optional_versioned_ref_list(params, "path_template_refs", "path_template_id"),
         {:ok, starts_at} <- required_datetime(params, "starts_at"),
         {:ok, ends_at} <- optional_datetime(params, "ends_at"),
         {:ok, paths} <- contact_paths(params) do
      {:ok,
       ScheduledContact.new(%{
         scheduled_contact_id: string_value(params, "scheduled_contact_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         source_endpoint_refs: source_endpoint_refs,
         contact_intents: contact_intents,
         link_assignment_refs: link_assignment_refs,
         path_template_ids: path_template_ids,
         path_template_refs: path_template_refs,
         paths: paths,
         starts_at: starts_at,
         ends_at: ends_at,
         provider_contact_ref: string_value(params, "provider_contact_ref"),
         current_revision: 1,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec realization(map()) :: {:ok, keyword()} | {:error, term()}
  def realization(params) when is_map(params) do
    with {:ok, clock_mode} <- clock_mode(params),
         {:ok, initial_time} <- optional_datetime(params, "initial_time"),
         {:ok, realized_at} <- optional_datetime(params, "realized_at"),
         {:ok, transition_time} <- optional_datetime(params, "transition_time") do
      {:ok,
       []
       |> maybe_put_opt(:clock_mode, clock_mode)
       |> maybe_put_opt(:initial_time, initial_time)
       |> maybe_put_opt(:realized_at, realized_at)
       |> maybe_put_opt(:transition_time, transition_time)
       |> maybe_put_opt(:realized_contact_id, string_value(params, "realized_contact_id"))
       |> Keyword.put(:metadata, map_value(params, "metadata"))}
    end
  end

  @spec resource_version(map(), binary()) :: {:ok, pos_integer()} | {:error, term()}
  def resource_version(params, key \\ "version") when is_map(params) and is_binary(key) do
    positive_integer(params, key, nil)
  end

  @spec contact_action(map()) :: {:ok, keyword()} | {:error, term()}
  def contact_action(params) when is_map(params) do
    with {:ok, transition_time} <- optional_datetime(params, "transition_time"),
         {:ok, actor} <- optional_map(params, "actor", %{}) do
      {:ok,
       []
       |> maybe_put_opt(:transition_time, transition_time)
       |> maybe_put_opt(:reason, string_value(params, "reason"))
       |> Keyword.put(:actor, actor)
       |> Keyword.put(:metadata, map_value(params, "metadata"))}
    end
  end

  @spec mission_health_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def mission_health_filters(params) when is_map(params) do
    {:ok,
     []
     |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))}
  end

  @spec mission_event_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def mission_event_filters(params) when is_map(params) do
    with {:ok, limit} <- optional_positive_integer(params, "limit"),
         {:ok, cursor} <- mission_event_cursor(params),
         {:ok, category} <- string_or_string_list(params, "category"),
         {:ok, kind} <- string_or_string_list(params, "kind"),
         {:ok, severity} <- string_or_string_list(params, "severity") do
      {:ok,
       []
       |> maybe_put_opt(:limit, limit)
       |> maybe_put_opt(:cursor, cursor)
       |> maybe_put_opt(:category, category)
       |> maybe_put_opt(:kind, kind)
       |> maybe_put_opt(:severity, severity)
       |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:scheduled_contact_id, string_value(params, "scheduled_contact_id"))
       |> maybe_put_opt(:realized_contact_id, string_value(params, "realized_contact_id"))
       |> maybe_put_opt(:path_id, string_value(params, "path_id"))
       |> maybe_put_opt(:capability_instance_id, string_value(params, "capability_instance_id"))}
    end
  end

  @spec telemetry_latest_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def telemetry_latest_filters(params) when is_map(params) do
    {:ok,
     []
     |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))}
  end

  @spec telemetry_history_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def telemetry_history_filters(params) when is_map(params) do
    with {:ok, limit} <- optional_positive_integer(params, "limit"),
         {:ok, order} <- telemetry_history_order(params),
         {:ok, from_receipt_time} <- optional_datetime(params, "from_receipt_time"),
         {:ok, to_receipt_time} <- optional_datetime(params, "to_receipt_time") do
      {:ok,
       []
       |> maybe_put_opt(:spacecraft_id, string_value(params, "spacecraft_id"))
       |> maybe_put_opt(:limit, limit)
       |> maybe_put_opt(:order, order)
       |> maybe_put_opt(:from_receipt_time, from_receipt_time)
       |> maybe_put_opt(:to_receipt_time, to_receipt_time)}
    end
  end

  @spec dev_space_packet_ingress(binary(), map()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def dev_space_packet_ingress(mission_id, params)
      when is_binary(mission_id) and is_map(params) do
    with {:ok, raw_packet} <- required_packet_binary(params),
         {:ok, source_time} <- optional_datetime(params, "source_time"),
         {:ok, receipt_time} <- optional_datetime(params, "receipt_time"),
         {:ok, direction} <- optional_direction(params, "direction") do
      {:ok,
       RawEvidence.new(
         %{
           mission_id: mission_id,
           protocol_family: :space_packet,
           direction: direction || :downlink,
           raw: raw_packet,
           source_endpoint_ref: string_value(params, "source_endpoint_ref"),
           spacecraft_id: string_value(params, "spacecraft_id"),
           source_ref: string_value(params, "source_ref"),
           metadata: map_value(params, "metadata")
         }
         |> maybe_put_attr(:source_time, source_time)
         |> maybe_put_attr(:receipt_time, receipt_time)
       )}
    end
  end

  @spec dev_tm_frame_ingress(binary(), map()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def dev_tm_frame_ingress(mission_id, params) when is_binary(mission_id) and is_map(params) do
    with {:ok, raw_frame} <- required_frame_binary(params),
         {:ok, source_time} <- optional_datetime(params, "source_time"),
         {:ok, receipt_time} <- optional_datetime(params, "receipt_time"),
         {:ok, direction} <- optional_direction(params, "direction"),
         {:ok, frame_size} <- optional_positive_integer(params, "frame_size"),
         {:ok, secondary_header_length} <- non_neg_integer(params, "secondary_header_length", 0),
         {:ok, ocf_length} <- non_neg_integer(params, "ocf_length", 0) do
      metadata =
        params
        |> map_value("metadata")
        |> Map.put(:frame_size, frame_size || byte_size(raw_frame))
        |> Map.put_new(:secondary_header_length, secondary_header_length)
        |> Map.put_new(:ocf_length, ocf_length)

      {:ok,
       RawEvidence.new(
         %{
           mission_id: mission_id,
           protocol_family: :tm_transfer_frame,
           direction: direction || :downlink,
           raw: raw_frame,
           source_endpoint_ref: string_value(params, "source_endpoint_ref"),
           spacecraft_id: string_value(params, "spacecraft_id"),
           source_ref: string_value(params, "source_ref"),
           metadata: metadata
         }
         |> maybe_put_attr(:source_time, source_time)
         |> maybe_put_attr(:receipt_time, receipt_time)
       )}
    end
  end

  defdelegate command_stage(organization_id, mission_id, params), to: Commanding
  defdelegate command_stage(organization_id, mission_id, params, opts), to: Commanding
  defdelegate command_stage(existing_command_stage, params), to: Commanding
  defdelegate command_stage_filters(params), to: Commanding

  defdelegate staged_command_item(organization_id, mission_id, command_stage_id, params),
    to: Commanding

  defdelegate staged_command_item(existing_staged_command_item, params), to: Commanding
  defdelegate staged_command_item_filters(params), to: Commanding
  defdelegate command_stage_submission(params), to: Commanding
  defdelegate command_stage_submission(params, opts), to: Commanding
  defdelegate command_request(organization_id, mission_id, params), to: Commanding
  defdelegate command_request(organization_id, mission_id, params, opts), to: Commanding
  defdelegate command_request_filters(params), to: Commanding
  defdelegate command_approval(command_request_id, params), to: Commanding
  defdelegate command_approval(command_request_id, params, opts), to: Commanding
  defdelegate command_approval_filters(params), to: Commanding
  defdelegate command_queue_entry(params), to: Commanding
  defdelegate command_queue_entry(params, opts), to: Commanding
  defdelegate command_queue_entry_filters(params), to: Commanding
  defdelegate command_release_attempt(params), to: Commanding
  defdelegate command_release_attempt(params, opts), to: Commanding
  defdelegate command_release_attempt_filters(params), to: Commanding
  defdelegate command_verifier_instance_filters(params), to: Commanding

  defp field_definitions(params) do
    params
    |> list_value("fields")
    |> Enum.reduce_while({:ok, []}, fn field_params, {:ok, acc} ->
      case field_definition(field_params) do
        {:ok, %FieldDefinition{} = field_definition} -> {:cont, {:ok, acc ++ [field_definition]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp field_definition(params) when is_map(params) do
    with {:ok, name} <- required_string(params, "name"),
         {:ok, size_bits} <- positive_integer(params, "size_bits", nil),
         {:ok, offset_bits} <- non_neg_integer(params, "offset_bits", 0),
         {:ok, data_type} <- existing_atom(params, "data_type", :uint) do
      {:ok,
       FieldDefinition.new(%{
         field_id: string_value(params, "field_id"),
         name: name,
         offset_bits: offset_bits,
         size_bits: size_bits,
         data_type: data_type,
         engineering_unit: string_value(params, "engineering_unit")
       })}
    end
  end

  defp contact_paths(params) do
    params
    |> list_value("paths")
    |> Enum.reduce_while({:ok, []}, fn path_params, {:ok, acc} ->
      case contact_path(path_params) do
        {:ok, %Path{} = path} -> {:cont, {:ok, acc ++ [path]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp contact_path(params) when is_map(params) do
    with {:ok, direction} <- direction(params),
         {:ok, selection_role} <- selection_role(params),
         {:ok, provider_bindings} <- provider_bindings(params),
         {:ok, transport_bindings} <- transport_bindings(params) do
      {:ok,
       Path.new(%{
         path_id: string_value(params, "path_id"),
         direction: direction,
         selection_role: selection_role,
         source_endpoint_ref: string_value(params, "source_endpoint_ref"),
         provider_path_ref: string_value(params, "provider_path_ref"),
         provider_bindings: provider_bindings,
         transport_bindings: transport_bindings,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  defp provider_bindings(params) do
    params
    |> list_value("provider_bindings")
    |> Enum.reduce_while({:ok, []}, fn binding_params, {:ok, acc} ->
      case provider_binding(binding_params) do
        {:ok, %ProviderBinding{} = provider_binding} ->
          {:cont, {:ok, acc ++ [provider_binding]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp provider_binding(params) when is_map(params) do
    with {:ok, adapter_key} <- provider_adapter_key(params),
         {:ok, configuration} <- optional_map(params, "configuration", %{}) do
      {:ok,
       ProviderBinding.new(%{
         provider_binding_id: string_value(params, "provider_binding_id"),
         adapter_key: adapter_key,
         configuration: configuration,
         metadata: map_value(params, "metadata")
       })}
    end
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

  defp transport_bindings(params) do
    params
    |> list_value("transport_bindings")
    |> Enum.reduce_while({:ok, []}, fn binding_params, {:ok, acc} ->
      case transport_binding(binding_params) do
        {:ok, %TransportBinding{} = transport_binding} ->
          {:cont, {:ok, acc ++ [transport_binding]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp transport_binding(params) when is_map(params) do
    with {:ok, family_key} <- transport_family_key(params),
         {:ok, target_scope} <- transport_target_scope(params),
         {:ok, configuration} <- optional_map(params, "configuration", %{}) do
      {:ok,
       TransportBinding.new(%{
         transport_binding_id: string_value(params, "transport_binding_id"),
         family_key: family_key,
         target_scope: target_scope,
         configuration: configuration,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  defp capability_instances(params) do
    params
    |> list_value("capability_instances")
    |> Enum.reduce_while({:ok, []}, fn capability_instance_params, {:ok, acc} ->
      case capability_instance(capability_instance_params) do
        {:ok, %CapabilityInstance{} = capability_instance} ->
          {:cont, {:ok, acc ++ [capability_instance]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp capability_instance(params) when is_map(params) do
    with {:ok, family_key} <- existing_atom(params, "family_key", nil),
         {:ok, target_scope} <- existing_atom(params, "target_scope", :mission),
         {:ok, lifecycle_state} <- existing_atom(params, "lifecycle_state", :active),
         {:ok, capability_config} <- capability_config(params),
         {:ok, runtime_configuration} <- optional_map(params, "runtime_configuration") do
      {:ok,
       CapabilityInstance.new(%{
         capability_instance_id: string_value(params, "capability_instance_id"),
         family_key: family_key,
         target_scope: target_scope,
         source_endpoint_ref: string_value(params, "source_endpoint_ref"),
         lifecycle_state: lifecycle_state,
         capability_config: capability_config,
         runtime_configuration: runtime_configuration
       })}
    end
  end

  defp binding_rules(params) do
    params
    |> list_value("rules")
    |> Enum.reduce_while({:ok, []}, fn binding_rule_params, {:ok, acc} ->
      case binding_rule(binding_rule_params) do
        {:ok, %BindingRule{} = binding_rule} -> {:cont, {:ok, acc ++ [binding_rule]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp binding_rule(params) when is_map(params) do
    with {:ok, handler_key} <- existing_atom(params, "handler_key", nil),
         {:ok, priority} <- non_neg_integer(params, "priority", 100),
         {:ok, fanout_mode} <- existing_atom(params, "fanout_mode", :exclusive),
         {:ok, selector} <- selector(params),
         {:ok, capability_config} <- capability_config(params),
         {:ok, handler_configuration} <- optional_map(params, "handler_configuration") do
      {:ok,
       BindingRule.new(%{
         binding_rule_id: string_value(params, "binding_rule_id"),
         capability_instance_id: string_value(params, "capability_instance_id"),
         handler_key: handler_key,
         selector: selector,
         capability_config: capability_config,
         priority: priority,
         fanout_mode: fanout_mode,
         handler_configuration: handler_configuration
       })}
    end
  end

  defp selector(params) do
    with {:ok, scope} <- selector_scope(map_value(params, "selector") |> Map.get("scope", %{})),
         {:ok, match} <- selector_match(map_value(params, "selector") |> Map.get("match", %{})) do
      {:ok, %Selector{scope: scope, match: match}}
    end
  end

  defp selector_scope(params) when is_map(params) do
    with {:ok, target_scope} <- existing_atom(params, "target_scope", nil) do
      {:ok,
       SelectorScope.new(%{
         target_scope: target_scope,
         source_endpoint_ref: string_value(params, "source_endpoint_ref")
       })}
    end
  end

  defp selector_match(params) when is_map(params) do
    with {:ok, packet_kind} <- existing_atom(params, "packet_kind", nil),
         {:ok, apid} <- optional_integer(params, "apid") do
      {:ok, %SelectorMatch{packet_kind: packet_kind, apid: apid}}
    end
  end

  defp capability_config(params) do
    config_params = map_value(params, "capability_config")

    with {:ok, config_type} <- capability_config_type(config_params),
         {:ok, document} <- optional_map(config_params, "document", %{}) do
      {:ok,
       CapabilityConfig.new(%{
         config_type: config_type,
         document: document
       })}
    end
  end

  defp capability_config_type(params) when map_size(params) == 0, do: {:ok, :none}
  defp capability_config_type(params), do: existing_atom(params, "config_type", :none)
end
