defmodule Cadence.Contacts.PathTemplateStore do
  @moduledoc """
  Persists, versions, and resolves reusable contact path templates.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.ConfigurationValidation
  alias Cadence.Contacts.Path
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore.{ArchivedProfile, PathTemplateRow, VersionedReferences}
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Contacts.ProviderBinding
  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Contacts.TransportBinding
  alias Cadence.Contacts.TransportProfile
  alias Cadence.Listing
  alias Cadence.Missions
  alias Cadence.Persistence.{BulkInsert, BulkLookup}
  alias Cadence.Repo

  @spec persist(binary(), PathTemplate.t()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def persist(organization_id, %PathTemplate{} = path_template)
      when is_binary(organization_id) do
    with {:ok, scoped_path_template} <- put_organization_scope(path_template, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_path_template.organization_id,
             scoped_path_template.mission_id
           ),
         {:ok, prepared_path_template} <- prepare(scoped_path_template),
         :ok <- validate(prepared_path_template),
         {:ok, _row} <-
           Repo.insert(PathTemplateRow.changeset(prepared_path_template),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :path_template_id, :version]
           ) do
      fetch_version(
        prepared_path_template.organization_id,
        prepared_path_template.mission_id,
        prepared_path_template.path_template_id,
        prepared_path_template.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist(PathTemplate.t()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def persist(%PathTemplate{} = path_template) do
    with {:ok, prepared_path_template} <- prepare(path_template),
         :ok <- validate(prepared_path_template) do
      case Repo.insert(PathTemplateRow.changeset(prepared_path_template),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :path_template_id, :version]
           ) do
        {:ok, %PathTemplateRow{} = row} ->
          {:ok, PathTemplateRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec fetch(binary(), binary()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def fetch(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    case latest_versioned_row(mission_id, path_template_id) do
      nil ->
        {:error, :contact_path_template_not_found}

      %PathTemplateRow{lifecycle_state: "deleted"} ->
        {:error, :contact_path_template_not_found}

      %PathTemplateRow{} = row ->
        {:ok, PathTemplateRow.to_domain(row)}
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) do
    case latest_versioned_row(organization_id, mission_id, path_template_id) do
      nil ->
        {:error, :contact_path_template_not_found}

      %PathTemplateRow{lifecycle_state: "deleted"} ->
        {:error, :contact_path_template_not_found}

      %PathTemplateRow{} = row ->
        {:ok, PathTemplateRow.to_domain(row)}
    end
  end

  @spec fetch_version(binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_version(mission_id, path_template_id, version)
      when is_binary(mission_id) and is_binary(path_template_id) and is_integer(version) and
             version > 0 do
    case Repo.get_by(PathTemplateRow,
           mission_id: mission_id,
           path_template_id: path_template_id,
           version: version
         ) do
      nil -> {:error, :contact_path_template_not_found}
      %PathTemplateRow{} = row -> {:ok, PathTemplateRow.to_domain(row)}
    end
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_version(organization_id, mission_id, path_template_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_integer(version) and version > 0 do
    case Repo.get_by(PathTemplateRow,
           organization_id: organization_id,
           mission_id: mission_id,
           path_template_id: path_template_id,
           version: version
         ) do
      nil -> {:error, :contact_path_template_not_found}
      %PathTemplateRow{} = row -> {:ok, PathTemplateRow.to_domain(row)}
    end
  end

  @doc "Exact mission path template versions keyed by `{id, version}`."
  def fetch_versions(organization_id, mission_id, keys) do
    PathTemplateRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> BulkLookup.by_version(:path_template_id, keys)
    |> Map.new(&{{&1.path_template_id, &1.version}, PathTemplateRow.to_domain(&1)})
  end

  @doc "Returns one bounded page of active latest path-template versions."
  @spec list_page(binary(), binary(), keyword()) :: Listing.Page.t()
  def list_page(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    %{page: page, page_size: page_size, offset: offset} = Listing.page_opts(opts)

    latest =
      PathTemplateRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )
      |> distinct([row], row.path_template_id)
      |> order_by([row], asc: row.path_template_id, desc: row.version)

    filtered =
      latest
      |> subquery()
      |> where([row], row.lifecycle_state != "deleted")
      |> apply_search(Keyword.get(opts, :search))

    items =
      filtered
      |> order_by([row], asc: row.path_template_id)
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&PathTemplateRow.to_domain/1)

    %Listing.Page{
      items: items,
      total_count: Repo.aggregate(filtered, :count),
      page: page,
      page_size: page_size
    }
  end

  @spec list_versions(binary(), binary(), binary()) :: [PathTemplate.t()]
  def list_versions(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(path_template_id) do
    PathTemplateRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.path_template_id == ^path_template_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&PathTemplateRow.to_domain/1)
  end

  @spec version(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def version(organization_id, mission_id, path_template_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_map(attrs) do
    with {:ok, %PathTemplate{} = current_path_template} <-
           fetch(organization_id, mission_id, path_template_id),
         {:ok, %PathTemplate{} = next_path_template} <-
           build_next_version(current_path_template, attrs) do
      persist(organization_id, next_path_template)
    end
  end

  @spec delete(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def delete(organization_id, mission_id, path_template_id, metadata_patch)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_map(metadata_patch) do
    with {:ok, %PathTemplate{} = current_path_template} <-
           fetch(organization_id, mission_id, path_template_id) do
      tombstone =
        %PathTemplate{
          current_path_template
          | version: current_path_template.version + 1,
            lifecycle_state: :deleted,
            metadata:
              current_path_template.metadata
              |> Map.merge(metadata_patch)
              |> Map.put("deleted_at", DateTime.utc_now())
        }

      persist(organization_id, tombstone)
    end
  end

  @doc false
  def persist_route_templates(templates) do
    BulkInsert.changesets(PathTemplateRow, Stream.map(templates, &PathTemplateRow.changeset/1),
      on_conflict: :nothing,
      conflict_target: [:mission_id, :path_template_id, :version]
    )
  end

  @doc false
  def retire_route_templates(organization_id, mission_id, retired_by) do
    now = DateTime.utc_now()

    tombstones =
      PathTemplateRow
      |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
      |> distinct([row], row.path_template_id)
      |> order_by([row], desc: row.version)
      |> BulkLookup.by_id(:path_template_id, Map.keys(retired_by))
      |> Enum.reject(&(&1.lifecycle_state == "deleted"))
      |> Enum.map(fn row ->
        template = PathTemplateRow.to_domain(row)

        %{
          template
          | version: template.version + 1,
            lifecycle_state: :deleted,
            metadata:
              template.metadata
              |> Map.put(
                "retired_by_routing_rule",
                Map.fetch!(retired_by, template.path_template_id)
              )
              |> Map.put("deleted_at", now)
        }
      end)

    persist_route_templates(tombstones)
  end

  @spec fetch_ref(binary() | nil, binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_ref(organization_id, mission_id, ref)
      when is_binary(mission_id) and is_map(ref) do
    organization_id
    |> load_refs(mission_id, [ref])
    |> fetch_loaded_ref(ref)
  end

  @doc false
  def load_refs(org, mission, refs) do
    keys = Enum.map(refs, &VersionedReferences.key(&1, "path_template_id"))
    latest = for {id, nil} <- keys, do: id

    PathTemplateRow
    |> VersionedReferences.in_scope(org, mission)
    |> VersionedReferences.load(:path_template_id, keys, latest, &PathTemplateRow.to_domain/1)
  end

  @doc false
  def fetch_loaded_ref(templates, ref) do
    key = VersionedReferences.key(ref, "path_template_id")
    VersionedReferences.fetch(templates, key, :contact_path_template_not_found)
  end

  @spec resolve(PathTemplate.t()) :: {:ok, Path.t()} | {:error, term()}
  def resolve(%PathTemplate{} = path_template) do
    [path_template]
    |> resolve_many()
    |> Map.fetch!(path_template)
  end

  @doc false
  def resolve_many(templates) do
    templates
    |> Enum.uniq()
    |> Enum.group_by(&{&1.organization_id, &1.mission_id})
    |> Enum.flat_map(fn {{org, mission}, templates} ->
      provider_profiles =
        ProfileStore.load_provider_refs(org, mission, Enum.flat_map(templates, &provider_refs/1))

      transport_profiles =
        ProfileStore.load_transport_refs(
          org,
          mission,
          Enum.flat_map(templates, &transport_refs/1)
        )

      Enum.map(templates, &{&1, resolve(&1, provider_profiles, transport_profiles)})
    end)
    |> Map.new()
  end

  defp resolve(path_template, providers, transports) do
    with {:ok, provider_bindings} <- resolve_provider_bindings(path_template, providers),
         {:ok, transport_bindings} <- resolve_transport_bindings(path_template, transports) do
      provider_bindings = link_clcw_ingress(provider_bindings, transport_bindings)

      metadata =
        path_template.metadata
        |> Map.put("path_template_id", path_template.path_template_id)
        |> Map.put("path_template_version", path_template.version)

      {:ok,
       Path.new(%{
         path_id: path_template.path_id,
         direction: path_template.direction,
         selection_role: path_template.selection_role,
         source_endpoint_ref: path_template.source_endpoint_ref,
         provider_path_ref: path_template.provider_path_ref,
         provider_bindings: provider_bindings,
         transport_bindings: transport_bindings,
         metadata: metadata
       })}
    end
  end

  # CLCWs arriving on a provider binding must reach FOP in the path's uplink gateway. A provider
  # profile is shared by every route on its transport while gateways are per spacecraft, so the
  # link is made here, per path: with exactly one gateway, a CLCW ingress binding that names
  # none is pointed at it (#44).
  defp link_clcw_ingress(provider_bindings, transport_bindings) do
    case Enum.filter(transport_bindings, &(&1.family_key == :uplink_gateway)) do
      [gateway] -> Enum.map(provider_bindings, &link_binding(&1, gateway.transport_binding_id))
      _none_or_many -> provider_bindings
    end
  end

  defp link_binding(%ProviderBinding{configuration: configuration} = binding, gateway_id) do
    clcw? =
      configuration_value(configuration, "ingress_protocol_family", :ingress_protocol_family) in [
        "cop1_clcw",
        :cop1_clcw
      ]

    linked? =
      configuration_value(
        configuration,
        "ingress_transport_binding_id",
        :ingress_transport_binding_id
      ) not in [nil, ""]

    if clcw? and not linked?,
      do: %{
        binding
        | configuration: Map.put(configuration, "ingress_transport_binding_id", gateway_id)
      },
      else: binding
  end

  defp configuration_value(configuration, key, atom_key),
    do: Map.get(configuration, key, Map.get(configuration, atom_key))

  defp validate(%PathTemplate{} = path_template) do
    with :ok <- ConfigurationValidation.mission_id(path_template.mission_id),
         :ok <- ConfigurationValidation.reusable_refs(path_template.provider_profile_ids),
         :ok <- ConfigurationValidation.reusable_refs(path_template.transport_profile_ids),
         {:ok, _path} <- resolve(path_template) do
      :ok
    end
  end

  defp prepare(%PathTemplate{} = path_template) do
    with {:ok, provider_profile_refs} <-
           normalize_versioned_refs(
             path_template.provider_profile_ids,
             path_template.provider_profile_refs,
             "provider_profile_id",
             fn ref ->
               fetch_provider_profile_ref(
                 path_template.organization_id,
                 path_template.mission_id,
                 ref
               )
             end
           ),
         {:ok, transport_profile_refs} <-
           normalize_versioned_refs(
             path_template.transport_profile_ids,
             path_template.transport_profile_refs,
             "transport_profile_id",
             fn ref ->
               fetch_transport_profile_ref(
                 path_template.organization_id,
                 path_template.mission_id,
                 ref
               )
             end
           ),
         :ok <-
           ConfigurationValidation.reusable_refs(
             ids_from_refs(provider_profile_refs, "provider_profile_id")
           ),
         :ok <-
           ConfigurationValidation.reusable_refs(
             ids_from_refs(transport_profile_refs, "transport_profile_id")
           ) do
      {:ok,
       %PathTemplate{
         path_template
         | source_endpoint_ref: nil,
           provider_profile_ids: ids_from_refs(provider_profile_refs, "provider_profile_id"),
           provider_profile_refs: provider_profile_refs,
           transport_profile_ids: ids_from_refs(transport_profile_refs, "transport_profile_id"),
           transport_profile_refs: transport_profile_refs
       }}
    end
  end

  defp provider_refs(template) do
    VersionedReferences.refs(
      template.provider_profile_ids,
      template.provider_profile_refs,
      "provider_profile_id"
    )
  end

  defp transport_refs(template) do
    VersionedReferences.refs(
      template.transport_profile_ids,
      template.transport_profile_refs,
      "transport_profile_id"
    )
  end

  defp resolve_provider_bindings(%PathTemplate{} = path_template, profiles) do
    Enum.reduce_while(provider_refs(path_template), {:ok, []}, fn ref, {:ok, acc} ->
      case provider_profile(profiles, ref) do
        {:ok, %ProviderProfile{} = provider_profile} ->
          provider_binding =
            ProviderBinding.new(%{
              provider_binding_id: provider_profile.provider_profile_id,
              adapter_key: provider_profile.adapter_key,
              configuration: provider_profile.configuration,
              metadata:
                provider_profile.metadata
                |> Map.put("provider_profile_id", provider_profile.provider_profile_id)
                |> Map.put("provider_profile_version", provider_profile.version)
            })

          {:cont, {:ok, acc ++ [provider_binding]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_transport_bindings(%PathTemplate{} = path_template, profiles) do
    Enum.reduce_while(transport_refs(path_template), {:ok, []}, fn ref, {:ok, acc} ->
      case transport_profile(profiles, ref) do
        {:ok, %TransportProfile{} = transport_profile} ->
          transport_binding =
            TransportBinding.new(%{
              transport_binding_id: transport_profile.transport_profile_id,
              family_key: transport_profile.family_key,
              target_scope: transport_profile.target_scope,
              configuration: transport_profile.configuration,
              metadata:
                transport_profile.metadata
                |> Map.put("transport_profile_id", transport_profile.transport_profile_id)
                |> Map.put("transport_profile_version", transport_profile.version)
            })

          {:cont, {:ok, acc ++ [transport_binding]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_provider_profile_ref(org, mission, ref) do
    org |> ProfileStore.load_provider_refs(mission, [ref]) |> provider_profile(ref)
  end

  defp provider_profile(profiles, ref) do
    {id, version} = key = VersionedReferences.key(ref, "provider_profile_id")
    not_found = :contact_provider_profile_not_found

    # A pinned provider version is only usable while its latest version is live. The pinned
    # metadata identifies an archived transport in the refusal.
    with %ProviderProfile{} = pinned <- Map.get(profiles, key),
         :ok <- provider_version_live(profiles, id, version, pinned) do
      VersionedReferences.fetch(profiles, key, not_found)
    else
      nil -> {:error, not_found}
      {:error, _reason} = error -> error
    end
  end

  defp provider_version_live(_profiles, _id, nil, _profile), do: :ok

  defp provider_version_live(profiles, id, _version, profile) do
    profiles
    |> VersionedReferences.fetch({id, nil}, :contact_provider_profile_not_found)
    |> ArchivedProfile.live(profile)
  end

  defp fetch_transport_profile_ref(org, mission, ref) do
    org |> ProfileStore.load_transport_refs(mission, [ref]) |> transport_profile(ref)
  end

  defp transport_profile(profiles, ref) do
    key = VersionedReferences.key(ref, "transport_profile_id")
    VersionedReferences.fetch(profiles, key, :contact_transport_profile_not_found)
  end

  defp normalize_versioned_refs([], [], _id_key, _fetch_ref), do: {:ok, []}

  defp normalize_versioned_refs(ids, refs, id_key, fetch_ref)
       when is_list(ids) and is_list(refs) and is_binary(id_key) and is_function(fetch_ref, 1) do
    requested_refs =
      cond do
        refs != [] ->
          refs

        ids != [] ->
          refs_from_ids(ids, id_key)

        true ->
          []
      end

    with :ok <- validate_ref_list(requested_refs, id_key),
         :ok <- validate_ref_id_alignment(ids, requested_refs, id_key) do
      resolve_versioned_refs(requested_refs, id_key, fetch_ref)
    end
  end

  defp validate_ref_list(refs, id_key) when is_list(refs) and is_binary(id_key) do
    if Enum.all?(refs, fn ref ->
         is_binary(Map.get(ref, id_key)) and Map.get(ref, id_key) != "" and
           (is_nil(Map.get(ref, "version")) or
              (is_integer(Map.get(ref, "version")) and Map.get(ref, "version") > 0))
       end) do
      :ok
    else
      {:error, :invalid_contact_runtime_config_reference}
    end
  end

  defp validate_ref_id_alignment([], _refs, _id_key), do: :ok

  defp validate_ref_id_alignment(ids, refs, id_key)
       when is_list(ids) and is_list(refs) and is_binary(id_key) do
    if ids == ids_from_refs(refs, id_key) do
      :ok
    else
      {:error, :contact_runtime_config_reference_mismatch}
    end
  end

  defp resolve_versioned_refs(refs, id_key, fetch_ref)
       when is_list(refs) and is_binary(id_key) and is_function(fetch_ref, 1) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_ref.(ref) do
        {:ok, resource} ->
          {:cont, {:ok, acc ++ [versioned_ref_from_resource(resource, id_key)]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp versioned_ref_from_resource(resource, id_key) do
    %{id_key => versioned_ref_resource_id(resource, id_key), "version" => resource.version}
  end

  defp versioned_ref_resource_id(resource, "provider_profile_id"),
    do: resource.provider_profile_id

  defp versioned_ref_resource_id(resource, "transport_profile_id"),
    do: resource.transport_profile_id

  defp versioned_ref_resource_id(resource, "path_template_id"),
    do: resource.path_template_id

  defp ids_from_refs(refs, id_key) when is_list(refs) and is_binary(id_key) do
    Enum.map(refs, &Map.get(&1, id_key))
  end

  defp refs_from_ids(ids, id_key) when is_list(ids) and is_binary(id_key) do
    Enum.map(ids, &%{id_key => &1})
  end

  defp latest_versioned_row(mission_id, path_template_id) do
    PathTemplateRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.path_template_id == ^path_template_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp latest_versioned_row(organization_id, mission_id, path_template_id) do
    PathTemplateRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.path_template_id == ^path_template_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search) when is_binary(search) do
    pattern = "%" <> Listing.escape_like(search) <> "%"

    where(
      query,
      [row],
      ilike(row.path_template_id, ^pattern) or
        ilike(row.path_id, ^pattern) or
        ilike(row.provider_path_ref, ^pattern)
    )
  end

  defp build_next_version(%PathTemplate{} = path_template, attrs) when is_map(attrs) do
    provider_profile_ids =
      if Map.has_key?(attrs, :provider_profile_ids) do
        Map.get(attrs, :provider_profile_ids, [])
      else
        path_template.provider_profile_ids
      end

    provider_profile_refs =
      cond do
        Map.has_key?(attrs, :provider_profile_refs) ->
          Map.get(attrs, :provider_profile_refs, [])

        Map.has_key?(attrs, :provider_profile_ids) ->
          []

        true ->
          path_template.provider_profile_refs
      end

    transport_profile_ids =
      if Map.has_key?(attrs, :transport_profile_ids) do
        Map.get(attrs, :transport_profile_ids, [])
      else
        path_template.transport_profile_ids
      end

    transport_profile_refs =
      cond do
        Map.has_key?(attrs, :transport_profile_refs) ->
          Map.get(attrs, :transport_profile_refs, [])

        Map.has_key?(attrs, :transport_profile_ids) ->
          []

        true ->
          path_template.transport_profile_refs
      end

    {:ok,
     %PathTemplate{
       path_template
       | version: path_template.version + 1,
         lifecycle_state: :active,
         path_id: Map.get(attrs, :path_id, path_template.path_id),
         direction: Map.get(attrs, :direction, path_template.direction),
         selection_role: Map.get(attrs, :selection_role, path_template.selection_role),
         source_endpoint_ref: nil,
         provider_path_ref: Map.get(attrs, :provider_path_ref, path_template.provider_path_ref),
         provider_profile_ids: provider_profile_ids,
         provider_profile_refs: provider_profile_refs,
         transport_profile_ids: transport_profile_ids,
         transport_profile_refs: transport_profile_refs,
         metadata: Map.merge(path_template.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  defp put_organization_scope(%PathTemplate{} = path_template, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case path_template.organization_id do
      nil ->
        {:ok, %PathTemplate{path_template | organization_id: organization_id}}

      ^organization_id ->
        {:ok, path_template}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          path_template.mission_id}}
    end
  end
end
