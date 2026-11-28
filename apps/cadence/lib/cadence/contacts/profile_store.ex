defmodule Cadence.Contacts.ProfileStore do
  @moduledoc """
  Persists and versions provider and transport profiles.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.ListenClaims
  alias Cadence.Contacts.PathTemplateStore.VersionedReferences

  alias Cadence.Contacts.ProfileStore.{
    ListenAllowlist,
    ProviderProfileRow,
    TransportProfileRow,
    Versions
  }

  alias Cadence.Contacts.{ProviderProfile, TransportProfile}
  alias Cadence.Listing
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Persistence.{BulkInsert, BulkLookup}
  alias Cadence.Repo

  @spec persist_provider_profile(binary(), ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(organization_id, %ProviderProfile{} = provider_profile)
      when is_binary(organization_id) do
    # SAFETY: a listen host:port is one mission's (ListenClaims), and a listening profile names
    # the peers it accepts (#990, DECISIONS #115); both fail closed at save.
    with :ok <- listen_allowlist(provider_profile) do
      ListenClaims.guard(
        provider_profile.mission_id,
        claimed_configuration(provider_profile),
        fn ->
          persist_scoped_provider_profile(organization_id, provider_profile)
        end
      )
    end
  end

  defp persist_scoped_provider_profile(organization_id, provider_profile) do
    with {:ok, scoped_provider_profile} <-
           put_organization_scope(provider_profile, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_provider_profile.organization_id,
             scoped_provider_profile.mission_id
           ),
         {:ok, _row} <-
           Repo.insert(ProviderProfileRow.changeset(scoped_provider_profile),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :provider_profile_id, :version]
           ) do
      fetch_provider_profile_version(
        scoped_provider_profile.organization_id,
        scoped_provider_profile.mission_id,
        scoped_provider_profile.provider_profile_id,
        scoped_provider_profile.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_provider_profile(ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(%ProviderProfile{} = provider_profile) do
    with :ok <- listen_allowlist(provider_profile) do
      ListenClaims.guard(
        provider_profile.mission_id,
        claimed_configuration(provider_profile),
        fn ->
          insert_provider_profile(provider_profile)
        end
      )
    end
  end

  @doc "Whether an active listen-mode TCP provider profile names a usable allowlist (#990)."
  defdelegate listen_allowlist(profile), to: ListenAllowlist, as: :check

  # Only an active profile claims its listen endpoint; a tombstone releases it.
  defp claimed_configuration(%ProviderProfile{lifecycle_state: :active, configuration: config}),
    do: config

  defp claimed_configuration(%ProviderProfile{}), do: nil

  defp insert_provider_profile(provider_profile) do
    case Repo.insert(ProviderProfileRow.changeset(provider_profile),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :provider_profile_id, :version]
         ) do
      {:ok, %ProviderProfileRow{}} ->
        fetch_provider_profile_version(
          provider_profile.mission_id,
          provider_profile.provider_profile_id,
          provider_profile.version
        )

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_provider_profile(binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    case latest_versioned_row(
           ProviderProfileRow,
           mission_id,
           :provider_profile_id,
           provider_profile_id
         ) do
      nil ->
        {:error, :contact_provider_profile_not_found}

      %ProviderProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_provider_profile_not_found}

      %ProviderProfileRow{} = row ->
        {:ok, ProviderProfileRow.to_domain(row)}
    end
  end

  @spec fetch_provider_profile(binary(), binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    case latest_versioned_row(
           ProviderProfileRow,
           organization_id,
           mission_id,
           :provider_profile_id,
           provider_profile_id
         ) do
      nil ->
        {:error, :contact_provider_profile_not_found}

      %ProviderProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_provider_profile_not_found}

      %ProviderProfileRow{} = row ->
        {:ok, ProviderProfileRow.to_domain(row)}
    end
  end

  @spec fetch_provider_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(mission_id, provider_profile_id, version)
      when is_binary(mission_id) and is_binary(provider_profile_id) and is_integer(version) and
             version > 0 do
    case Repo.get_by(ProviderProfileRow,
           mission_id: mission_id,
           provider_profile_id: provider_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_provider_profile_not_found}
      %ProviderProfileRow{} = row -> {:ok, ProviderProfileRow.to_domain(row)}
    end
  end

  @spec fetch_provider_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(organization_id, mission_id, provider_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_integer(version) and version > 0 do
    case Repo.get_by(ProviderProfileRow,
           organization_id: organization_id,
           mission_id: mission_id,
           provider_profile_id: provider_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_provider_profile_not_found}
      %ProviderProfileRow{} = row -> {:ok, ProviderProfileRow.to_domain(row)}
    end
  end

  @doc "Latest non-deleted mission provider profiles keyed by their IDs."
  def fetch_provider_profiles(organization_id, mission_id, ids) do
    ProviderProfileRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> distinct([row], row.provider_profile_id)
    |> order_by([row], desc: row.version)
    |> BulkLookup.by_id(:provider_profile_id, ids)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Map.new(&{&1.provider_profile_id, ProviderProfileRow.to_domain(&1)})
  end

  @doc false
  def load_provider_refs(org, mission, refs) do
    keys = Enum.map(refs, &VersionedReferences.key(&1, "provider_profile_id"))

    ProviderProfileRow
    |> VersionedReferences.in_scope(org, mission)
    |> VersionedReferences.load(
      :provider_profile_id,
      keys,
      Enum.map(keys, &elem(&1, 0)),
      &ProviderProfileRow.to_domain/1
    )
  end

  @doc false
  def load_transport_refs(org, mission, refs) do
    keys = Enum.map(refs, &VersionedReferences.key(&1, "transport_profile_id"))
    latest = for {id, nil} <- keys, do: id

    TransportProfileRow
    |> VersionedReferences.in_scope(org, mission)
    |> VersionedReferences.load(
      :transport_profile_id,
      keys,
      latest,
      &TransportProfileRow.to_domain/1
    )
  end

  @doc "Returns one bounded page of active latest provider-profile versions."
  @spec list_provider_profiles_page(binary(), binary(), keyword()) :: Listing.Page.t()
  def list_provider_profiles_page(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    page_of_latest_profiles(
      ProviderProfileRow,
      :provider_profile_id,
      organization_id,
      mission_id,
      opts,
      &ProviderProfileRow.to_domain/1
    )
  end

  @spec list_provider_profile_versions(binary(), binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    ProviderProfileRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.provider_profile_id == ^provider_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ProviderProfileRow.to_domain/1)
  end

  @doc """
  Other missions' provider profiles (any organization) that mention listen port `port`, each at
  its LATEST version: `[%{lifecycle_state, configuration}]` for `Cadence.Comms.ListenClaims`,
  which decides whether one still claims the port. A server-internal read: callers mustn't show
  another mission's profile to a user.
  """
  @spec latest_provider_profiles_on_port(binary(), pos_integer()) :: [map()]
  def latest_provider_profiles_on_port(mission_id, port)
      when is_binary(mission_id) and is_integer(port) do
    port_text = Integer.to_string(port)

    candidates =
      from(row in ProviderProfileRow,
        where:
          row.mission_id != ^mission_id and
            fragment("(?->'value'->>'port') = ?", row.configuration, ^port_text),
        select: %{mission_id: row.mission_id, provider_profile_id: row.provider_profile_id},
        distinct: true
      )

    from(row in ProviderProfileRow,
      join: candidate in subquery(candidates),
      on:
        candidate.mission_id == row.mission_id and
          candidate.provider_profile_id == row.provider_profile_id,
      distinct: [row.mission_id, row.provider_profile_id],
      order_by: [row.mission_id, row.provider_profile_id, desc: row.version],
      select: %{lifecycle_state: row.lifecycle_state, configuration: row.configuration}
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | configuration: JsonDocument.unwrap_value(&1.configuration)})
  end

  @spec version_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def version_provider_profile(organization_id, mission_id, provider_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(attrs) do
    with {:ok, %ProviderProfile{} = current_provider_profile} <-
           fetch_provider_profile(organization_id, mission_id, provider_profile_id),
         {:ok, %ProviderProfile{} = next_provider_profile} <-
           Versions.next_provider_profile(current_provider_profile, attrs) do
      persist_provider_profile(organization_id, next_provider_profile)
    end
  end

  @spec delete_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def delete_provider_profile(
        organization_id,
        mission_id,
        provider_profile_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(metadata_patch) do
    with {:ok, %ProviderProfile{} = current_provider_profile} <-
           fetch_provider_profile(organization_id, mission_id, provider_profile_id) do
      tombstone =
        %ProviderProfile{
          current_provider_profile
          | version: current_provider_profile.version + 1,
            lifecycle_state: :deleted,
            metadata:
              current_provider_profile.metadata
              |> Map.merge(metadata_patch)
              |> Map.put("deleted_at", DateTime.utc_now())
        }

      persist_provider_profile(organization_id, tombstone)
    end
  end

  @spec persist_transport_profile(binary(), TransportProfile.t()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def persist_transport_profile(organization_id, %TransportProfile{} = transport_profile)
      when is_binary(organization_id) do
    with {:ok, scoped_transport_profile} <-
           put_organization_scope(transport_profile, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_transport_profile.organization_id,
             scoped_transport_profile.mission_id
           ),
         {:ok, _row} <-
           Repo.insert(TransportProfileRow.changeset(scoped_transport_profile),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :transport_profile_id, :version]
           ) do
      fetch_transport_profile_version(
        scoped_transport_profile.organization_id,
        scoped_transport_profile.mission_id,
        scoped_transport_profile.transport_profile_id,
        scoped_transport_profile.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_transport_profile(TransportProfile.t()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def persist_transport_profile(%TransportProfile{} = transport_profile) do
    case Repo.insert(TransportProfileRow.changeset(transport_profile),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :transport_profile_id, :version]
         ) do
      {:ok, %TransportProfileRow{}} ->
        fetch_transport_profile_version(
          transport_profile.mission_id,
          transport_profile.transport_profile_id,
          transport_profile.version
        )

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def persist_route_gateways(profiles) do
    BulkInsert.changesets(
      TransportProfileRow,
      Stream.map(profiles, &TransportProfileRow.changeset/1),
      on_conflict: :nothing,
      conflict_target: [:mission_id, :transport_profile_id, :version]
    )
  end

  @spec fetch_transport_profile(binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    case latest_versioned_row(
           TransportProfileRow,
           mission_id,
           :transport_profile_id,
           transport_profile_id
         ) do
      nil ->
        {:error, :contact_transport_profile_not_found}

      %TransportProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_transport_profile_not_found}

      %TransportProfileRow{} = row ->
        {:ok, TransportProfileRow.to_domain(row)}
    end
  end

  @spec fetch_transport_profile(binary(), binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    case latest_versioned_row(
           TransportProfileRow,
           organization_id,
           mission_id,
           :transport_profile_id,
           transport_profile_id
         ) do
      nil ->
        {:error, :contact_transport_profile_not_found}

      %TransportProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_transport_profile_not_found}

      %TransportProfileRow{} = row ->
        {:ok, TransportProfileRow.to_domain(row)}
    end
  end

  @spec fetch_transport_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(mission_id, transport_profile_id, version)
      when is_binary(mission_id) and is_binary(transport_profile_id) and is_integer(version) and
             version > 0 do
    case Repo.get_by(TransportProfileRow,
           mission_id: mission_id,
           transport_profile_id: transport_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_transport_profile_not_found}
      %TransportProfileRow{} = row -> {:ok, TransportProfileRow.to_domain(row)}
    end
  end

  @spec fetch_transport_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(organization_id, mission_id, transport_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_integer(version) and version > 0 do
    case Repo.get_by(TransportProfileRow,
           organization_id: organization_id,
           mission_id: mission_id,
           transport_profile_id: transport_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_transport_profile_not_found}
      %TransportProfileRow{} = row -> {:ok, TransportProfileRow.to_domain(row)}
    end
  end

  @spec list_transport_profiles(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    TransportProfileRow
    |> latest_versioned_rows(organization_id, mission_id, :transport_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&TransportProfileRow.to_domain/1)
  end

  @doc "Returns one bounded page of active latest transport-profile versions."
  @spec list_transport_profiles_page(binary(), binary(), keyword()) :: Listing.Page.t()
  def list_transport_profiles_page(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    page_of_latest_profiles(
      TransportProfileRow,
      :transport_profile_id,
      organization_id,
      mission_id,
      opts,
      &TransportProfileRow.to_domain/1
    )
  end

  @spec list_transport_profile_versions(binary(), binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    TransportProfileRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_profile_id == ^transport_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&TransportProfileRow.to_domain/1)
  end

  @spec version_transport_profile(binary(), binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def version_transport_profile(organization_id, mission_id, transport_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_map(attrs) do
    with {:ok, %TransportProfile{} = current_transport_profile} <-
           fetch_transport_profile(organization_id, mission_id, transport_profile_id),
         {:ok, %TransportProfile{} = next_transport_profile} <-
           Versions.next_transport_profile(current_transport_profile, attrs) do
      persist_transport_profile(organization_id, next_transport_profile)
    end
  end

  @spec delete_transport_profile(binary(), binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def delete_transport_profile(
        organization_id,
        mission_id,
        transport_profile_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_map(metadata_patch) do
    with {:ok, %TransportProfile{} = current_transport_profile} <-
           fetch_transport_profile(organization_id, mission_id, transport_profile_id) do
      tombstone =
        %TransportProfile{
          current_transport_profile
          | version: current_transport_profile.version + 1,
            lifecycle_state: :deleted,
            metadata:
              current_transport_profile.metadata
              |> Map.merge(metadata_patch)
              |> Map.put("deleted_at", DateTime.utc_now())
        }

      persist_transport_profile(organization_id, tombstone)
    end
  end

  defp latest_versioned_row(schema, mission_id, definition_id_field, definition_id) do
    schema
    |> where(
      [definition_row],
      field(definition_row, :mission_id) == ^mission_id and
        field(definition_row, ^definition_id_field) == ^definition_id
    )
    |> order_by([definition_row], desc: field(definition_row, :version))
    |> limit(1)
    |> Repo.one()
  end

  defp latest_versioned_row(
         schema,
         organization_id,
         mission_id,
         definition_id_field,
         definition_id
       ) do
    schema
    |> where(
      [definition_row],
      field(definition_row, :organization_id) == ^organization_id and
        field(definition_row, :mission_id) == ^mission_id and
        field(definition_row, ^definition_id_field) == ^definition_id
    )
    |> order_by([definition_row], desc: field(definition_row, :version))
    |> limit(1)
    |> Repo.one()
  end

  defp latest_versioned_rows(schema, organization_id, mission_id, definition_id_field) do
    schema
    |> where(
      [definition_row],
      field(definition_row, :organization_id) == ^organization_id and
        field(definition_row, :mission_id) == ^mission_id
    )
    |> order_by([definition_row],
      asc: field(definition_row, ^definition_id_field),
      desc: field(definition_row, :version)
    )
    |> Repo.all()
    |> latest_rows(definition_id_field)
  end

  defp page_of_latest_profiles(schema, id_field, organization_id, mission_id, opts, converter) do
    %{page: page, page_size: page_size, offset: offset} = Listing.page_opts(opts)

    latest =
      schema
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )
      |> distinct([row], field(row, ^id_field))
      |> order_by([row], asc: field(row, ^id_field), desc: row.version)

    filtered =
      latest
      |> subquery()
      |> where([row], row.lifecycle_state != "deleted")
      |> apply_profile_search(Keyword.get(opts, :search), id_field)

    items =
      filtered
      |> order_by([row], asc: field(row, ^id_field))
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(converter)

    %Listing.Page{
      items: items,
      total_count: Repo.aggregate(filtered, :count),
      page: page,
      page_size: page_size
    }
  end

  defp apply_profile_search(query, nil, _id_field), do: query
  defp apply_profile_search(query, "", _id_field), do: query

  defp apply_profile_search(query, search, id_field) when is_binary(search) do
    pattern = "%" <> Listing.escape_like(search) <> "%"
    where(query, [row], ilike(field(row, ^id_field), ^pattern))
  end

  defp latest_rows(rows, definition_id_field) do
    rows
    |> Enum.reduce(%{}, fn definition_row, acc ->
      definition_id = Map.fetch!(definition_row, definition_id_field)
      Map.put_new(acc, definition_id, definition_row)
    end)
    |> Map.values()
  end

  defp put_organization_scope(%module{} = profile, organization_id)
       when module in [ProviderProfile, TransportProfile] and is_binary(organization_id) and
              organization_id != "" do
    case profile.organization_id do
      nil ->
        {:ok, %{profile | organization_id: organization_id}}

      ^organization_id ->
        {:ok, profile}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          profile.mission_id}}
    end
  end
end
