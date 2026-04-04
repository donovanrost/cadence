defmodule CadenceWeb.ControlPlaneParams do
  @moduledoc false

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Catalog.Artifact

  alias Cadence.Commanding.{CommandRequest, CommandStage, StagedCommandItem}

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
  alias Cadence.Spacecraft
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @command_stage_visibility_values [:private, :shared]
  @command_stage_lifecycle_states [:draft, :in_review, :ready_to_submit, :submitted, :canceled]
  @staged_command_item_lifecycle_states [:draft, :submitted, :canceled]
  @command_request_lifecycle_states [
    :draft,
    :validated,
    :approval_pending,
    :approved,
    :rejected,
    :queued,
    :released,
    :canceled
  ]
  @command_approval_decisions [:approved, :rejected]
  @command_queue_entry_lifecycle_states [:pending, :release_pending, :released, :canceled]
  @command_release_attempt_lifecycle_states [
    :release_pending,
    :released,
    :release_failed,
    :canceled
  ]
  @command_verifier_instance_lifecycle_states [
    :pending,
    :satisfied,
    :failed,
    :timed_out,
    :canceled
  ]
  @command_verifier_phases [:acceptance, :start, :completion, :custom]
  @service_identity_lifecycle_states [:active, :disabled]
  @direction_values [:uplink, :downlink]
  @selection_role_values [:selected, :candidate, :contributing]
  @transport_target_scope_values [:path, :transport]

  @spec bootstrap_admin_session(map()) :: {:ok, {binary(), binary()}} | {:error, term()}
  def bootstrap_admin_session(params) when is_map(params) do
    with {:ok, email} <- required_string(params, "email"),
         {:ok, password} <- required_string(params, "password") do
      {:ok, {email, password}}
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
    with {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Spacecraft.new(%{
         spacecraft_id: string_value(params, "spacecraft_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         display_name: display_name,
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

  @spec activation(binary(), map()) ::
          {:ok, {binary(), pos_integer(), keyword()}} | {:error, term()}
  def activation(mission_id, params) when is_binary(mission_id) and is_map(params) do
    with {:ok, binding_set_id} <- required_string(params, "binding_set_id"),
         {:ok, version} <- positive_integer(params, "version", nil) do
      {:ok,
       {binding_set_id, version,
        [
          metadata: map_value(params, "metadata")
        ]}}
    end
  end

  @spec provider_profile(binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def provider_profile(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, adapter_key} <- existing_atom(params, "adapter_key", nil),
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
    with {:ok, adapter_key} <- maybe_existing_atom(params, "adapter_key"),
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
         source_endpoint_ref: string_value(params, "source_endpoint_ref"),
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
         {:ok, source_endpoint_ref} <-
           optional_patch_nullable_string(params, "source_endpoint_ref"),
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
       |> maybe_put_attr(:source_endpoint_ref, source_endpoint_ref)
       |> maybe_put_attr(:provider_path_ref, provider_path_ref)
       |> maybe_put_attr(:provider_profile_ids, provider_profile_ids)
       |> maybe_put_attr(:provider_profile_refs, provider_profile_refs)
       |> maybe_put_attr(:transport_profile_ids, transport_profile_ids)
       |> maybe_put_attr(:transport_profile_refs, transport_profile_refs)
       |> maybe_put_attr(:metadata, metadata)}
    end
  end

  @spec scheduled_contact(binary(), binary(), map()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def scheduled_contact(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, source_endpoint_refs} <- required_string_list(params, "source_endpoint_refs"),
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
         path_template_ids: path_template_ids,
         path_template_refs: path_template_refs,
         paths: paths,
         starts_at: starts_at,
         ends_at: ends_at,
         provider_contact_ref: string_value(params, "provider_contact_ref"),
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

  @spec command_stage(binary(), binary(), map(), keyword()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def command_stage(organization_id, mission_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) and
             is_list(opts) do
    with {:ok, stage_name} <- required_string(params, "stage_name"),
         {:ok, visibility} <- command_stage_visibility(params, :private),
         {:ok, lifecycle_state} <- command_stage_lifecycle_state(params, :draft),
         {:ok, owner} <- optional_map(params, "owner", Keyword.get(opts, :default_owner, %{})) do
      {:ok,
       CommandStage.new(%{
         command_stage_id: string_value(params, "command_stage_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         stage_name: stage_name,
         description: string_value(params, "description"),
         owner: owner || %{},
         visibility: visibility,
         lifecycle_state: lifecycle_state,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec command_stage(CommandStage.t(), map()) :: {:ok, CommandStage.t()} | {:error, term()}
  def command_stage(%CommandStage{} = existing_command_stage, params) when is_map(params) do
    with {:ok, visibility} <-
           command_stage_visibility(params, existing_command_stage.visibility),
         {:ok, lifecycle_state} <-
           command_stage_lifecycle_state(params, existing_command_stage.lifecycle_state),
         {:ok, owner} <- maybe_map_override(params, "owner", existing_command_stage.owner) do
      {:ok,
       CommandStage.new(%{
         command_stage_id: existing_command_stage.command_stage_id,
         organization_id: existing_command_stage.organization_id,
         mission_id: existing_command_stage.mission_id,
         stage_name:
           maybe_string_override(params, "stage_name", existing_command_stage.stage_name),
         description:
           maybe_nullable_string_override(
             params,
             "description",
             existing_command_stage.description
           ),
         owner: owner,
         visibility: visibility,
         lifecycle_state: lifecycle_state,
         metadata: maybe_map_value(params, "metadata", existing_command_stage.metadata)
       })}
    end
  end

  @spec command_stage_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_stage_filters(params) when is_map(params) do
    with {:ok, visibility} <- optional_command_stage_visibility(params),
         {:ok, lifecycle_state} <- optional_command_stage_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:visibility, visibility)
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec staged_command_item(binary(), binary(), binary(), map()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def staged_command_item(organization_id, mission_id, command_stage_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_stage_id) and is_map(params) do
    with {:ok, scoped_command_stage_id} <-
           resolve_scoped_command_stage_id(params, command_stage_id),
         {:ok, source_endpoint_ref} <- required_string(params, "source_endpoint_ref"),
         {:ok, command_snapshot_id} <- required_string(params, "command_snapshot_id"),
         {:ok, command_id} <- required_string(params, "command_id"),
         {:ok, priority} <- non_neg_integer(params, "priority", 3),
         {:ok, item_order} <- non_neg_integer(params, "item_order", 0),
         {:ok, not_before} <- optional_datetime(params, "not_before"),
         {:ok, expires_at} <- optional_datetime(params, "expires_at") do
      {:ok,
       StagedCommandItem.new(%{
         staged_command_item_id: string_value(params, "staged_command_item_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         command_stage_id: scoped_command_stage_id,
         source_endpoint_ref: source_endpoint_ref,
         command_snapshot_id: command_snapshot_id,
         command_id: command_id,
         argument_values: map_value(params, "argument_values"),
         priority: priority,
         not_before: not_before,
         expires_at: expires_at,
         notes: string_value(params, "notes"),
         item_order: item_order,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec staged_command_item(StagedCommandItem.t(), map()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def staged_command_item(%StagedCommandItem{} = existing_staged_command_item, params)
      when is_map(params) do
    with {:ok, priority} <-
           maybe_non_neg_integer(params, "priority", existing_staged_command_item.priority),
         {:ok, item_order} <-
           maybe_non_neg_integer(params, "item_order", existing_staged_command_item.item_order),
         {:ok, not_before} <-
           maybe_optional_datetime(params, "not_before", existing_staged_command_item.not_before),
         {:ok, expires_at} <-
           maybe_optional_datetime(params, "expires_at", existing_staged_command_item.expires_at) do
      {:ok,
       StagedCommandItem.new(%{
         staged_command_item_id: existing_staged_command_item.staged_command_item_id,
         organization_id: existing_staged_command_item.organization_id,
         mission_id: existing_staged_command_item.mission_id,
         command_stage_id: existing_staged_command_item.command_stage_id,
         source_endpoint_ref:
           maybe_string_override(
             params,
             "source_endpoint_ref",
             existing_staged_command_item.source_endpoint_ref
           ),
         command_snapshot_id:
           maybe_string_override(
             params,
             "command_snapshot_id",
             existing_staged_command_item.command_snapshot_id
           ),
         command_id:
           maybe_string_override(params, "command_id", existing_staged_command_item.command_id),
         argument_values:
           maybe_map_value(
             params,
             "argument_values",
             existing_staged_command_item.argument_values
           ),
         priority: priority,
         not_before: not_before,
         expires_at: expires_at,
         notes:
           maybe_nullable_string_override(params, "notes", existing_staged_command_item.notes),
         item_order: item_order,
         lifecycle_state: existing_staged_command_item.lifecycle_state,
         submitted_command_request_id: existing_staged_command_item.submitted_command_request_id,
         metadata: maybe_map_value(params, "metadata", existing_staged_command_item.metadata)
       })}
    end
  end

  @spec staged_command_item_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def staged_command_item_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_staged_command_item_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_stage_id, string_value(params, "command_stage_id"))
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_stage_submission(map(), keyword()) ::
          {:ok, {[binary()], map()}} | {:error, term()}
  def command_stage_submission(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, staged_command_item_ids} <- required_string_list(params, "staged_command_item_ids"),
         {:ok, requested_by} <-
           optional_map(params, "requested_by", Keyword.get(opts, :default_requested_by, %{})) do
      {:ok, {staged_command_item_ids, requested_by || %{}}}
    end
  end

  @spec command_request(binary(), binary(), map(), keyword()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def command_request(organization_id, mission_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) and
             is_list(opts) do
    with {:ok, source_endpoint_ref} <- required_string(params, "source_endpoint_ref"),
         {:ok, command_snapshot_id} <- required_string(params, "command_snapshot_id"),
         {:ok, command_id} <- required_string(params, "command_id"),
         {:ok, priority} <- non_neg_integer(params, "priority", 3),
         {:ok, not_before} <- optional_datetime(params, "not_before"),
         {:ok, expires_at} <- optional_datetime(params, "expires_at"),
         {:ok, requested_by} <-
           optional_map(params, "requested_by", Keyword.get(opts, :default_requested_by, %{})) do
      {:ok,
       CommandRequest.new(%{
         command_request_id: string_value(params, "command_request_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         source_endpoint_ref: source_endpoint_ref,
         command_snapshot_id: command_snapshot_id,
         command_id: command_id,
         priority: priority,
         not_before: not_before,
         expires_at: expires_at,
         requested_by: requested_by || %{},
         argument_values: map_value(params, "argument_values"),
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec command_request_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_request_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_request_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:command_stage_id, string_value(params, "command_stage_id"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_approval(binary(), map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def command_approval(command_request_id, params, opts \\ [])
      when is_binary(command_request_id) and is_map(params) and is_list(opts) do
    with {:ok, decided_by} <-
           optional_map(params, "decided_by", Keyword.get(opts, :default_decided_by, %{})) do
      {:ok,
       [
         reason: string_value(params, "reason"),
         decided_by: decided_by || %{},
         metadata: map_value(params, "metadata")
       ]}
    end
  end

  @spec command_approval_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_approval_filters(params) when is_map(params) do
    with {:ok, decision} <- optional_command_approval_decision(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_request_id, string_value(params, "command_request_id"))
       |> maybe_put_opt(:decision, decision)}
    end
  end

  @spec command_queue_entry(map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def command_queue_entry(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, enqueued_by} <-
           optional_map(params, "enqueued_by", Keyword.get(opts, :default_enqueued_by, %{})) do
      {:ok,
       [
         enqueued_by: enqueued_by || %{},
         metadata: map_value(params, "metadata")
       ]}
    end
  end

  @spec command_queue_entry_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_queue_entry_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_queue_entry_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:queue_lane_key, string_value(params, "queue_lane_key"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_release_attempt(map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def command_release_attempt(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, realized_contact_id} <- required_string(params, "realized_contact_id"),
         {:ok, released_by} <-
           optional_map(params, "released_by", Keyword.get(opts, :default_released_by, %{})),
         {:ok, attempted_at} <- optional_datetime(params, "attempted_at") do
      {:ok,
       []
       |> Keyword.put(:realized_contact_id, realized_contact_id)
       |> Keyword.put(:released_by, released_by || %{})
       |> maybe_put_opt(:path_id, string_value(params, "path_id"))
       |> maybe_put_opt(:transport_binding_id, string_value(params, "transport_binding_id"))
       |> maybe_put_opt(:attempted_at, attempted_at)
       |> Keyword.put(:metadata, map_value(params, "metadata"))}
    end
  end

  @spec command_release_attempt_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_release_attempt_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_release_attempt_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_request_id, string_value(params, "command_request_id"))
       |> maybe_put_opt(:command_queue_entry_id, string_value(params, "command_queue_entry_id"))
       |> maybe_put_opt(:realized_contact_id, string_value(params, "realized_contact_id"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_verifier_instance_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_verifier_instance_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_verifier_instance_lifecycle_state(params),
         {:ok, phase} <- optional_command_verifier_phase(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_request_id, string_value(params, "command_request_id"))
       |> maybe_put_opt(
         :command_release_attempt_id,
         string_value(params, "command_release_attempt_id")
       )
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:phase, phase)
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

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

  defp command_stage_visibility(params, default) when is_map(params) do
    allowed_atom_param(params, "visibility", default, @command_stage_visibility_values)
  end

  defp optional_command_stage_visibility(params) when is_map(params) do
    optional_allowed_atom_param(params, "visibility", @command_stage_visibility_values)
  end

  defp command_stage_lifecycle_state(params, default) when is_map(params) do
    allowed_atom_param(params, "lifecycle_state", default, @command_stage_lifecycle_states)
  end

  defp optional_command_stage_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @command_stage_lifecycle_states)
  end

  defp optional_staged_command_item_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @staged_command_item_lifecycle_states)
  end

  defp optional_command_request_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @command_request_lifecycle_states)
  end

  defp optional_command_approval_decision(params) when is_map(params) do
    optional_allowed_atom_param(params, "decision", @command_approval_decisions)
  end

  defp optional_command_queue_entry_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @command_queue_entry_lifecycle_states)
  end

  defp optional_command_release_attempt_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(
      params,
      "lifecycle_state",
      @command_release_attempt_lifecycle_states
    )
  end

  defp optional_command_verifier_instance_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(
      params,
      "lifecycle_state",
      @command_verifier_instance_lifecycle_states
    )
  end

  defp optional_command_verifier_phase(params) when is_map(params) do
    optional_allowed_atom_param(params, "phase", @command_verifier_phases)
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
    with {:ok, adapter_key} <- existing_atom(params, "adapter_key", nil),
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

  defp capabilities(params, default) when is_map(params) and is_list(default) do
    case Map.get(params, "capabilities", default) do
      values when is_list(values) ->
        reduce_ok(values, &normalize_capability/1)

      _other ->
        {:error, {:invalid_param, "capabilities", :list}}
    end
  end

  defp service_identity_lifecycle_state(params) when is_map(params) do
    allowed_atom_param(params, "lifecycle_state", :active, @service_identity_lifecycle_states)
  end

  defp required_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:invalid_param, key, :required}}
    end
  end

  defp required_json_term(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> {:ok, value}
    end
  end

  defp string_value(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp required_integer(params, key) do
    case integer_from_value(Map.get(params, key)) do
      {:ok, integer} -> {:ok, integer}
      :error -> {:error, {:invalid_param, key, :integer}}
    end
  end

  defp optional_positive_integer(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> integer_from_value(value) |> ensure_positive_integer(key)
    end
  end

  defp required_datetime(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        datetime_from_value(value) |> wrap_datetime_result(key)

      _missing ->
        {:error, {:invalid_param, key, :required}}
    end
  end

  defp optional_datetime(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> datetime_from_value(value) |> wrap_datetime_result(key)
    end
  end

  defp optional_integer(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> integer_from_value(value) |> wrap_integer_result(key)
    end
  end

  defp positive_integer(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> integer_from_value(value) |> ensure_positive_integer(key)
    end
  end

  defp non_neg_integer(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:ok, default}
      value -> integer_from_value(value) |> ensure_non_neg_integer(key)
    end
  end

  defp wrap_integer_result({:ok, integer}, _key), do: {:ok, integer}
  defp wrap_integer_result(:error, key), do: {:error, {:invalid_param, key, :integer}}

  defp wrap_datetime_result({:ok, datetime}, _key), do: {:ok, datetime}
  defp wrap_datetime_result(:error, key), do: {:error, {:invalid_param, key, :datetime}}

  defp ensure_positive_integer({:ok, integer}, _key) when integer > 0, do: {:ok, integer}

  defp ensure_positive_integer(_result, key),
    do: {:error, {:invalid_param, key, :positive_integer}}

  defp ensure_non_neg_integer({:ok, integer}, _key) when integer >= 0, do: {:ok, integer}
  defp ensure_non_neg_integer(_result, key), do: {:error, {:invalid_param, key, :non_neg_integer}}

  defp integer_from_value(value) when is_integer(value), do: {:ok, value}

  defp integer_from_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp integer_from_value(_value), do: :error

  defp datetime_from_value(%DateTime{} = datetime), do: {:ok, datetime}

  defp datetime_from_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _other -> :error
    end
  end

  defp datetime_from_value(_value), do: :error

  defp existing_atom(params, key, default) do
    case Map.get(params, key, default) do
      nil ->
        {:ok, nil}

      value when is_atom(value) ->
        {:ok, value}

      value when is_binary(value) ->
        try do
          {:ok, String.to_existing_atom(value)}
        rescue
          ArgumentError -> {:error, {:invalid_param, key, :unknown_atom}}
        end

      _other ->
        {:error, {:invalid_param, key, :atom}}
    end
  end

  defp maybe_existing_atom(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      existing_atom(params, key, nil)
    else
      {:ok, nil}
    end
  end

  defp allowed_atom_param(params, key, default, allowed)
       when is_map(params) and is_binary(key) and is_list(allowed) do
    parse_allowed_atom(Map.get(params, key, default), key, allowed)
  end

  defp optional_allowed_atom_param(params, key, allowed)
       when is_map(params) and is_binary(key) and is_list(allowed) do
    parse_allowed_atom(Map.get(params, key), key, allowed)
  end

  defp required_allowed_atom_param(params, key, allowed)
       when is_map(params) and is_binary(key) and is_list(allowed) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> parse_allowed_atom(value, key, allowed)
    end
  end

  defp parse_allowed_atom(nil, _key, _allowed), do: {:ok, nil}

  defp parse_allowed_atom(value, key, allowed) when is_atom(value) do
    if Enum.member?(allowed, value) do
      {:ok, value}
    else
      {:error, {:invalid_param, key, :unknown_atom}}
    end
  end

  defp parse_allowed_atom(value, key, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:invalid_param, key, :unknown_atom}}
      atom -> {:ok, atom}
    end
  end

  defp parse_allowed_atom(_value, key, _allowed),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  defp normalize_capability(value) do
    case value do
      :organization_admin -> {:ok, :organization_admin}
      "organization_admin" -> {:ok, :organization_admin}
      :mission_admin -> {:ok, :mission_admin}
      "mission_admin" -> {:ok, :mission_admin}
      _other -> {:error, {:invalid_param, "capabilities", :unknown_atom}}
    end
  end

  defp required_catalog_family(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> catalog_family_from_value(value, key)
    end
  end

  defp optional_catalog_family(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> catalog_family_from_value(value, key)
    end
  end

  defp catalog_family_from_value(:telemetry, _key), do: {:ok, :telemetry}
  defp catalog_family_from_value("telemetry", _key), do: {:ok, :telemetry}
  defp catalog_family_from_value(:command, _key), do: {:ok, :command}
  defp catalog_family_from_value("command", _key), do: {:ok, :command}
  defp catalog_family_from_value(:combined, _key), do: {:ok, :combined}
  defp catalog_family_from_value("combined", _key), do: {:ok, :combined}

  defp catalog_family_from_value(_other, key),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  defp optional_import_run_status(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> import_run_status_from_value(value, key)
    end
  end

  defp import_run_status_from_value(:running, _key), do: {:ok, :running}
  defp import_run_status_from_value("running", _key), do: {:ok, :running}
  defp import_run_status_from_value(:completed, _key), do: {:ok, :completed}
  defp import_run_status_from_value("completed", _key), do: {:ok, :completed}
  defp import_run_status_from_value(:failed, _key), do: {:ok, :failed}
  defp import_run_status_from_value("failed", _key), do: {:ok, :failed}

  defp import_run_status_from_value(_other, key),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  defp mission_event_cursor(params) when is_map(params) do
    with {:ok, occurred_at} <- optional_datetime(params, "cursor_occurred_at") do
      case {occurred_at, string_value(params, "cursor_mission_event_id")} do
        {nil, nil} ->
          {:ok, nil}

        {nil, _event_id} ->
          {:error, {:invalid_param, "cursor_occurred_at", :required}}

        {%DateTime{} = cursor_time, nil} ->
          {:ok, %{occurred_at: cursor_time}}

        {%DateTime{} = cursor_time, event_id} ->
          {:ok, %{occurred_at: cursor_time, mission_event_id: event_id}}
      end
    end
  end

  defp telemetry_history_order(params) when is_map(params) do
    case Map.get(params, "order") do
      nil -> {:ok, nil}
      :asc -> {:ok, :asc}
      "asc" -> {:ok, :asc}
      :desc -> {:ok, :desc}
      "desc" -> {:ok, :desc}
      _other -> {:error, {:invalid_param, "order", :unknown_atom}}
    end
  end

  defp string_or_string_list(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) and value != "" ->
        {:ok, value}

      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_param, key, :string_list}}
        end

      _other ->
        {:error, {:invalid_param, key, :string_or_string_list}}
    end
  end

  defp clock_mode(params) when is_map(params) do
    case Map.get(params, "clock_mode") do
      nil -> {:ok, nil}
      :live -> {:ok, :live}
      "live" -> {:ok, :live}
      :replay -> {:ok, :replay}
      "replay" -> {:ok, :replay}
      _other -> {:error, {:invalid_param, "clock_mode", :unknown_atom}}
    end
  end

  defp direction(params) when is_map(params) do
    required_allowed_atom_param(params, "direction", @direction_values)
  end

  defp optional_direction(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @direction_values)
  end

  defp optional_selection_role(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @selection_role_values)
  end

  defp selection_role(params) when is_map(params) do
    allowed_atom_param(params, "selection_role", :candidate, @selection_role_values)
  end

  defp transport_target_scope(params) when is_map(params) do
    allowed_atom_param(params, "target_scope", :path, @transport_target_scope_values)
  end

  defp optional_transport_target_scope(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @transport_target_scope_values)
  end

  defp transport_family_key(params) when is_map(params) do
    case Map.get(params, "family_key") do
      nil -> {:error, {:invalid_param, "family_key", :required}}
      value when is_atom(value) -> {:ok, value}
      value when is_binary(value) -> existing_atom(%{"family_key" => value}, "family_key", nil)
      _other -> {:error, {:invalid_param, "family_key", :atom}}
    end
  end

  defp optional_transport_family_key(params, key) when is_map(params) and is_binary(key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      value when is_atom(value) ->
        {:ok, value}

      value when is_binary(value) ->
        existing_atom(%{key => value}, key, nil)

      _other ->
        {:error, {:invalid_param, key, :atom}}
    end
  end

  defp map_value(params, key) do
    case Map.get(params, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp optional_map(params, key), do: optional_map(params, key, nil)

  defp optional_map(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:ok, nil}
      value when is_map(value) -> {:ok, value}
      _other -> {:error, {:invalid_param, key, :map}}
    end
  end

  defp list_value(params, key) do
    case Map.get(params, key, []) do
      value when is_list(value) -> value
      _other -> []
    end
  end

  defp required_string_list(params, key) do
    case Map.get(params, key) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_param, key, :string_list}}
        end

      _other ->
        {:error, {:invalid_param, key, :string_list}}
    end
  end

  defp optional_string_list(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_param, key, :string_list}}
        end

      _other ->
        {:error, {:invalid_param, key, :string_list}}
    end
  end

  defp optional_patch_string_list(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      optional_string_list(params, key)
    else
      {:ok, nil}
    end
  end

  defp optional_versioned_ref_list(params, key, id_key)
       when is_map(params) and is_binary(key) and is_binary(id_key) do
    case Map.get(params, key) do
      nil ->
        {:ok, []}

      refs when is_list(refs) ->
        reduce_ok(refs, &versioned_ref(&1, id_key))

      _other ->
        {:error, {:invalid_param, key, :list}}
    end
  end

  defp optional_patch_versioned_ref_list(params, key, id_key)
       when is_map(params) and is_binary(key) and is_binary(id_key) do
    if Map.has_key?(params, key) do
      optional_versioned_ref_list(params, key, id_key)
    else
      {:ok, nil}
    end
  end

  defp reduce_ok(values, mapper) when is_list(values) and is_function(mapper, 1) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case mapper.(value) do
        {:ok, normalized_value} -> {:cont, {:ok, acc ++ [normalized_value]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp versioned_ref(ref, id_key) when is_map(ref) and is_binary(id_key) do
    ref_id =
      case Map.get(ref, id_key) do
        value when is_binary(value) and value != "" -> value
        _other -> nil
      end

    with {:ok, version} <- positive_integer(ref, "version", 1),
         true <- is_binary(ref_id) and ref_id != "" do
      {:ok, %{id_key => ref_id, "version" => version}}
    else
      false -> {:error, {:invalid_param, id_key, :required}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp optional_patch_map(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      optional_map(params, key, %{})
    else
      {:ok, nil}
    end
  end

  defp required_packet_binary(params) when is_map(params) do
    packet_hex = string_value(params, "packet_hex")
    packet_base64 = string_value(params, "packet_base64")

    cond do
      is_binary(packet_hex) and is_binary(packet_base64) ->
        {:error, {:invalid_param, "packet_hex", :mutually_exclusive_with_packet_base64}}

      is_binary(packet_hex) ->
        decode_packet_hex(packet_hex)

      is_binary(packet_base64) ->
        decode_packet_base64(packet_base64)

      true ->
        {:error, {:invalid_param, "packet_hex_or_packet_base64", :required}}
    end
  end

  defp required_frame_binary(params) when is_map(params) do
    frame_hex = string_value(params, "frame_hex")
    frame_base64 = string_value(params, "frame_base64")

    cond do
      is_binary(frame_hex) and is_binary(frame_base64) ->
        {:error, {:invalid_param, "frame_hex", :mutually_exclusive_with_frame_base64}}

      is_binary(frame_hex) ->
        decode_packet_hex(frame_hex)

      is_binary(frame_base64) ->
        decode_packet_base64(frame_base64)

      true ->
        {:error, {:invalid_param, "frame_hex_or_frame_base64", :required}}
    end
  end

  defp decode_packet_hex(packet_hex) when is_binary(packet_hex) do
    normalized_hex =
      packet_hex
      |> String.replace(~r/[\s_]/u, "")
      |> String.replace_prefix("0x", "")
      |> String.replace_prefix("0X", "")

    case Base.decode16(normalized_hex, case: :mixed) do
      {:ok, raw_packet} -> {:ok, raw_packet}
      :error -> {:error, {:invalid_param, "packet_hex", :hex}}
    end
  end

  defp decode_packet_base64(packet_base64) when is_binary(packet_base64) do
    normalized_base64 = String.replace(packet_base64, ~r/\s+/u, "")

    case Base.decode64(normalized_base64) do
      {:ok, raw_packet} -> {:ok, raw_packet}
      :error -> {:error, {:invalid_param, "packet_base64", :base64}}
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_attr(map, _key, nil), do: map
  defp maybe_put_attr(map, key, value), do: Map.put(map, key, value)

  defp maybe_string_override(params, key, existing_value) do
    if Map.has_key?(params, key) do
      string_value(params, key) || existing_value
    else
      existing_value
    end
  end

  defp maybe_nullable_string_override(params, key, existing_value) do
    if Map.has_key?(params, key) do
      string_value(params, key)
    else
      existing_value
    end
  end

  defp maybe_map_value(params, key, existing_value) do
    if Map.has_key?(params, key) do
      map_value(params, key)
    else
      existing_value
    end
  end

  defp maybe_map_override(params, key, existing_value) do
    if Map.has_key?(params, key) do
      optional_map(params, key, existing_value)
    else
      {:ok, existing_value}
    end
  end

  defp optional_patch_nullable_string(params, key) when is_map(params) and is_binary(key) do
    if Map.has_key?(params, key) do
      {:ok, string_value(params, key)}
    else
      {:ok, nil}
    end
  end

  defp maybe_non_neg_integer(params, key, existing_value) do
    if Map.has_key?(params, key) do
      non_neg_integer(params, key, existing_value)
    else
      {:ok, existing_value}
    end
  end

  defp maybe_optional_datetime(params, key, existing_value) do
    if Map.has_key?(params, key) do
      optional_datetime(params, key)
    else
      {:ok, existing_value}
    end
  end

  defp resolve_spacecraft_id(params, nil), do: {:ok, string_value(params, "spacecraft_id")}

  defp resolve_spacecraft_id(params, scoped_spacecraft_id) when is_binary(scoped_spacecraft_id) do
    case string_value(params, "spacecraft_id") do
      nil -> {:ok, scoped_spacecraft_id}
      ^scoped_spacecraft_id -> {:ok, scoped_spacecraft_id}
      _other -> {:error, :scope_mismatch}
    end
  end

  defp resolve_scoped_command_stage_id(params, scoped_command_stage_id)
       when is_binary(scoped_command_stage_id) do
    case string_value(params, "command_stage_id") do
      nil -> {:ok, scoped_command_stage_id}
      ^scoped_command_stage_id -> {:ok, scoped_command_stage_id}
      _other -> {:error, :scope_mismatch}
    end
  end
end
