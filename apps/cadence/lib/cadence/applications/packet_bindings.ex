defmodule Cadence.Applications.PacketBindings do
  @moduledoc """
  Host-owned persistence and validation boundary for shareable packet inputs.

  An APID participates in packet selection, but this context deliberately has
  no cross-application uniqueness rule. Exact installation, capability, packet
  model, resource, and configuration versions are validated before a desired
  configuration is replaced.
  """

  import Ecto.Query

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    HostContext,
    PacketBinding,
    PacketBindingConfiguration,
    PacketBindingResource,
    PacketInputDefinition,
    Registry
  }

  alias Cadence.Applications.PacketBindings.{BindingRow, ConfigurationRow, ResourceRow}
  alias Cadence.Auth.Scope
  alias Cadence.Capabilities.{DefinitionRegistry, Descriptor}
  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint

  @max_packets 512

  @type preview :: %{
          configuration: PacketBindingConfiguration.t(),
          input_definition: PacketInputDefinition.t()
        }

  @spec list(Scope.t(), HostContext.t(), binary(), keyword()) ::
          {:ok, [PacketBindingConfiguration.t()]} | {:error, term()}
  def list(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_installation_id,
        opts \\ []
      )
      when is_binary(application_installation_id) and is_list(opts) do
    with {:ok, %ApplicationInstallation{} = installation} <-
           fetch_scoped_installation(current_scope, host_context, application_installation_id) do
      configurations =
        ConfigurationRow
        |> where(
          [row],
          row.application_installation_id == ^installation.application_installation_id
        )
        |> maybe_filter_input(Keyword.get(opts, :input_id))
        |> order_by([row], asc: row.input_id, asc: row.input_version)
        |> Repo.all()
        |> hydrate_configurations()

      {:ok, configurations}
    end
  end

  @spec preview(Scope.t(), HostContext.t(), binary(), map()) ::
          {:ok, preview()} | {:error, term()}
  def preview(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_installation_id,
        attrs
      )
      when is_binary(application_installation_id) and is_map(attrs) do
    with {:ok, %ApplicationInstallation{} = installation} <-
           fetch_scoped_installation(current_scope, host_context, application_installation_id),
         {:ok, input_definition} <- resolve_input_definition(installation, attrs),
         {:ok, existing} <-
           fetch_existing(installation.application_installation_id, input_definition),
         :ok <- validate_expected_version(existing, attrs),
         {:ok, bindings} <-
           resolve_catalog_bindings(current_scope, host_context, input_definition, attrs),
         :ok <- validate_cardinality(input_definition, bindings) do
      {:ok,
       %{
         configuration:
           build_configuration(installation, input_definition, existing, bindings, attrs),
         input_definition: input_definition
       }}
    end
  end

  @spec replace(Scope.t(), HostContext.t(), binary(), map()) ::
          {:ok, PacketBindingConfiguration.t()} | {:error, term()}
  def replace(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_installation_id,
        attrs
      )
      when is_binary(application_installation_id) and is_map(attrs) do
    with {:ok, %{configuration: desired}} <-
           preview(current_scope, host_context, application_installation_id, attrs) do
      persist_replacement(desired, attrs)
    end
  end

  @spec disable(Scope.t(), HostContext.t(), binary()) ::
          {:ok, [PacketBindingConfiguration.t()]} | {:error, term()}
  def disable(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_installation_id
      )
      when is_binary(application_installation_id) do
    with {:ok, %ApplicationInstallation{} = installation} <-
           fetch_scoped_installation(current_scope, host_context, application_installation_id) do
      installation
      |> disable_installation_bindings_transaction()
      |> normalize_configuration_transaction()
    end
  end

  @doc false
  @spec list_for_mission(binary(), binary(), keyword()) ::
          [PacketBindingConfiguration.t()]
  def list_for_mission(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ConfigurationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_application(Keyword.get(opts, :application_key))
    |> maybe_filter_enabled(Keyword.get(opts, :enabled))
    |> order_by([row], asc: row.application_key, asc: row.spacecraft_id, asc: row.input_id)
    |> Repo.all()
    |> hydrate_configurations()
  end

  @doc false
  @spec stamp_applied_for_mission(binary(), binary(), binary(), pos_integer(), keyword()) ::
          :ok | {:error, term()}
  def stamp_applied_for_mission(
        organization_id,
        mission_id,
        binding_set_id,
        binding_set_version,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(binding_set_id) and is_integer(binding_set_version) and
             binding_set_version > 0 and is_list(opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    application_key = Keyword.get(opts, :application_key)

    organization_id
    |> applied_rows_query(mission_id, application_key)
    |> stamp_applied_transaction(binding_set_id, binding_set_version, now)
    |> normalize_stamp_transaction()
  end

  defp applied_rows_query(organization_id, mission_id, application_key) do
    ConfigurationRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_application(application_key)
    |> lock("FOR UPDATE")
  end

  defp stamp_applied_row(row, binding_set_id, binding_set_version, now) do
    changes = applied_stamp_changes(row, binding_set_id, binding_set_version, now)

    case row |> Ecto.Changeset.change(changes) |> Repo.update() do
      {:ok, _updated} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp stamp_applied_transaction(query, binding_set_id, binding_set_version, now) do
    Repo.transaction(fn ->
      query
      |> Repo.all()
      |> Enum.each(&stamp_applied_row(&1, binding_set_id, binding_set_version, now))

      :ok
    end)
  end

  defp applied_stamp_changes(%ConfigurationRow{enabled: true}, binding_set_id, version, now) do
    %{
      applied_binding_set_id: binding_set_id,
      applied_binding_set_version: version,
      applied_at: now
    }
  end

  defp applied_stamp_changes(%ConfigurationRow{}, _binding_set_id, _version, _now) do
    %{applied_binding_set_id: nil, applied_binding_set_version: nil, applied_at: nil}
  end

  defp normalize_stamp_transaction({:ok, :ok}), do: :ok
  defp normalize_stamp_transaction({:error, reason}), do: {:error, reason}

  defp disable_installation_bindings_transaction(installation),
    do: Repo.transaction(fn -> disable_installation_bindings(installation) end)

  defp normalize_configuration_transaction({:ok, configurations}),
    do: {:ok, configurations}

  defp normalize_configuration_transaction({:error, reason}), do: {:error, reason}

  defp fetch_scoped_installation(current_scope, host_context, installation_id) do
    with {:ok, installations} <- ApplicationInstallations.list(current_scope, host_context),
         %ApplicationInstallation{lifecycle_state: :installed} = installation <-
           Enum.find(installations, &(&1.application_installation_id == installation_id)) do
      {:ok, installation}
    else
      %ApplicationInstallation{lifecycle_state: :disabled} ->
        {:error, :application_installation_disabled}

      %ApplicationInstallation{lifecycle_state: :uninstalled} ->
        {:error, :application_installation_uninstalled}

      nil ->
        {:error, :application_not_installed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_input_definition(%ApplicationInstallation{} = installation, attrs) do
    input_id = value(attrs, :input_id)
    requested_version = value(attrs, :input_version)

    with input_id when is_binary(input_id) and input_id != "" <- input_id,
         {:ok, %ApplicationDefinition{} = definition} <-
           Registry.fetch_available(
             installation.application_key,
             installation.application_version
           ),
         {:ok, input_definition} <-
           find_input_definition(definition, input_id, requested_version) do
      {:ok, input_definition}
    else
      nil -> {:error, :packet_input_id_required}
      "" -> {:error, :packet_input_id_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_input_definition(%ApplicationDefinition{} = definition, input_id, requested_version) do
    matches =
      definition.capability_contributions
      |> Enum.flat_map(fn contribution ->
        family_key = Map.get(contribution, :family_key)

        case DefinitionRegistry.fetch_descriptor(DefinitionRegistry.default(), family_key) do
          {:ok, %Descriptor{} = descriptor} -> descriptor.packet_inputs
          {:error, _reason} -> []
        end
      end)
      |> Enum.filter(fn input ->
        input.input_id == input_id and
          (is_nil(requested_version) or requested_version == input.version or
             requested_version == Integer.to_string(input.version))
      end)

    case matches do
      [%PacketInputDefinition{} = input] -> {:ok, input}
      [] -> {:error, :unknown_application_packet_input}
      _many -> {:error, :ambiguous_application_packet_input}
    end
  end

  defp resolve_catalog_bindings(
         %Scope{organization_id: organization_id},
         %HostContext{mission_id: mission_id} = host_context,
         %PacketInputDefinition{} = input_definition,
         attrs
       ) do
    with {:ok, catalog_revision_id} <- required_text(attrs, :catalog_revision_id),
         {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         {:ok, telemetry} <- TelemetryProjection.load(organization_id, mission_id, revision),
         {:ok, source_endpoint_ref} <-
           validate_source_endpoint(
             organization_id,
             mission_id,
             host_context,
             value(attrs, :source_endpoint_ref)
           ),
         {:ok, packet_ids} <- selected_packet_ids(attrs),
         {:ok, packets} <- select_packets(telemetry.packet_definitions, packet_ids) do
      build_packet_bindings(
        telemetry,
        revision,
        packets,
        source_endpoint_ref,
        input_definition
      )
    end
  end

  defp validate_source_endpoint(_organization_id, _mission_id, _host_context, nil),
    do: {:error, :packet_binding_source_endpoint_required}

  defp validate_source_endpoint(
         organization_id,
         mission_id,
         %HostContext{} = host_context,
         source_endpoint_ref
       )
       when is_binary(source_endpoint_ref) and source_endpoint_ref != "" do
    with {:ok, %SourceEndpoint{} = endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             organization_id,
             mission_id,
             source_endpoint_ref
           ),
         :ok <- endpoint_matches_host(endpoint, host_context) do
      {:ok, endpoint.source_endpoint_id}
    end
  end

  defp validate_source_endpoint(_organization_id, _mission_id, _host_context, _source),
    do: {:error, :packet_binding_source_endpoint_required}

  defp endpoint_matches_host(%SourceEndpoint{}, %HostContext{placement: :mission}), do: :ok
  defp endpoint_matches_host(%SourceEndpoint{spacecraft_id: nil}, %HostContext{}), do: :ok

  defp endpoint_matches_host(
         %SourceEndpoint{spacecraft_id: spacecraft_id},
         %HostContext{placement: :spacecraft, spacecraft_id: spacecraft_id}
       ),
       do: :ok

  defp endpoint_matches_host(%SourceEndpoint{}, %HostContext{}),
    do: {:error, :source_endpoint_belongs_to_other_spacecraft}

  defp selected_packet_ids(attrs) do
    packet_ids =
      attrs
      |> value(:selected_packet_ids, [])
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    if length(packet_ids) <= @max_packets,
      do: {:ok, packet_ids},
      else: {:error, :packet_binding_selection_too_large}
  end

  defp select_packets(packet_definitions, packet_ids) do
    packet_by_id = Map.new(packet_definitions, &{&1.packet_definition_id, &1})
    missing_ids = Enum.reject(packet_ids, &Map.has_key?(packet_by_id, &1))

    case missing_ids do
      [] -> {:ok, Enum.map(packet_ids, &Map.fetch!(packet_by_id, &1))}
      _missing -> {:error, {:packet_binding_packets_not_in_revision, missing_ids}}
    end
  end

  defp build_packet_bindings(
         telemetry,
         revision,
         packets,
         source_endpoint_ref,
         %PacketInputDefinition{selection_mode: :compatible_fields} = input_definition
       ) do
    Enum.reduce_while(packets, {:ok, []}, fn packet, {:ok, bindings} ->
      append_compatible_packet_binding(
        packet,
        bindings,
        input_definition,
        revision,
        telemetry,
        source_endpoint_ref
      )
    end)
    |> reverse_bindings()
  end

  defp build_packet_bindings(
         telemetry,
         revision,
         packets,
         source_endpoint_ref,
         %PacketInputDefinition{selection_mode: :whole_packet}
       ) do
    bindings =
      Enum.map(packets, fn packet ->
        resource =
          PacketBindingResource.new(%{
            packet_binding_resource_id:
              "packet_binding_resource:#{packet.packet_definition_id}:whole_packet",
            resource_id: packet.packet_definition_id,
            resource_kind: :whole_packet,
            path: packet.packet_name,
            role: :primary
          })

        catalog_binding(revision, telemetry, packet, source_endpoint_ref, [resource])
      end)

    {:ok, bindings}
  end

  defp build_packet_bindings(
         _telemetry,
         _revision,
         _packets,
         _source_endpoint_ref,
         %PacketInputDefinition{selection_mode: :explicit_fields}
       ),
       do: {:error, :explicit_field_packet_bindings_not_supported}

  defp append_compatible_packet_binding(
         packet,
         bindings,
         input_definition,
         revision,
         telemetry,
         source_endpoint_ref
       ) do
    resources =
      packet.fields
      |> Enum.filter(&(&1.data_type in input_definition.accepted_data_types))
      |> Enum.map(&field_resource(packet.packet_definition_id, &1))

    if resources == [] do
      {:halt, {:error, {:packet_input_incompatible, packet.packet_definition_id}}}
    else
      binding = catalog_binding(revision, telemetry, packet, source_endpoint_ref, resources)
      {:cont, {:ok, [binding | bindings]}}
    end
  end

  defp catalog_binding(revision, telemetry, packet, source_endpoint_ref, resources) do
    PacketBinding.new(%{
      packet_binding_id: "packet_binding:#{packet.packet_definition_id}",
      source_endpoint_ref: source_endpoint_ref,
      catalog_revision_id: revision.catalog_revision_id,
      mission_model_revision_id: telemetry.mission_model_revision.revision_id,
      packet_id: packet.packet_definition_id,
      packet_model_content_sha256: telemetry.mission_model_revision.content_sha256,
      packet_name: packet.packet_name,
      apid: packet.apid,
      selector: %{
        match: %{packet_kind: :space_packet, apid: packet.apid},
        scope: %{
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref
        }
      },
      resources: resources,
      metadata: %{
        "catalog_revision_label" => revision.revision_label,
        "telemetry_plan_id" => telemetry.telemetry_plan.plan_id
      }
    })
  end

  defp field_resource(packet_id, field) do
    resource_kind = if(field.data_type == :binary, do: :binary_region, else: :field)

    PacketBindingResource.new(%{
      packet_binding_resource_id: "packet_binding_resource:#{packet_id}:#{field.field_id}",
      resource_id: field.field_id,
      resource_kind: resource_kind,
      path: field.name,
      data_type: field.data_type,
      offset_bits: field.offset_bits,
      size_bits: field.size_bits,
      role: :primary
    })
  end

  defp reverse_bindings({:ok, bindings}), do: {:ok, Enum.reverse(bindings)}
  defp reverse_bindings({:error, reason}), do: {:error, reason}

  defp validate_cardinality(%PacketInputDefinition{} = input_definition, bindings) do
    resources = Enum.flat_map(bindings, & &1.resources)
    resource_count = length(resources)

    cond do
      resource_count < input_definition.min_selected ->
        {:error,
         {:packet_binding_selection_too_small, input_definition.min_selected, resource_count}}

      resource_count > input_definition.max_selected ->
        {:error,
         {:packet_binding_selection_too_large, input_definition.max_selected, resource_count}}

      Enum.any?(resources, &(&1.resource_kind not in input_definition.accepted_resource_kinds)) ->
        {:error, :packet_binding_resource_kind_not_accepted}

      Enum.any?(resources, fn resource ->
        not is_nil(resource.data_type) and
            resource.data_type not in input_definition.accepted_data_types
      end) ->
        {:error, :packet_binding_data_type_not_accepted}

      true ->
        :ok
    end
  end

  defp build_configuration(installation, input_definition, existing, bindings, attrs) do
    current_version = existing && existing.configuration_version

    configuration_id =
      if(existing,
        do: existing.packet_binding_configuration_id,
        else:
          "packet_binding_configuration:#{installation.application_installation_id}:#{input_definition.input_id}:#{input_definition.version}"
      )

    bindings = canonicalize_binding_ids(configuration_id, bindings)

    semantic_change? =
      is_nil(existing) or
        semantic_configuration(existing) !=
          semantic_configuration(%{
            enabled: boolean_value(attrs, :enabled, true),
            bindings: bindings,
            metadata: value(attrs, :metadata, %{})
          })

    PacketBindingConfiguration.new(%{
      packet_binding_configuration_id: configuration_id,
      organization_id: installation.organization_id,
      mission_id: installation.mission_id,
      spacecraft_id: spacecraft_id(installation),
      application_installation_id: installation.application_installation_id,
      application_key: installation.application_key,
      application_version: installation.application_version,
      capability_family_key: input_definition.capability_family_key,
      input_id: input_definition.input_id,
      input_version: input_definition.version,
      configuration_version:
        if(semantic_change?, do: (current_version || 0) + 1, else: current_version),
      enabled: boolean_value(attrs, :enabled, true),
      applied_binding_set_id:
        if(semantic_change?, do: nil, else: existing.applied_binding_set_id),
      applied_binding_set_version:
        if(semantic_change?, do: nil, else: existing.applied_binding_set_version),
      applied_at: if(semantic_change?, do: nil, else: existing.applied_at),
      bindings: bindings,
      metadata: value(attrs, :metadata, %{})
    })
  end

  defp semantic_configuration(%PacketBindingConfiguration{} = configuration) do
    semantic_configuration(%{
      enabled: configuration.enabled,
      bindings: configuration.bindings,
      metadata: configuration.metadata
    })
  end

  defp semantic_configuration(configuration) when is_map(configuration) do
    %{
      enabled: Map.fetch!(configuration, :enabled),
      bindings:
        configuration
        |> Map.fetch!(:bindings)
        |> Enum.map(fn binding ->
          %{
            source_endpoint_ref: binding.source_endpoint_ref,
            catalog_revision_id: binding.catalog_revision_id,
            mission_model_revision_id: binding.mission_model_revision_id,
            packet_id: binding.packet_id,
            packet_model_content_sha256: binding.packet_model_content_sha256,
            packet_name: binding.packet_name,
            apid: binding.apid,
            selector: JsonDocument.encode(binding.selector),
            resources:
              Enum.map(binding.resources, fn resource ->
                Map.take(resource, [
                  :resource_id,
                  :resource_kind,
                  :path,
                  :data_type,
                  :offset_bits,
                  :size_bits,
                  :role,
                  :metadata
                ])
                |> JsonDocument.encode()
              end),
            metadata: JsonDocument.encode(binding.metadata)
          }
        end),
      metadata: configuration |> Map.fetch!(:metadata) |> JsonDocument.encode()
    }
  end

  defp canonicalize_binding_ids(configuration_id, bindings) do
    Enum.map(bindings, fn %PacketBinding{} = binding ->
      binding_id =
        content_id(:packet_binding, {configuration_id, binding.packet_id || binding.apid})

      resources =
        Enum.map(binding.resources, fn %PacketBindingResource{} = resource ->
          %PacketBindingResource{
            resource
            | packet_binding_resource_id:
                content_id(:packet_binding_resource, {binding_id, resource.resource_id})
          }
        end)

      %PacketBinding{binding | packet_binding_id: binding_id, resources: resources}
    end)
  end

  defp content_id(kind, basis), do: "#{kind}:#{ContentHash.term_sha256(basis)}"

  defp persist_replacement(%PacketBindingConfiguration{} = desired, attrs) do
    case Repo.transaction(fn -> locked_replace(desired, attrs) end) do
      {:ok, %PacketBindingConfiguration{} = persisted} -> {:ok, persisted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp locked_replace(%PacketBindingConfiguration{} = desired, attrs) do
    existing_row =
      ConfigurationRow
      |> where(
        [row],
        row.application_installation_id == ^desired.application_installation_id and
          row.input_id == ^desired.input_id and row.input_version == ^desired.input_version
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    existing = existing_row && hydrate_configuration(existing_row)

    case validate_expected_version(existing, attrs) do
      :ok ->
        if existing && semantic_configuration(existing) == semantic_configuration(desired) do
          existing
        else
          persist_configuration(existing_row, desired)
        end

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp persist_configuration(existing_row, desired) do
    with {:ok, configuration_row} <-
           Repo.insert_or_update(
             ConfigurationRow.changeset(existing_row || %ConfigurationRow{}, desired)
           ),
         {_count, _rows} <-
           from(binding in BindingRow,
             where:
               binding.packet_binding_configuration_id ==
                 ^configuration_row.packet_binding_configuration_id
           )
           |> Repo.delete_all(),
         :ok <-
           persist_bindings(configuration_row.packet_binding_configuration_id, desired.bindings) do
      hydrate_configuration(configuration_row)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_bindings(configuration_id, bindings) do
    Enum.reduce_while(bindings, :ok, &persist_binding(configuration_id, &1, &2))
  end

  defp persist_binding(configuration_id, binding, :ok) do
    case Repo.insert(BindingRow.changeset(%BindingRow{}, configuration_id, binding)) do
      {:ok, binding_row} -> persist_binding_resources(binding_row, binding.resources)
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp persist_binding_resources(binding_row, resources) do
    case persist_resources(binding_row.packet_binding_id, resources) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp persist_resources(packet_binding_id, resources) do
    Enum.reduce_while(resources, :ok, fn resource, :ok ->
      case Repo.insert(ResourceRow.changeset(%ResourceRow{}, packet_binding_id, resource)) do
        {:ok, _row} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp disable_installation_bindings(%ApplicationInstallation{} = installation) do
    rows =
      ConfigurationRow
      |> where(
        [row],
        row.application_installation_id == ^installation.application_installation_id
      )
      |> lock("FOR UPDATE")
      |> Repo.all()

    Enum.map(rows, &disable_configuration_row/1)
  end

  defp disable_configuration_row(%ConfigurationRow{enabled: false} = row),
    do: hydrate_configuration(row)

  defp disable_configuration_row(%ConfigurationRow{} = row) do
    changes = %{
      enabled: false,
      configuration_version: row.configuration_version + 1,
      applied_binding_set_id: nil,
      applied_binding_set_version: nil,
      applied_at: nil
    }

    case row |> Ecto.Changeset.change(changes) |> Repo.update() do
      {:ok, updated} -> hydrate_configuration(updated)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp fetch_existing(installation_id, %PacketInputDefinition{} = input_definition) do
    row =
      ConfigurationRow
      |> where(
        [row],
        row.application_installation_id == ^installation_id and
          row.input_id == ^input_definition.input_id and
          row.input_version == ^input_definition.version
      )
      |> Repo.one()

    {:ok, row && hydrate_configuration(row)}
  end

  defp validate_expected_version(nil, attrs) do
    case integer_value(attrs, :expected_configuration_version) do
      nil -> :ok
      0 -> :ok
      expected -> {:error, {:packet_binding_configuration_version_conflict, expected, nil}}
    end
  end

  defp validate_expected_version(%PacketBindingConfiguration{} = existing, attrs) do
    case integer_value(attrs, :expected_configuration_version) do
      expected when expected == existing.configuration_version ->
        :ok

      expected ->
        {:error,
         {:packet_binding_configuration_version_conflict, expected,
          existing.configuration_version}}
    end
  end

  defp hydrate_configurations(rows), do: Enum.map(rows, &hydrate_configuration/1)

  defp hydrate_configuration(%ConfigurationRow{} = row) do
    binding_rows =
      BindingRow
      |> where(
        [binding],
        binding.packet_binding_configuration_id == ^row.packet_binding_configuration_id
      )
      |> order_by([binding], asc: binding.apid, asc: binding.packet_name)
      |> Repo.all()

    resources =
      if binding_rows == [] do
        %{}
      else
        binding_ids = Enum.map(binding_rows, & &1.packet_binding_id)

        ResourceRow
        |> where([resource], resource.packet_binding_id in ^binding_ids)
        |> order_by([resource], asc: resource.offset_bits, asc: resource.resource_id)
        |> Repo.all()
        |> Enum.group_by(& &1.packet_binding_id)
      end

    PacketBindingConfiguration.new(%{
      packet_binding_configuration_id: row.packet_binding_configuration_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      spacecraft_id: row.spacecraft_id,
      application_installation_id: row.application_installation_id,
      application_key: row.application_key,
      application_version: row.application_version,
      capability_family_key: String.to_existing_atom(row.capability_family_key),
      input_id: row.input_id,
      input_version: row.input_version,
      configuration_version: row.configuration_version,
      enabled: row.enabled,
      applied_binding_set_id: row.applied_binding_set_id,
      applied_binding_set_version: row.applied_binding_set_version,
      applied_at: row.applied_at,
      bindings:
        Enum.map(binding_rows, fn binding_row ->
          binding_from_row(binding_row, Map.get(resources, binding_row.packet_binding_id, []))
        end),
      inserted_at: row.inserted_at,
      updated_at: row.updated_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp binding_from_row(row, resource_rows) do
    PacketBinding.new(%{
      packet_binding_id: row.packet_binding_id,
      source_endpoint_ref: row.source_endpoint_ref,
      catalog_revision_id: row.catalog_revision_id,
      mission_model_revision_id: row.mission_model_revision_id,
      packet_id: row.packet_id,
      packet_model_content_sha256: row.packet_model_content_sha256,
      packet_name: row.packet_name,
      apid: row.apid,
      selector: JsonDocument.unwrap_value(row.selector),
      resources: Enum.map(resource_rows, &resource_from_row/1),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp resource_from_row(row) do
    PacketBindingResource.new(%{
      packet_binding_resource_id: row.packet_binding_resource_id,
      resource_id: row.resource_id,
      resource_kind: row.resource_kind,
      path: row.path,
      data_type: row.data_type,
      offset_bits: row.offset_bits,
      size_bits: row.size_bits,
      role: row.role,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp maybe_filter_input(query, nil), do: query
  defp maybe_filter_input(query, input_id), do: where(query, [row], row.input_id == ^input_id)

  defp maybe_filter_application(query, nil), do: query

  defp maybe_filter_application(query, application_key),
    do: where(query, [row], row.application_key == ^application_key)

  defp maybe_filter_enabled(query, nil), do: query
  defp maybe_filter_enabled(query, enabled), do: where(query, [row], row.enabled == ^enabled)

  defp spacecraft_id(%ApplicationInstallation{scope_kind: :spacecraft, scope_id: scope_id}),
    do: scope_id

  defp spacecraft_id(%ApplicationInstallation{}), do: nil

  defp required_text(attrs, key) do
    case value(attrs, key) do
      text when is_binary(text) and text != "" -> {:ok, text}
      _missing -> {:error, {:missing_packet_binding_attribute, key}}
    end
  end

  defp integer_value(attrs, key) do
    case value(attrs, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _other -> nil
    end
  end

  defp boolean_value(attrs, key, default) do
    case value(attrs, key, default) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _other -> default
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
