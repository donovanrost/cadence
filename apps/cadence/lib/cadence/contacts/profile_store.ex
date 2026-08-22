defmodule Cadence.Contacts.ProfileStore do
  @moduledoc """
  Persists and versions provider and transport profiles.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Contacts.ProfileStore.{ProviderProfileRow, TransportProfileRow}
  alias Cadence.Contacts.{ProviderProfile, TransportProfile}
  alias Cadence.Missions

  alias Cadence.Repo

  @spec persist_provider_profile(binary(), ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(organization_id, %ProviderProfile{} = provider_profile)
      when is_binary(organization_id) do
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

  @spec list_provider_profiles(binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(mission_id) when is_binary(mission_id) do
    ProviderProfileRow
    |> latest_versioned_rows(mission_id, :provider_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ProviderProfileRow.to_domain/1)
  end

  @spec list_provider_profiles(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ProviderProfileRow
    |> latest_versioned_rows(organization_id, mission_id, :provider_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ProviderProfileRow.to_domain/1)
  end

  @spec list_provider_profile_versions(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    ProviderProfileRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.provider_profile_id == ^provider_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ProviderProfileRow.to_domain/1)
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

  @spec version_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def version_provider_profile(organization_id, mission_id, provider_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(attrs) do
    with {:ok, %ProviderProfile{} = current_provider_profile} <-
           fetch_provider_profile(organization_id, mission_id, provider_profile_id),
         {:ok, %ProviderProfile{} = next_provider_profile} <-
           build_next_provider_profile_version(current_provider_profile, attrs) do
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

  @spec list_transport_profiles(binary()) :: [TransportProfile.t()]
  def list_transport_profiles(mission_id) when is_binary(mission_id) do
    TransportProfileRow
    |> latest_versioned_rows(mission_id, :transport_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&TransportProfileRow.to_domain/1)
  end

  @spec list_transport_profiles(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    TransportProfileRow
    |> latest_versioned_rows(organization_id, mission_id, :transport_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&TransportProfileRow.to_domain/1)
  end

  @spec list_transport_profile_versions(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    TransportProfileRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.transport_profile_id == ^transport_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&TransportProfileRow.to_domain/1)
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
           build_next_transport_profile_version(current_transport_profile, attrs) do
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

  defp latest_versioned_rows(schema, mission_id, definition_id_field) do
    schema
    |> where([definition_row], field(definition_row, :mission_id) == ^mission_id)
    |> order_by([definition_row],
      asc: field(definition_row, ^definition_id_field),
      desc: field(definition_row, :version)
    )
    |> Repo.all()
    |> latest_rows(definition_id_field)
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

  defp latest_rows(rows, definition_id_field) do
    rows
    |> Enum.reduce(%{}, fn definition_row, acc ->
      definition_id = Map.fetch!(definition_row, definition_id_field)
      Map.put_new(acc, definition_id, definition_row)
    end)
    |> Map.values()
  end

  defp build_next_provider_profile_version(%ProviderProfile{} = provider_profile, attrs) do
    {:ok,
     %ProviderProfile{
       provider_profile
       | version: provider_profile.version + 1,
         lifecycle_state: :active,
         adapter_key: Map.get(attrs, :adapter_key, provider_profile.adapter_key),
         configuration: Map.get(attrs, :configuration, provider_profile.configuration),
         metadata: Map.merge(provider_profile.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  defp build_next_transport_profile_version(%TransportProfile{} = transport_profile, attrs) do
    {:ok,
     %TransportProfile{
       transport_profile
       | version: transport_profile.version + 1,
         lifecycle_state: :active,
         family_key: Map.get(attrs, :family_key, transport_profile.family_key),
         target_scope: Map.get(attrs, :target_scope, transport_profile.target_scope),
         configuration: Map.get(attrs, :configuration, transport_profile.configuration),
         metadata: Map.merge(transport_profile.metadata, Map.get(attrs, :metadata, %{}))
     }}
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
