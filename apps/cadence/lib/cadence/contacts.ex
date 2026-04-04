defmodule Cadence.Contacts do
  @moduledoc """
  Persistence and lifecycle boundary for scheduled and realized contacts.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Contacts.{
    ContactAction,
    Path,
    PathTemplate,
    ProviderBinding,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    TransportBinding,
    TransportProfile
  }

  alias Cadence.Missions
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection

  alias Cadence.Persistence.Schemas.{
    ContactActionRow,
    ContactPathTemplateRow,
    ContactProviderProfileRow,
    ContactTransportProfileRow,
    RealizedContactRow,
    ScheduledContactRow
  }

  alias Cadence.Repo
  alias Cadence.Runtime

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
           Repo.insert(ContactProviderProfileRow.changeset(scoped_provider_profile),
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
    case Repo.insert(ContactProviderProfileRow.changeset(provider_profile),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :provider_profile_id, :version]
         ) do
      {:ok, %ContactProviderProfileRow{}} ->
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
           ContactProviderProfileRow,
           mission_id,
           :provider_profile_id,
           provider_profile_id
         ) do
      nil ->
        {:error, :contact_provider_profile_not_found}

      %ContactProviderProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_provider_profile_not_found}

      %ContactProviderProfileRow{} = row ->
        {:ok, ContactProviderProfileRow.to_domain(row)}
    end
  end

  @spec fetch_provider_profile(binary(), binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    case latest_versioned_row(
           ContactProviderProfileRow,
           organization_id,
           mission_id,
           :provider_profile_id,
           provider_profile_id
         ) do
      nil ->
        {:error, :contact_provider_profile_not_found}

      %ContactProviderProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_provider_profile_not_found}

      %ContactProviderProfileRow{} = row ->
        {:ok, ContactProviderProfileRow.to_domain(row)}
    end
  end

  @spec fetch_provider_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(mission_id, provider_profile_id, version)
      when is_binary(mission_id) and is_binary(provider_profile_id) and is_integer(version) and
             version > 0 do
    case Repo.get_by(ContactProviderProfileRow,
           mission_id: mission_id,
           provider_profile_id: provider_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_provider_profile_not_found}
      %ContactProviderProfileRow{} = row -> {:ok, ContactProviderProfileRow.to_domain(row)}
    end
  end

  @spec fetch_provider_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(organization_id, mission_id, provider_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_integer(version) and version > 0 do
    case Repo.get_by(ContactProviderProfileRow,
           organization_id: organization_id,
           mission_id: mission_id,
           provider_profile_id: provider_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_provider_profile_not_found}
      %ContactProviderProfileRow{} = row -> {:ok, ContactProviderProfileRow.to_domain(row)}
    end
  end

  @spec list_provider_profiles(binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(mission_id) when is_binary(mission_id) do
    ContactProviderProfileRow
    |> latest_versioned_rows(mission_id, :provider_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ContactProviderProfileRow.to_domain/1)
  end

  @spec list_provider_profiles(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactProviderProfileRow
    |> latest_versioned_rows(organization_id, mission_id, :provider_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ContactProviderProfileRow.to_domain/1)
  end

  @spec list_provider_profile_versions(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    ContactProviderProfileRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.provider_profile_id == ^provider_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ContactProviderProfileRow.to_domain/1)
  end

  @spec list_provider_profile_versions(binary(), binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    ContactProviderProfileRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.provider_profile_id == ^provider_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ContactProviderProfileRow.to_domain/1)
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
           Repo.insert(ContactTransportProfileRow.changeset(scoped_transport_profile),
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
    case Repo.insert(ContactTransportProfileRow.changeset(transport_profile),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :transport_profile_id, :version]
         ) do
      {:ok, %ContactTransportProfileRow{}} ->
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
           ContactTransportProfileRow,
           mission_id,
           :transport_profile_id,
           transport_profile_id
         ) do
      nil ->
        {:error, :contact_transport_profile_not_found}

      %ContactTransportProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_transport_profile_not_found}

      %ContactTransportProfileRow{} = row ->
        {:ok, ContactTransportProfileRow.to_domain(row)}
    end
  end

  @spec fetch_transport_profile(binary(), binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    case latest_versioned_row(
           ContactTransportProfileRow,
           organization_id,
           mission_id,
           :transport_profile_id,
           transport_profile_id
         ) do
      nil ->
        {:error, :contact_transport_profile_not_found}

      %ContactTransportProfileRow{lifecycle_state: "deleted"} ->
        {:error, :contact_transport_profile_not_found}

      %ContactTransportProfileRow{} = row ->
        {:ok, ContactTransportProfileRow.to_domain(row)}
    end
  end

  @spec fetch_transport_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(mission_id, transport_profile_id, version)
      when is_binary(mission_id) and is_binary(transport_profile_id) and is_integer(version) and
             version > 0 do
    case Repo.get_by(ContactTransportProfileRow,
           mission_id: mission_id,
           transport_profile_id: transport_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_transport_profile_not_found}
      %ContactTransportProfileRow{} = row -> {:ok, ContactTransportProfileRow.to_domain(row)}
    end
  end

  @spec fetch_transport_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(organization_id, mission_id, transport_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_integer(version) and version > 0 do
    case Repo.get_by(ContactTransportProfileRow,
           organization_id: organization_id,
           mission_id: mission_id,
           transport_profile_id: transport_profile_id,
           version: version
         ) do
      nil -> {:error, :contact_transport_profile_not_found}
      %ContactTransportProfileRow{} = row -> {:ok, ContactTransportProfileRow.to_domain(row)}
    end
  end

  @spec list_transport_profiles(binary()) :: [TransportProfile.t()]
  def list_transport_profiles(mission_id) when is_binary(mission_id) do
    ContactTransportProfileRow
    |> latest_versioned_rows(mission_id, :transport_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ContactTransportProfileRow.to_domain/1)
  end

  @spec list_transport_profiles(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactTransportProfileRow
    |> latest_versioned_rows(organization_id, mission_id, :transport_profile_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ContactTransportProfileRow.to_domain/1)
  end

  @spec list_transport_profile_versions(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    ContactTransportProfileRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.transport_profile_id == ^transport_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ContactTransportProfileRow.to_domain/1)
  end

  @spec list_transport_profile_versions(binary(), binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    ContactTransportProfileRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_profile_id == ^transport_profile_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ContactTransportProfileRow.to_domain/1)
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

  @spec persist_path_template(binary(), PathTemplate.t()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def persist_path_template(organization_id, %PathTemplate{} = path_template)
      when is_binary(organization_id) do
    with {:ok, scoped_path_template} <- put_organization_scope(path_template, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_path_template.organization_id,
             scoped_path_template.mission_id
           ),
         {:ok, prepared_path_template} <- prepare_path_template(scoped_path_template),
         :ok <- validate_path_template(prepared_path_template),
         {:ok, _row} <-
           Repo.insert(ContactPathTemplateRow.changeset(prepared_path_template),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :path_template_id, :version]
           ) do
      fetch_path_template_version(
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

  @spec persist_path_template(PathTemplate.t()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def persist_path_template(%PathTemplate{} = path_template) do
    with {:ok, prepared_path_template} <- prepare_path_template(path_template),
         :ok <- validate_path_template(prepared_path_template) do
      case Repo.insert(ContactPathTemplateRow.changeset(prepared_path_template),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :path_template_id, :version]
           ) do
        {:ok, %ContactPathTemplateRow{} = row} ->
          {:ok, ContactPathTemplateRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_path_template(binary(), binary()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    case latest_versioned_row(
           ContactPathTemplateRow,
           mission_id,
           :path_template_id,
           path_template_id
         ) do
      nil ->
        {:error, :contact_path_template_not_found}

      %ContactPathTemplateRow{lifecycle_state: "deleted"} ->
        {:error, :contact_path_template_not_found}

      %ContactPathTemplateRow{} = row ->
        {:ok, ContactPathTemplateRow.to_domain(row)}
    end
  end

  @spec fetch_path_template(binary(), binary(), binary()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) do
    case latest_versioned_row(
           ContactPathTemplateRow,
           organization_id,
           mission_id,
           :path_template_id,
           path_template_id
         ) do
      nil ->
        {:error, :contact_path_template_not_found}

      %ContactPathTemplateRow{lifecycle_state: "deleted"} ->
        {:error, :contact_path_template_not_found}

      %ContactPathTemplateRow{} = row ->
        {:ok, ContactPathTemplateRow.to_domain(row)}
    end
  end

  @spec fetch_path_template_version(binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template_version(mission_id, path_template_id, version)
      when is_binary(mission_id) and is_binary(path_template_id) and is_integer(version) and
             version > 0 do
    case Repo.get_by(ContactPathTemplateRow,
           mission_id: mission_id,
           path_template_id: path_template_id,
           version: version
         ) do
      nil -> {:error, :contact_path_template_not_found}
      %ContactPathTemplateRow{} = row -> {:ok, ContactPathTemplateRow.to_domain(row)}
    end
  end

  @spec fetch_path_template_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template_version(organization_id, mission_id, path_template_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_integer(version) and version > 0 do
    case Repo.get_by(ContactPathTemplateRow,
           organization_id: organization_id,
           mission_id: mission_id,
           path_template_id: path_template_id,
           version: version
         ) do
      nil -> {:error, :contact_path_template_not_found}
      %ContactPathTemplateRow{} = row -> {:ok, ContactPathTemplateRow.to_domain(row)}
    end
  end

  @spec list_path_templates(binary()) :: [PathTemplate.t()]
  def list_path_templates(mission_id) when is_binary(mission_id) do
    ContactPathTemplateRow
    |> latest_versioned_rows(mission_id, :path_template_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ContactPathTemplateRow.to_domain/1)
  end

  @spec list_path_templates(binary(), binary()) :: [PathTemplate.t()]
  def list_path_templates(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactPathTemplateRow
    |> latest_versioned_rows(organization_id, mission_id, :path_template_id)
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.map(&ContactPathTemplateRow.to_domain/1)
  end

  @spec list_path_template_versions(binary(), binary()) :: [PathTemplate.t()]
  def list_path_template_versions(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    ContactPathTemplateRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.path_template_id == ^path_template_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ContactPathTemplateRow.to_domain/1)
  end

  @spec list_path_template_versions(binary(), binary(), binary()) :: [PathTemplate.t()]
  def list_path_template_versions(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(path_template_id) do
    ContactPathTemplateRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.path_template_id == ^path_template_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&ContactPathTemplateRow.to_domain/1)
  end

  @spec version_path_template(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def version_path_template(organization_id, mission_id, path_template_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_map(attrs) do
    with {:ok, %PathTemplate{} = current_path_template} <-
           fetch_path_template(organization_id, mission_id, path_template_id),
         {:ok, %PathTemplate{} = next_path_template} <-
           build_next_path_template_version(current_path_template, attrs) do
      persist_path_template(organization_id, next_path_template)
    end
  end

  @spec delete_path_template(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def delete_path_template(organization_id, mission_id, path_template_id, metadata_patch \\ %{})
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_map(metadata_patch) do
    with {:ok, %PathTemplate{} = current_path_template} <-
           fetch_path_template(organization_id, mission_id, path_template_id) do
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

      persist_path_template(organization_id, tombstone)
    end
  end

  @spec persist_scheduled_contact(ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    with {:ok, prepared_scheduled_contact} <- prepare_scheduled_contact(scheduled_contact),
         :ok <- validate_scheduled_contact(prepared_scheduled_contact) do
      case Repo.insert(ScheduledContactRow.changeset(prepared_scheduled_contact),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :scheduled_contact_id]
           ) do
        {:ok, %ScheduledContactRow{} = row} ->
          {:ok, ScheduledContactRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec persist_scheduled_contact(binary(), ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled_contact(organization_id, %ScheduledContact{} = scheduled_contact)
      when is_binary(organization_id) do
    with {:ok, scoped_scheduled_contact} <-
           put_organization_scope(scheduled_contact, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_scheduled_contact.organization_id,
             scoped_scheduled_contact.mission_id
           ) do
      persist_scheduled_contact(scoped_scheduled_contact)
    end
  end

  @spec fetch_scheduled_contact(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(mission_id, scheduled_contact_id)
      when is_binary(mission_id) and is_binary(scheduled_contact_id) do
    case Repo.get_by(ScheduledContactRow,
           mission_id: mission_id,
           scheduled_contact_id: scheduled_contact_id
         ) do
      nil -> {:error, :scheduled_contact_not_found}
      %ScheduledContactRow{} = row -> {:ok, ScheduledContactRow.to_domain(row)}
    end
  end

  @spec fetch_scheduled_contact(binary(), binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) do
    case Repo.get_by(ScheduledContactRow,
           organization_id: organization_id,
           mission_id: mission_id,
           scheduled_contact_id: scheduled_contact_id
         ) do
      nil -> {:error, :scheduled_contact_not_found}
      %ScheduledContactRow{} = row -> {:ok, ScheduledContactRow.to_domain(row)}
    end
  end

  @spec list_scheduled_contacts(binary()) :: [ScheduledContact.t()]
  def list_scheduled_contacts(mission_id) when is_binary(mission_id) do
    ScheduledContactRow
    |> where([row], row.mission_id == ^mission_id)
    |> order_by([row], asc: row.starts_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  @spec list_scheduled_contacts(binary(), binary()) :: [ScheduledContact.t()]
  def list_scheduled_contacts(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ScheduledContactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.starts_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  @spec list_contact_actions(binary(), keyword()) :: [ContactAction.t()]
  def list_contact_actions(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    ContactActionRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter_contact_actions(opts)
    |> order_by([row], asc: row.occurred_at, asc: row.contact_action_id)
    |> Repo.all()
    |> Enum.map(&ContactActionRow.to_domain/1)
  end

  @spec list_contact_actions(binary(), binary(), keyword()) :: [ContactAction.t()]
  def list_contact_actions(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ContactActionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_contact_actions(opts)
    |> order_by([row], asc: row.occurred_at, asc: row.contact_action_id)
    |> Repo.all()
    |> Enum.map(&ContactActionRow.to_domain/1)
  end

  @spec persist_realized_contact(RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized_contact(%RealizedContact{} = realized_contact) do
    with :ok <- validate_realized_contact(realized_contact) do
      case Repo.insert(RealizedContactRow.changeset(realized_contact),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :realized_contact_id]
           ) do
        {:ok, %RealizedContactRow{} = row} ->
          {:ok, RealizedContactRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec persist_realized_contact(binary(), RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized_contact(organization_id, %RealizedContact{} = realized_contact)
      when is_binary(organization_id) do
    with {:ok, scoped_realized_contact} <-
           put_organization_scope(realized_contact, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_realized_contact.organization_id,
             scoped_realized_contact.mission_id
           ) do
      persist_realized_contact(scoped_realized_contact)
    end
  end

  @spec fetch_realized_contact(binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    case Repo.get_by(RealizedContactRow,
           mission_id: mission_id,
           realized_contact_id: realized_contact_id
         ) do
      nil -> {:error, :realized_contact_not_found}
      %RealizedContactRow{} = row -> {:ok, RealizedContactRow.to_domain(row)}
    end
  end

  @spec fetch_realized_contact(binary(), binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    case Repo.get_by(RealizedContactRow,
           organization_id: organization_id,
           mission_id: mission_id,
           realized_contact_id: realized_contact_id
         ) do
      nil -> {:error, :realized_contact_not_found}
      %RealizedContactRow{} = row -> {:ok, RealizedContactRow.to_domain(row)}
    end
  end

  @spec list_realized_contacts(binary()) :: [RealizedContact.t()]
  def list_realized_contacts(mission_id) when is_binary(mission_id) do
    RealizedContactRow
    |> where([row], row.mission_id == ^mission_id)
    |> order_by([row], asc: row.realized_at, asc: row.realized_contact_id)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  @spec list_realized_contacts(binary(), binary()) :: [RealizedContact.t()]
  def list_realized_contacts(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    RealizedContactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.realized_at, asc: row.realized_contact_id)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  @spec reconcile(DateTime.t()) :: {:ok, map()}
  def reconcile(%DateTime{} = reference_time) do
    {expired_scheduled_contact_ids, expiration_errors} =
      list_expired_scheduled_contacts(reference_time)
      |> collect_reconcile_results(&expire_scheduled_contact_for_reconcile(&1, reference_time))

    {completed_scheduled_contact_ids, scheduled_completion_errors} =
      list_completed_scheduled_contacts(reference_time)
      |> collect_reconcile_results(&complete_scheduled_contact_for_reconcile(&1, reference_time))

    {realized_scheduled_contact_ids, realization_errors} =
      list_due_scheduled_contacts(reference_time)
      |> collect_reconcile_results(&realize_scheduled_contact_for_reconcile(&1, reference_time))

    {completed_realized_contact_ids, completion_errors} =
      list_expired_active_realized_contacts(reference_time)
      |> collect_reconcile_results(&complete_realized_contact_for_reconcile(&1, reference_time))

    {restarted_realized_contact_ids, restart_errors} =
      list_active_realized_contacts()
      |> collect_reconcile_results(&restart_realized_contact_for_reconcile(&1, reference_time))

    {:ok,
     %{
       reference_time: reference_time,
       expired_scheduled_contact_ids: Enum.reverse(expired_scheduled_contact_ids),
       completed_scheduled_contact_ids: Enum.reverse(completed_scheduled_contact_ids),
       realized_scheduled_contact_ids: Enum.reverse(realized_scheduled_contact_ids),
       completed_realized_contact_ids: Enum.reverse(completed_realized_contact_ids),
       restarted_realized_contact_ids: Enum.reverse(restarted_realized_contact_ids),
       errors:
         Enum.reverse(expiration_errors) ++
           Enum.reverse(scheduled_completion_errors) ++
           Enum.reverse(realization_errors) ++
           Enum.reverse(completion_errors) ++ Enum.reverse(restart_errors)
     }}
  end

  defp collect_reconcile_results(contacts, action)
       when is_list(contacts) and is_function(action, 1) do
    Enum.reduce(contacts, {[], []}, fn contact, {ids, errors} ->
      case action.(contact) do
        {:ok, contact_id} -> {[contact_id | ids], errors}
        :skip -> {ids, errors}
        {:error, error} -> {ids, [error | errors]}
      end
    end)
  end

  defp expire_scheduled_contact_for_reconcile(
         %ScheduledContact{} = scheduled_contact,
         reference_time
       ) do
    case expire_scheduled_contact(scheduled_contact, %{
           expired_at: reference_time,
           expired_from_schedule: true
         }) do
      {:ok, %ScheduledContact{} = expired_scheduled_contact} ->
        {:ok, expired_scheduled_contact.scheduled_contact_id}

      {:error, reason} ->
        {:error, reconcile_error(:scheduled_contact_expiration, scheduled_contact, reason)}
    end
  end

  defp complete_scheduled_contact_for_reconcile(
         %ScheduledContact{} = scheduled_contact,
         reference_time
       ) do
    case complete_scheduled_contact(scheduled_contact, %{
           completed_at: reference_time,
           completed_from_schedule: true
         }) do
      {:ok, %ScheduledContact{} = completed_scheduled_contact} ->
        {:ok, completed_scheduled_contact.scheduled_contact_id}

      {:error, reason} ->
        {:error, reconcile_error(:scheduled_contact_completion, scheduled_contact, reason)}
    end
  end

  defp realize_scheduled_contact_for_reconcile(
         %ScheduledContact{} = scheduled_contact,
         reference_time
       ) do
    case realize_scheduled_contact(
           scheduled_contact.mission_id,
           scheduled_contact.scheduled_contact_id,
           clock_mode: :live,
           initial_time: reference_time,
           realized_at: reference_time,
           transition_time: reference_time,
           metadata: %{scheduler_realized?: true}
         ) do
      {:ok, %RealizedContact{} = realized_contact} ->
        {:ok, realized_contact.realized_contact_id}

      {:error, :scheduled_contact_already_realized} ->
        :skip

      {:error, reason} ->
        {:error, reconcile_error(:scheduled_contact_realization, scheduled_contact, reason)}
    end
  end

  defp complete_realized_contact_for_reconcile(
         %RealizedContact{} = realized_contact,
         reference_time
       ) do
    case complete_realized_contact(realized_contact, %{
           completed_at: reference_time,
           completed_from_schedule: true
         }) do
      {:ok, %RealizedContact{} = completed_realized_contact} ->
        {:ok, completed_realized_contact.realized_contact_id}

      {:error, reason} ->
        {:error, reconcile_error(:realized_contact_completion, realized_contact, reason)}
    end
  end

  defp restart_realized_contact_for_reconcile(
         %RealizedContact{} = realized_contact,
         reference_time
       ) do
    if Runtime.realized_contact_running?(
         realized_contact.mission_id,
         realized_contact.realized_contact_id
       ) do
      :skip
    else
      case start_runtime_and_mark_active(realized_contact, %{
             reconciled_at: reference_time,
             started_at: reference_time
           }) do
        {:ok, _pid} ->
          {:ok, realized_contact.realized_contact_id}

        {:error, reason} ->
          {:error, reconcile_error(:realized_contact_restart, realized_contact, reason)}
      end
    end
  end

  @spec realize_scheduled_contact(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled_contact(mission_id, scheduled_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           fetch_scheduled_contact(mission_id, scheduled_contact_id) do
      realize_scheduled_contact_record(scheduled_contact, opts)
    end
  end

  @spec realize_scheduled_contact(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled_contact(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id) do
      realize_scheduled_contact_record(scheduled_contact, opts)
    end
  end

  @spec cancel_scheduled_contact(binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled_contact(mission_id, scheduled_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           fetch_scheduled_contact(mission_id, scheduled_contact_id) do
      cancel_scheduled_contact_record(scheduled_contact, opts)
    end
  end

  @spec cancel_scheduled_contact(binary(), binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled_contact(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id) do
      cancel_scheduled_contact_record(scheduled_contact, opts)
    end
  end

  @spec start_realized_contact(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(%RealizedContact{} = realized_contact) do
    start_runtime_and_mark_active(realized_contact, %{started_at: DateTime.utc_now()})
  end

  @spec start_realized_contact(binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           fetch_realized_contact(mission_id, realized_contact_id) do
      start_realized_contact(realized_contact)
    end
  end

  @spec start_realized_contact(binary(), binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           fetch_realized_contact(organization_id, mission_id, realized_contact_id) do
      start_realized_contact(realized_contact)
    end
  end

  @spec end_realized_contact_early(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_contact_early(mission_id, realized_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_list(opts) do
    case fetch_realized_contact(mission_id, realized_contact_id) do
      {:ok, %RealizedContact{} = realized_contact} ->
        end_realized_contact_early_record(realized_contact, opts)

      {:error, :realized_contact_not_found} ->
        case Runtime.stop_realized_contact(mission_id, realized_contact_id) do
          :ok -> {:error, :realized_contact_not_found}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec end_realized_contact_early(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_contact_early(organization_id, mission_id, realized_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_list(opts) do
    case fetch_realized_contact(organization_id, mission_id, realized_contact_id) do
      {:ok, %RealizedContact{} = realized_contact} ->
        end_realized_contact_early_record(realized_contact, opts)

      {:error, :realized_contact_not_found} ->
        case Runtime.stop_realized_contact(mission_id, realized_contact_id) do
          :ok -> {:error, :realized_contact_not_found}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    case end_realized_contact_early(mission_id, realized_contact_id) do
      {:ok, _realized_contact} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_realized_contact(binary(), binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    case end_realized_contact_early(organization_id, mission_id, realized_contact_id, []) do
      {:ok, _realized_contact} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_path_template(%PathTemplate{} = path_template) do
    with :ok <- validate_mission_id(path_template.mission_id),
         :ok <- validate_reusable_path_refs(path_template.provider_profile_ids),
         :ok <- validate_reusable_path_refs(path_template.transport_profile_ids),
         {:ok, _path} <- resolve_path_template(path_template) do
      :ok
    end
  end

  defp validate_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    with :ok <- validate_mission_id(scheduled_contact.mission_id),
         :ok <- validate_starts_before_end(scheduled_contact.starts_at, scheduled_contact.ends_at),
         {:ok, resolved_paths} <- resolve_scheduled_contact_paths(scheduled_contact),
         :ok <- validate_non_empty_paths(resolved_paths) do
      validate_unique_path_ids(resolved_paths)
    end
  end

  defp validate_realized_contact(%RealizedContact{} = realized_contact) do
    validate_mission_id(realized_contact.mission_id)
  end

  defp validate_mission_id(mission_id) when is_binary(mission_id) and mission_id != "", do: :ok
  defp validate_mission_id(_mission_id), do: {:error, :missing_mission_id}

  defp validate_starts_before_end(%DateTime{} = _starts_at, nil), do: :ok

  defp validate_starts_before_end(%DateTime{} = starts_at, %DateTime{} = ends_at) do
    case DateTime.compare(starts_at, ends_at) do
      :gt -> {:error, :scheduled_contact_ends_before_it_starts}
      _other -> :ok
    end
  end

  defp validate_starts_before_end(_starts_at, _ends_at),
    do: {:error, :scheduled_contact_requires_start_time}

  defp validate_reusable_path_refs(refs) when is_list(refs) do
    if length(refs) == MapSet.size(MapSet.new(refs)) do
      :ok
    else
      {:error, :duplicate_contact_runtime_config_reference}
    end
  end

  defp validate_non_empty_paths([]), do: {:error, :scheduled_contact_requires_path_configuration}
  defp validate_non_empty_paths(_paths), do: :ok

  defp validate_unique_path_ids(paths) do
    path_ids = Enum.map(paths, & &1.path_id)

    if length(path_ids) == MapSet.size(MapSet.new(path_ids)) do
      :ok
    else
      {:error, :duplicate_scheduled_contact_path_id}
    end
  end

  defp validate_schedule_realization(%ScheduledContact{lifecycle_state: :scheduled}), do: :ok

  defp validate_schedule_realization(%ScheduledContact{lifecycle_state: :realized}),
    do: {:error, :scheduled_contact_already_realized}

  defp validate_schedule_realization(%ScheduledContact{lifecycle_state: :completed}),
    do: {:error, :scheduled_contact_completed}

  defp validate_schedule_realization(%ScheduledContact{lifecycle_state: :expired}),
    do: {:error, :scheduled_contact_expired}

  defp validate_schedule_realization(%ScheduledContact{lifecycle_state: :canceled}),
    do: {:error, :scheduled_contact_canceled}

  defp realize_scheduled_contact_record(%ScheduledContact{} = scheduled_contact, opts) do
    transition_time = Keyword.get(opts, :transition_time, DateTime.utc_now())

    with :ok <- validate_schedule_realization(scheduled_contact),
         {:ok, realized_contact} <- build_realized_contact(scheduled_contact, opts),
         :ok <- validate_unique_path_ids(realized_contact.paths) do
      with {:ok, %RealizedContact{} = persisted_realized_contact} <-
             persist_realized_contact_transaction(scheduled_contact, realized_contact),
           {:ok, _pid} <-
             start_runtime_and_mark_active(persisted_realized_contact, %{
               activated_from_schedule: true,
               started_at: transition_time
             }),
           {:ok, %RealizedContact{} = active_realized_contact} <-
             fetch_realized_contact(
               persisted_realized_contact.mission_id,
               persisted_realized_contact.realized_contact_id
             ) do
        {:ok, active_realized_contact}
      end
    end
  end

  defp cancel_scheduled_contact_record(%ScheduledContact{} = scheduled_contact, opts) do
    transition_time = Keyword.get(opts, :transition_time, DateTime.utc_now())

    case scheduled_contact.lifecycle_state do
      :canceled ->
        {:ok, scheduled_contact}

      :completed ->
        {:error, :scheduled_contact_completed}

      :expired ->
        {:error, :scheduled_contact_expired}

      _other_state ->
        with {:ok, _realized_contact} <-
               maybe_stop_linked_realized_contact_for_schedule_cancellation(
                 scheduled_contact,
                 transition_time,
                 opts
               ),
             {:ok, %ScheduledContact{} = canceled_scheduled_contact} <-
               update_scheduled_contact_lifecycle(
                 scheduled_contact,
                 :canceled,
                 schedule_cancellation_metadata(
                   scheduled_contact,
                   transition_time,
                   opts
                 )
               ),
             {:ok, %ContactAction{}} <-
               persist_contact_action(
                 build_scheduled_contact_canceled_action(
                   canceled_scheduled_contact,
                   transition_time,
                   opts
                 )
               ) do
          {:ok, canceled_scheduled_contact}
        end
    end
  end

  defp end_realized_contact_early_record(%RealizedContact{} = realized_contact, opts) do
    transition_time = Keyword.get(opts, :transition_time, DateTime.utc_now())

    with {:ok, %RealizedContact{} = stopped_realized_contact} <-
           stop_realized_contact_transition(
             realized_contact,
             realized_contact_stop_metadata(transition_time, opts)
           ),
         {:ok, _scheduled_contact} <-
           maybe_cancel_linked_scheduled_contact_for_realized_stop(
             realized_contact,
             transition_time,
             opts
           ),
         {:ok, %ContactAction{}} <-
           persist_contact_action(
             build_realized_contact_ended_early_action(
               stopped_realized_contact,
               transition_time,
               opts
             )
           ) do
      {:ok, stopped_realized_contact}
    end
  end

  defp persist_realized_contact_transaction(
         %ScheduledContact{} = scheduled_contact,
         %RealizedContact{} = realized_contact
       ) do
    Multi.new()
    |> Multi.insert(:realized_contact, RealizedContactRow.changeset(realized_contact))
    |> Multi.run(:scheduled_contact, fn repo, _changes ->
      case repo.get_by(ScheduledContactRow,
             mission_id: scheduled_contact.mission_id,
             scheduled_contact_id: scheduled_contact.scheduled_contact_id
           ) do
        nil ->
          {:error, :scheduled_contact_not_found}

        %ScheduledContactRow{} = row ->
          row
          |> ScheduledContactRow.realized_changeset(scheduled_contact, realized_contact)
          |> repo.update()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{realized_contact: %RealizedContactRow{} = row}} ->
        {:ok, RealizedContactRow.to_domain(row)}

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp start_runtime_and_mark_active(
         %RealizedContact{} = realized_contact,
         metadata_patch
       )
       when is_map(metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized_contact(realized_contact),
         {:ok, pid} <- Runtime.start_realized_contact(persisted_realized_contact),
         {:ok, _updated_realized_contact} <-
           update_realized_contact_lifecycle(
             persisted_realized_contact,
             :active,
             metadata_patch
           ) do
      {:ok, pid}
    end
  end

  defp stop_realized_contact_transition(
         %RealizedContact{} = realized_contact,
         metadata_patch
       )
       when is_map(metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized_contact(realized_contact),
         :ok <-
           Runtime.stop_realized_contact(
             persisted_realized_contact.mission_id,
             persisted_realized_contact.realized_contact_id
           ) do
      case persisted_realized_contact.lifecycle_state do
        state when state in [:stopped, :completed] ->
          {:ok, persisted_realized_contact}

        _other_state ->
          update_realized_contact_lifecycle(
            persisted_realized_contact,
            :stopped,
            metadata_patch
          )
      end
    end
  end

  defp complete_realized_contact(
         %RealizedContact{} = realized_contact,
         metadata_patch
       )
       when is_map(metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized_contact(realized_contact),
         :ok <-
           Runtime.stop_realized_contact(
             persisted_realized_contact.mission_id,
             persisted_realized_contact.realized_contact_id
           ),
         {:ok, %RealizedContact{} = completed_realized_contact} <-
           update_realized_contact_lifecycle(
             persisted_realized_contact,
             :completed,
             metadata_patch
           ) do
      {:ok, completed_realized_contact}
    end
  end

  defp ensure_persisted_realized_contact(%RealizedContact{} = realized_contact) do
    case fetch_realized_contact(realized_contact.mission_id, realized_contact.realized_contact_id) do
      {:ok, %RealizedContact{} = persisted_realized_contact} ->
        {:ok, persisted_realized_contact}

      {:error, :realized_contact_not_found} ->
        persist_realized_contact(realized_contact)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_contact_action(%ContactAction{} = contact_action) do
    projected_events = MissionEventProjection.project(contact_action)

    Multi.new()
    |> Multi.insert(
      :contact_action,
      ContactActionRow.changeset(contact_action),
      on_conflict: :nothing,
      conflict_target: [:mission_id, :contact_action_id]
    )
    |> Multi.run(:mission_events, fn repo, _changes ->
      MissionEventProjection.persist_entries(repo, projected_events)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{contact_action: %ContactActionRow{} = row}} ->
        {:ok, ContactActionRow.to_domain(row)}

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp maybe_stop_linked_realized_contact_for_schedule_cancellation(
         %ScheduledContact{realized_contact_id: nil},
         _transition_time,
         _opts
       ),
       do: {:ok, nil}

  defp maybe_stop_linked_realized_contact_for_schedule_cancellation(
         %ScheduledContact{} = scheduled_contact,
         transition_time,
         opts
       ) do
    case fetch_realized_contact(
           scheduled_contact.mission_id,
           scheduled_contact.realized_contact_id
         ) do
      {:ok, %RealizedContact{} = realized_contact} ->
        stop_realized_contact_transition(
          realized_contact,
          schedule_cancellation_realized_metadata(transition_time, opts)
        )

      {:error, :realized_contact_not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_cancel_linked_scheduled_contact_for_realized_stop(
         %RealizedContact{scheduled_contact_id: nil},
         _transition_time,
         _opts
       ),
       do: {:ok, nil}

  defp maybe_cancel_linked_scheduled_contact_for_realized_stop(
         %RealizedContact{} = realized_contact,
         transition_time,
         opts
       ) do
    case fetch_scheduled_contact(
           realized_contact.mission_id,
           realized_contact.scheduled_contact_id
         ) do
      {:ok, %ScheduledContact{lifecycle_state: state} = scheduled_contact}
      when state in [:canceled, :completed, :expired] ->
        {:ok, scheduled_contact}

      {:ok, %ScheduledContact{} = scheduled_contact} ->
        update_scheduled_contact_lifecycle(
          scheduled_contact,
          :canceled,
          realized_contact_cancellation_metadata(realized_contact, transition_time, opts)
        )

      {:error, :scheduled_contact_not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expire_scheduled_contact(
         %ScheduledContact{} = scheduled_contact,
         metadata_patch
       )
       when is_map(metadata_patch) do
    update_scheduled_contact_lifecycle(scheduled_contact, :expired, metadata_patch)
  end

  defp complete_scheduled_contact(
         %ScheduledContact{} = scheduled_contact,
         metadata_patch
       )
       when is_map(metadata_patch) do
    update_scheduled_contact_lifecycle(scheduled_contact, :completed, metadata_patch)
  end

  defp update_scheduled_contact_lifecycle(
         %ScheduledContact{} = scheduled_contact,
         lifecycle_state,
         metadata_patch
       )
       when is_atom(lifecycle_state) and is_map(metadata_patch) do
    case Repo.get_by(ScheduledContactRow,
           mission_id: scheduled_contact.mission_id,
           scheduled_contact_id: scheduled_contact.scheduled_contact_id
         ) do
      nil ->
        {:error, :scheduled_contact_not_found}

      %ScheduledContactRow{} = row ->
        row
        |> ScheduledContactRow.lifecycle_changeset(lifecycle_state, metadata_patch)
        |> Repo.update()
        |> case do
          {:ok, %ScheduledContactRow{} = updated_row} ->
            {:ok, ScheduledContactRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  defp update_realized_contact_lifecycle(
         %RealizedContact{} = realized_contact,
         lifecycle_state,
         metadata_patch
       )
       when is_atom(lifecycle_state) and is_map(metadata_patch) do
    case Repo.get_by(RealizedContactRow,
           mission_id: realized_contact.mission_id,
           realized_contact_id: realized_contact.realized_contact_id
         ) do
      nil ->
        {:error, :realized_contact_not_found}

      %RealizedContactRow{} = row ->
        row
        |> RealizedContactRow.lifecycle_changeset(lifecycle_state, metadata_patch)
        |> Repo.update()
        |> case do
          {:ok, %RealizedContactRow{} = updated_row} ->
            {:ok, RealizedContactRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  defp build_realized_contact(%ScheduledContact{} = scheduled_contact, opts) do
    with {:ok, resolved_paths} <- resolve_scheduled_contact_paths(scheduled_contact) do
      metadata =
        scheduled_contact.metadata
        |> Map.merge(%{
          scheduled_contact_id: scheduled_contact.scheduled_contact_id,
          provider_contact_ref: scheduled_contact.provider_contact_ref,
          path_template_ids: scheduled_contact.path_template_ids,
          path_template_refs: scheduled_contact.path_template_refs
        })
        |> Map.merge(Keyword.get(opts, :metadata, %{}))

      {:ok,
       RealizedContact.new(%{
         realized_contact_id:
           Keyword.get(
             opts,
             :realized_contact_id,
             scheduled_contact.scheduled_contact_id <> "_run"
           ),
         organization_id: scheduled_contact.organization_id,
         mission_id: scheduled_contact.mission_id,
         scheduled_contact_id: scheduled_contact.scheduled_contact_id,
         source_endpoint_refs: scheduled_contact.source_endpoint_refs,
         paths: resolved_paths,
         clock_mode: Keyword.get(opts, :clock_mode, :live),
         initial_time: Keyword.get(opts, :initial_time, scheduled_contact.starts_at),
         lifecycle_state: :defined,
         realized_at: Keyword.get(opts, :realized_at, DateTime.utc_now()),
         metadata: metadata
       })}
    end
  end

  defp resolve_scheduled_contact_paths(%ScheduledContact{} = scheduled_contact) do
    with {:ok, template_paths} <-
           resolve_path_templates(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.path_template_ids,
             scheduled_contact.path_template_refs
           ) do
      {:ok, template_paths ++ scheduled_contact.paths}
    end
  end

  defp resolve_path_templates(_organization_id, _mission_id, [], []), do: {:ok, []}

  defp resolve_path_templates(organization_id, mission_id, path_template_ids, path_template_refs)
       when is_binary(mission_id) and is_list(path_template_ids) and is_list(path_template_refs) do
    refs =
      if path_template_refs == [],
        do: refs_from_ids(path_template_ids, "path_template_id"),
        else: path_template_refs

    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      with {:ok, %PathTemplate{} = path_template} <-
             fetch_path_template_ref_for_scope(organization_id, mission_id, ref),
           {:ok, %Path{} = resolved_path} <- resolve_path_template(path_template) do
        {:cont, {:ok, acc ++ [resolved_path]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_path_template_for_scope(organization_id, mission_id, path_template_id)
       when is_binary(organization_id) and organization_id != "" do
    fetch_path_template(organization_id, mission_id, path_template_id)
  end

  defp fetch_path_template_for_scope(_organization_id, mission_id, path_template_id) do
    fetch_path_template(mission_id, path_template_id)
  end

  defp resolve_path_template(%PathTemplate{} = path_template) do
    with {:ok, provider_bindings} <- resolve_provider_bindings(path_template),
         {:ok, transport_bindings} <- resolve_transport_bindings(path_template) do
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

  defp resolve_provider_bindings(%PathTemplate{} = path_template) do
    refs =
      if path_template.provider_profile_refs == [] do
        refs_from_ids(path_template.provider_profile_ids, "provider_profile_id")
      else
        path_template.provider_profile_refs
      end

    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_provider_profile_ref_for_scope(
             path_template.organization_id,
             path_template.mission_id,
             ref
           ) do
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

  defp resolve_transport_bindings(%PathTemplate{} = path_template) do
    refs =
      if path_template.transport_profile_refs == [] do
        refs_from_ids(path_template.transport_profile_ids, "transport_profile_id")
      else
        path_template.transport_profile_refs
      end

    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_transport_profile_ref_for_scope(
             path_template.organization_id,
             path_template.mission_id,
             ref
           ) do
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

  defp fetch_provider_profile_for_scope(organization_id, mission_id, provider_profile_id)
       when is_binary(organization_id) and organization_id != "" do
    fetch_provider_profile(organization_id, mission_id, provider_profile_id)
  end

  defp fetch_provider_profile_for_scope(_organization_id, mission_id, provider_profile_id) do
    fetch_provider_profile(mission_id, provider_profile_id)
  end

  defp fetch_provider_profile_ref_for_scope(organization_id, mission_id, ref) do
    fetch_versioned_ref_for_scope(
      organization_id,
      mission_id,
      ref,
      "provider_profile_id",
      :contact_provider_profile_not_found,
      &fetch_provider_profile_for_scope/3,
      &fetch_provider_profile_version/4,
      &fetch_provider_profile_version/3
    )
  end

  defp fetch_transport_profile_for_scope(organization_id, mission_id, transport_profile_id)
       when is_binary(organization_id) and organization_id != "" do
    fetch_transport_profile(organization_id, mission_id, transport_profile_id)
  end

  defp fetch_transport_profile_for_scope(_organization_id, mission_id, transport_profile_id) do
    fetch_transport_profile(mission_id, transport_profile_id)
  end

  defp fetch_transport_profile_ref_for_scope(organization_id, mission_id, ref) do
    fetch_versioned_ref_for_scope(
      organization_id,
      mission_id,
      ref,
      "transport_profile_id",
      :contact_transport_profile_not_found,
      &fetch_transport_profile_for_scope/3,
      &fetch_transport_profile_version/4,
      &fetch_transport_profile_version/3
    )
  end

  defp fetch_path_template_ref_for_scope(organization_id, mission_id, ref) do
    fetch_versioned_ref_for_scope(
      organization_id,
      mission_id,
      ref,
      "path_template_id",
      :contact_path_template_not_found,
      &fetch_path_template_for_scope/3,
      &fetch_path_template_version/4,
      &fetch_path_template_version/3
    )
  end

  defp prepare_path_template(%PathTemplate{} = path_template) do
    with {:ok, provider_profile_refs} <-
           normalize_versioned_refs(
             path_template.provider_profile_ids,
             path_template.provider_profile_refs,
             "provider_profile_id",
             fn ref ->
               fetch_provider_profile_ref_for_scope(
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
               fetch_transport_profile_ref_for_scope(
                 path_template.organization_id,
                 path_template.mission_id,
                 ref
               )
             end
           ),
         :ok <-
           validate_reusable_path_refs(
             ids_from_refs(provider_profile_refs, "provider_profile_id")
           ),
         :ok <-
           validate_reusable_path_refs(
             ids_from_refs(transport_profile_refs, "transport_profile_id")
           ) do
      {:ok,
       %PathTemplate{
         path_template
         | provider_profile_ids: ids_from_refs(provider_profile_refs, "provider_profile_id"),
           provider_profile_refs: provider_profile_refs,
           transport_profile_ids: ids_from_refs(transport_profile_refs, "transport_profile_id"),
           transport_profile_refs: transport_profile_refs
       }}
    end
  end

  defp prepare_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    with {:ok, path_template_refs} <-
           normalize_versioned_refs(
             scheduled_contact.path_template_ids,
             scheduled_contact.path_template_refs,
             "path_template_id",
             fn ref ->
               fetch_path_template_ref_for_scope(
                 scheduled_contact.organization_id,
                 scheduled_contact.mission_id,
                 ref
               )
             end
           ),
         :ok <- validate_reusable_path_refs(ids_from_refs(path_template_refs, "path_template_id")) do
      {:ok,
       %ScheduledContact{
         scheduled_contact
         | path_template_ids: ids_from_refs(path_template_refs, "path_template_id"),
           path_template_refs: path_template_refs
       }}
    end
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

  defp fetch_versioned_ref_for_scope(
         organization_id,
         mission_id,
         ref,
         id_key,
         not_found_reason,
         fetch_scope,
         fetch_version_with_org,
         fetch_version_without_org
       ) do
    resource_id = Map.get(ref, id_key)
    version = Map.get(ref, "version")

    resource_result =
      if is_integer(version) and version > 0 do
        fetch_versioned_resource(
          organization_id,
          mission_id,
          resource_id,
          version,
          fetch_version_with_org,
          fetch_version_without_org
        )
      else
        fetch_scope.(organization_id, mission_id, resource_id)
      end

    normalize_versioned_ref_result(resource_result, not_found_reason)
  end

  defp fetch_versioned_resource(
         organization_id,
         mission_id,
         resource_id,
         version,
         fetch_version_with_org,
         fetch_version_without_org
       ) do
    if is_binary(organization_id) and organization_id != "" do
      fetch_version_with_org.(organization_id, mission_id, resource_id, version)
    else
      fetch_version_without_org.(mission_id, resource_id, version)
    end
  end

  defp normalize_versioned_ref_result({:ok, %{lifecycle_state: :deleted}}, not_found_reason) do
    {:error, not_found_reason}
  end

  defp normalize_versioned_ref_result({:ok, resource}, _not_found_reason), do: {:ok, resource}
  defp normalize_versioned_ref_result({:error, reason}, _not_found_reason), do: {:error, reason}

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

  defp latest_versioned_row(schema, mission_id, definition_id_field, definition_id)
       when is_binary(mission_id) and is_atom(definition_id_field) and is_binary(definition_id) do
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
       )
       when is_binary(organization_id) and is_binary(mission_id) and
              is_atom(definition_id_field) and is_binary(definition_id) do
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

  defp latest_versioned_rows(schema, mission_id, definition_id_field)
       when is_binary(mission_id) and is_atom(definition_id_field) do
    schema
    |> where([definition_row], field(definition_row, :mission_id) == ^mission_id)
    |> order_by([definition_row],
      asc: field(definition_row, ^definition_id_field),
      desc: field(definition_row, :version)
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn definition_row, acc ->
      definition_id = Map.fetch!(definition_row, definition_id_field)
      Map.put_new(acc, definition_id, definition_row)
    end)
    |> Map.values()
  end

  defp latest_versioned_rows(schema, organization_id, mission_id, definition_id_field)
       when is_binary(organization_id) and is_binary(mission_id) and
              is_atom(definition_id_field) do
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
    |> Enum.reduce(%{}, fn definition_row, acc ->
      definition_id = Map.fetch!(definition_row, definition_id_field)
      Map.put_new(acc, definition_id, definition_row)
    end)
    |> Map.values()
  end

  defp build_next_provider_profile_version(%ProviderProfile{} = provider_profile, attrs)
       when is_map(attrs) do
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

  defp build_next_transport_profile_version(%TransportProfile{} = transport_profile, attrs)
       when is_map(attrs) do
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

  defp build_next_path_template_version(%PathTemplate{} = path_template, attrs)
       when is_map(attrs) do
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
         source_endpoint_ref:
           Map.get(attrs, :source_endpoint_ref, path_template.source_endpoint_ref),
         provider_path_ref: Map.get(attrs, :provider_path_ref, path_template.provider_path_ref),
         provider_profile_ids: provider_profile_ids,
         provider_profile_refs: provider_profile_refs,
         transport_profile_ids: transport_profile_ids,
         transport_profile_refs: transport_profile_refs,
         metadata: Map.merge(path_template.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  defp list_due_scheduled_contacts(%DateTime{} = reference_time) do
    ScheduledContactRow
    |> where(
      [row],
      row.lifecycle_state == "scheduled" and row.starts_at <= ^reference_time and
        (is_nil(row.ends_at) or row.ends_at > ^reference_time)
    )
    |> order_by([row], asc: row.starts_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp list_expired_scheduled_contacts(%DateTime{} = reference_time) do
    ScheduledContactRow
    |> where(
      [row],
      row.lifecycle_state == "scheduled" and not is_nil(row.ends_at) and
        row.ends_at <= ^reference_time
    )
    |> order_by([row], asc: row.ends_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp list_completed_scheduled_contacts(%DateTime{} = reference_time) do
    ScheduledContactRow
    |> where(
      [row],
      row.lifecycle_state == "realized" and not is_nil(row.ends_at) and
        row.ends_at <= ^reference_time
    )
    |> order_by([row], asc: row.ends_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp list_active_realized_contacts do
    RealizedContactRow
    |> where([row], row.lifecycle_state == "active")
    |> order_by([row], asc: row.realized_at, asc: row.realized_contact_id)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  defp list_expired_active_realized_contacts(%DateTime{} = reference_time) do
    RealizedContactRow
    |> join(
      :inner,
      [realized_contact_row],
      scheduled_contact_row in ScheduledContactRow,
      on:
        realized_contact_row.mission_id == scheduled_contact_row.mission_id and
          realized_contact_row.scheduled_contact_id == scheduled_contact_row.scheduled_contact_id
    )
    |> where(
      [realized_contact_row, scheduled_contact_row],
      realized_contact_row.lifecycle_state == "active" and
        not is_nil(scheduled_contact_row.ends_at) and
        scheduled_contact_row.ends_at <= ^reference_time
    )
    |> order_by(
      [realized_contact_row, scheduled_contact_row],
      asc: scheduled_contact_row.ends_at,
      asc: realized_contact_row.realized_contact_id
    )
    |> select([realized_contact_row, _scheduled_contact_row], realized_contact_row)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  defp reconcile_error(kind, %ScheduledContact{} = scheduled_contact, reason) do
    %{
      kind: kind,
      mission_id: scheduled_contact.mission_id,
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      reason: reason
    }
  end

  defp reconcile_error(kind, %RealizedContact{} = realized_contact, reason) do
    %{
      kind: kind,
      mission_id: realized_contact.mission_id,
      realized_contact_id: realized_contact.realized_contact_id,
      reason: reason
    }
  end

  defp maybe_filter_contact_actions(query, opts) do
    query
    |> maybe_filter_contact_actions_by_scheduled_contact(opts)
    |> maybe_filter_contact_actions_by_realized_contact(opts)
  end

  defp maybe_filter_contact_actions_by_scheduled_contact(query, opts) do
    case Keyword.get(opts, :scheduled_contact_id) do
      nil ->
        query

      scheduled_contact_id ->
        where(query, [row], row.scheduled_contact_id == ^scheduled_contact_id)
    end
  end

  defp maybe_filter_contact_actions_by_realized_contact(query, opts) do
    case Keyword.get(opts, :realized_contact_id) do
      nil -> query
      realized_contact_id -> where(query, [row], row.realized_contact_id == ^realized_contact_id)
    end
  end

  defp realized_contact_stop_metadata(transition_time, opts) do
    %{
      stopped_at: transition_time,
      ended_early?: true
    }
    |> maybe_put_reason(opts)
  end

  defp schedule_cancellation_realized_metadata(transition_time, opts) do
    %{
      stopped_at: transition_time,
      ended_early?: true,
      stopped_from_schedule_cancellation: true
    }
    |> maybe_put_reason(opts)
  end

  defp schedule_cancellation_metadata(
         %ScheduledContact{} = scheduled_contact,
         transition_time,
         opts
       ) do
    %{
      canceled_at: transition_time,
      canceled_during_execution?: not is_nil(scheduled_contact.realized_contact_id),
      canceled_from_schedule_action: true
    }
    |> maybe_put_reason(opts)
  end

  defp realized_contact_cancellation_metadata(
         %RealizedContact{} = realized_contact,
         transition_time,
         opts
       ) do
    %{
      canceled_at: transition_time,
      canceled_during_execution?: true,
      canceled_from_realized_contact_stop: true,
      realized_contact_id: realized_contact.realized_contact_id
    }
    |> maybe_put_reason(opts)
  end

  defp maybe_put_reason(metadata, opts) do
    case Keyword.get(opts, :reason) do
      nil -> metadata
      reason -> Map.put(metadata, :reason, reason)
    end
  end

  defp build_scheduled_contact_canceled_action(
         %ScheduledContact{} = scheduled_contact,
         transition_time,
         opts
       ) do
    ContactAction.new(%{
      organization_id: scheduled_contact.organization_id,
      mission_id: scheduled_contact.mission_id,
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      realized_contact_id: scheduled_contact.realized_contact_id,
      action_kind: :scheduled_contact_canceled,
      reason: Keyword.get(opts, :reason),
      actor: Keyword.get(opts, :actor, %{}),
      metadata: %{
        canceled_during_execution?: not is_nil(scheduled_contact.realized_contact_id)
      },
      occurred_at: transition_time
    })
  end

  defp build_realized_contact_ended_early_action(
         %RealizedContact{} = realized_contact,
         transition_time,
         opts
       ) do
    ContactAction.new(%{
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      realized_contact_id: realized_contact.realized_contact_id,
      action_kind: :realized_contact_ended_early,
      reason: Keyword.get(opts, :reason),
      actor: Keyword.get(opts, :actor, %{}),
      metadata: %{ended_early?: true},
      occurred_at: transition_time
    })
  end

  defp put_organization_scope(%ProviderProfile{} = provider_profile, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case provider_profile.organization_id do
      nil ->
        {:ok, %ProviderProfile{provider_profile | organization_id: organization_id}}

      ^organization_id ->
        {:ok, provider_profile}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          provider_profile.mission_id}}
    end
  end

  defp put_organization_scope(%TransportProfile{} = transport_profile, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case transport_profile.organization_id do
      nil ->
        {:ok, %TransportProfile{transport_profile | organization_id: organization_id}}

      ^organization_id ->
        {:ok, transport_profile}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          transport_profile.mission_id}}
    end
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

  defp put_organization_scope(%ScheduledContact{} = scheduled_contact, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case scheduled_contact.organization_id do
      nil ->
        {:ok, %ScheduledContact{scheduled_contact | organization_id: organization_id}}

      ^organization_id ->
        {:ok, scheduled_contact}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          scheduled_contact.mission_id}}
    end
  end

  defp put_organization_scope(%RealizedContact{} = realized_contact, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case realized_contact.organization_id do
      nil ->
        {:ok, %RealizedContact{realized_contact | organization_id: organization_id}}

      ^organization_id ->
        {:ok, realized_contact}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          realized_contact.mission_id}}
    end
  end
end
