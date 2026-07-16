defmodule Cadence.Contacts do
  @moduledoc """
  Persistence and lifecycle boundary for scheduled and realized contacts.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Contacts.{
    ContactAction,
    LinkAssignment,
    Path,
    PathTemplate,
    ProviderBinding,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    ScheduledContactRevisions,
    Scheduler,
    TransportBinding,
    TransportProfile
  }

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Missions
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  alias Cadence.Persistence.Schemas.{
    ContactActionRow,
    ContactLinkAssignmentRow,
    ContactPathTemplateRow,
    ContactProviderProfileRow,
    ContactTransportProfileRow,
    RealizedContactRow,
    ScheduledContactRow
  }

  alias Cadence.Repo
  alias Cadence.Runtime

  @type shared_link_direction :: :downlink | :uplink | :bidirectional

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

  @spec create_shared_link(binary(), binary(), map()) ::
          {:ok,
           %{
             provider: ProviderProfile.t(),
             transport: TransportProfile.t() | nil,
             path_templates: [PathTemplate.t()]
           }}
          | {:error, term()}
  def create_shared_link(organization_id, mission_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(attrs) do
    with {:ok, context} <- shared_link_context(organization_id, mission_id, attrs) do
      Repo.transaction(fn ->
        context
        |> persist_shared_link_records()
        |> unwrap_transaction_result()
      end)
    end
  end

  @spec apply_link_template(binary(), binary(), PathTemplate.t(), [map()], map()) ::
          {:ok,
           %{
             rows: [map()],
             applied_count: non_neg_integer(),
             skipped_count: non_neg_integer(),
             failed_count: non_neg_integer()
           }}
  def apply_link_template(
        organization_id,
        mission_id,
        %PathTemplate{} = source_template,
        spacecraft,
        attrs
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft) and
             is_map(attrs) do
    source_endpoints = SourceEndpoints.list_source_endpoints(organization_id, mission_id)
    path_templates = list_path_templates(organization_id, mission_id)
    link_assignments = list_link_assignments(organization_id, mission_id)

    result_rows =
      Enum.map(spacecraft, fn spacecraft ->
        apply_link_template_row(
          organization_id,
          mission_id,
          source_template,
          spacecraft,
          attrs,
          source_endpoints,
          path_templates,
          link_assignments
        )
      end)

    {:ok,
     %{
       rows: result_rows,
       applied_count: Enum.count(result_rows, &(&1.kind == :applied)),
       skipped_count: Enum.count(result_rows, &(&1.kind == :skipped)),
       failed_count: Enum.count(result_rows, &(&1.kind == :failed))
     }}
  end

  @spec persist_link_assignment(binary(), LinkAssignment.t()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def persist_link_assignment(organization_id, %LinkAssignment{} = assignment)
      when is_binary(organization_id) do
    with {:ok, scoped_assignment} <- put_organization_scope(assignment, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_assignment.organization_id, scoped_assignment.mission_id),
         :ok <- validate_link_assignment(scoped_assignment),
         {:ok, _row} <-
           Repo.insert(ContactLinkAssignmentRow.changeset(scoped_assignment),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :link_assignment_id]
           ) do
      fetch_link_assignment(
        scoped_assignment.organization_id,
        scoped_assignment.mission_id,
        scoped_assignment.link_assignment_id
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_link_assignment(binary(), binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch_link_assignment(organization_id, mission_id, link_assignment_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) do
    case Repo.get_by(ContactLinkAssignmentRow,
           organization_id: organization_id,
           mission_id: mission_id,
           link_assignment_id: link_assignment_id
         ) do
      nil ->
        {:error, :contact_link_assignment_not_found}

      %ContactLinkAssignmentRow{lifecycle_state: "deleted"} ->
        {:error, :contact_link_assignment_not_found}

      %ContactLinkAssignmentRow{} = row ->
        {:ok, ContactLinkAssignmentRow.to_domain(row)}
    end
  end

  @spec fetch_link_assignment(binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch_link_assignment(mission_id, link_assignment_id)
      when is_binary(mission_id) and is_binary(link_assignment_id) do
    case Repo.get_by(ContactLinkAssignmentRow,
           mission_id: mission_id,
           link_assignment_id: link_assignment_id
         ) do
      nil ->
        {:error, :contact_link_assignment_not_found}

      %ContactLinkAssignmentRow{lifecycle_state: "deleted"} ->
        {:error, :contact_link_assignment_not_found}

      %ContactLinkAssignmentRow{} = row ->
        {:ok, ContactLinkAssignmentRow.to_domain(row)}
    end
  end

  @spec list_link_assignments(binary(), binary()) :: [LinkAssignment.t()]
  def list_link_assignments(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactLinkAssignmentRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.lifecycle_state == "active"
    )
    |> order_by([row], asc: row.link_assignment_id)
    |> Repo.all()
    |> Enum.map(&ContactLinkAssignmentRow.to_domain/1)
  end

  @spec delete_link_assignment(binary(), binary(), binary(), map()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def delete_link_assignment(
        organization_id,
        mission_id,
        link_assignment_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) and is_map(metadata_patch) do
    with {:ok, %LinkAssignment{} = assignment} <-
           fetch_link_assignment(organization_id, mission_id, link_assignment_id) do
      metadata =
        assignment.metadata
        |> Map.merge(metadata_patch)
        |> Map.put("deleted_at", DateTime.utc_now() |> DateTime.to_iso8601())

      {1, _rows} =
        ContactLinkAssignmentRow
        |> where(
          [row],
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.link_assignment_id == ^link_assignment_id
        )
        |> Repo.update_all(set: [lifecycle_state: "deleted", metadata: %{"value" => metadata}])

      {:ok, %LinkAssignment{assignment | lifecycle_state: :deleted, metadata: metadata}}
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
      Multi.new()
      |> Multi.insert(
        :scheduled_contact,
        ScheduledContactRow.changeset(prepared_scheduled_contact),
        on_conflict: :nothing,
        conflict_target: [:mission_id, :scheduled_contact_id]
      )
      |> Multi.run(:operational_event, fn repo, %{scheduled_contact: row} ->
        row
        |> ScheduledContactRow.to_domain()
        |> persist_contact_operational_event(repo)
      end)
      |> Multi.run(:scheduled_contact_revision, fn repo, %{scheduled_contact: row} ->
        ScheduledContactRevisions.ensure_initial(repo, ScheduledContactRow.to_domain(row))
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{scheduled_contact: %ScheduledContactRow{} = row}} ->
          row
          |> ScheduledContactRow.to_domain()
          |> notify_contact_changed()

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
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

  @spec fetch_scheduled_contact_by_provider_ref(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, :scheduled_contact_not_found}
  def fetch_scheduled_contact_by_provider_ref(mission_id, provider_contact_ref)
      when is_binary(mission_id) and is_binary(provider_contact_ref) do
    case Repo.get_by(ScheduledContactRow,
           mission_id: mission_id,
           provider_contact_ref: provider_contact_ref
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
      Multi.new()
      |> Multi.insert(:realized_contact, RealizedContactRow.changeset(realized_contact),
        on_conflict: :nothing,
        conflict_target: [:mission_id, :realized_contact_id]
      )
      |> Multi.run(:operational_event, fn repo, %{realized_contact: row} ->
        row
        |> RealizedContactRow.to_domain()
        |> persist_contact_operational_event(repo)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{realized_contact: %RealizedContactRow{} = row}} ->
          row
          |> RealizedContactRow.to_domain()
          |> notify_contact_changed()

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
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
    do_reconcile(nil, reference_time)
  end

  @spec reconcile(binary(), DateTime.t()) :: {:ok, map()}
  def reconcile(mission_id, %DateTime{} = reference_time) when is_binary(mission_id) do
    do_reconcile(mission_id, reference_time)
  end

  defp do_reconcile(mission_id, %DateTime{} = reference_time) do
    restart_candidates =
      list_active_realized_contacts_to_restart(reference_time, mission_id)

    {expired_scheduled_contact_ids, expiration_errors} =
      list_expired_scheduled_contacts(reference_time, mission_id)
      |> collect_reconcile_results(&expire_scheduled_contact_for_reconcile(&1, reference_time))

    {completed_scheduled_contact_ids, scheduled_completion_errors} =
      list_completed_scheduled_contacts(reference_time, mission_id)
      |> collect_reconcile_results(&complete_scheduled_contact_for_reconcile(&1, reference_time))

    {realized_scheduled_contact_ids, realization_errors} =
      list_due_scheduled_contacts(reference_time, mission_id)
      |> collect_reconcile_results(&realize_scheduled_contact_for_reconcile(&1, reference_time))

    {completed_realized_contact_ids, completion_errors} =
      list_expired_active_realized_contacts(reference_time, mission_id)
      |> collect_reconcile_results(&complete_realized_contact_for_reconcile(&1, reference_time))

    {restarted_realized_contact_ids, restart_errors} =
      restart_candidates
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

  @spec next_contact_scheduler_wakeup(binary(), DateTime.t()) :: DateTime.t() | nil
  def next_contact_scheduler_wakeup(mission_id, %DateTime{} = reference_time)
      when is_binary(mission_id) do
    reference_time
    |> list_contact_scheduler_wakeups(mission_id)
    |> Enum.find_value(fn
      %{mission_id: ^mission_id, wake_at: wake_at} -> wake_at
      _other -> nil
    end)
  end

  @spec list_contact_scheduler_wakeups(DateTime.t()) :: [
          %{mission_id: binary(), wake_at: DateTime.t()}
        ]
  def list_contact_scheduler_wakeups(reference_time, mission_id \\ nil)

  def list_contact_scheduler_wakeups(%DateTime{} = reference_time, mission_id)
      when is_nil(mission_id) or is_binary(mission_id) do
    scheduled_wakeups =
      ScheduledContactRow
      |> where([row], row.lifecycle_state in ["scheduled", "realized"])
      |> maybe_filter_scheduled_contacts_by_mission(mission_id)
      |> Repo.all()
      |> Enum.flat_map(&scheduled_contact_scheduler_wakeups(&1, reference_time))

    active_realized_wakeups =
      RealizedContactRow
      |> join(
        :inner,
        [realized_contact_row],
        scheduled_contact_row in ScheduledContactRow,
        on:
          realized_contact_row.mission_id == scheduled_contact_row.mission_id and
            realized_contact_row.scheduled_contact_id ==
              scheduled_contact_row.scheduled_contact_id
      )
      |> where(
        [realized_contact_row, scheduled_contact_row],
        realized_contact_row.lifecycle_state == "active" and
          not is_nil(scheduled_contact_row.ends_at)
      )
      |> maybe_filter_joined_realized_contacts_by_mission(mission_id)
      |> select([realized_contact_row, scheduled_contact_row], %{
        mission_id: realized_contact_row.mission_id,
        wake_at: scheduled_contact_row.ends_at
      })
      |> Repo.all()
      |> Enum.map(&normalize_scheduler_wakeup(&1, reference_time))

    scheduled_wakeups
    |> Kernel.++(active_realized_wakeups)
    |> group_scheduler_wakeups()
  end

  @spec contact_scheduler_projection(binary()) :: %{
          scheduled_contacts: %{optional(binary()) => ScheduledContact.t()}
        }
  def contact_scheduler_projection(mission_id) when is_binary(mission_id) do
    scheduled_contacts =
      ScheduledContactRow
      |> where(
        [row],
        row.mission_id == ^mission_id and row.lifecycle_state in ["scheduled", "realized"]
      )
      |> Repo.all()
      |> Enum.map(&ScheduledContactRow.to_domain/1)
      |> Map.new(&{&1.scheduled_contact_id, &1})

    %{scheduled_contacts: scheduled_contacts}
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
           notify_scheduler?: false,
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

  defp validate_link_assignment(%LinkAssignment{} = assignment) do
    with :ok <- validate_mission_id(assignment.mission_id),
         :ok <- validate_required_binary(assignment.spacecraft_id, :missing_spacecraft_id),
         :ok <-
           validate_required_binary(assignment.source_endpoint_ref, :missing_source_endpoint_ref),
         :ok <- validate_required_binary(assignment.path_template_id, :missing_path_template_id),
         {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             assignment.organization_id,
             assignment.mission_id,
             assignment.spacecraft_id
           ),
         {:ok, source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             assignment.organization_id,
             assignment.mission_id,
             assignment.source_endpoint_ref
           ),
         :ok <- validate_assignment_source_endpoint(spacecraft, source_endpoint),
         {:ok, path_template} <-
           fetch_path_template_version(
             assignment.organization_id,
             assignment.mission_id,
             assignment.path_template_id,
             assignment.path_template_version
           ),
         :ok <- validate_assignment_template_match(assignment, path_template),
         :ok <- validate_link_assignment_ref_existence(assignment) do
      validate_link_assignment_refs(assignment)
    end
  end

  defp validate_assignment_source_endpoint(spacecraft, source_endpoint) do
    if source_endpoint.spacecraft_id == spacecraft.spacecraft_id do
      :ok
    else
      {:error, :link_assignment_source_endpoint_mismatch}
    end
  end

  defp validate_assignment_template_match(
         %LinkAssignment{} = assignment,
         %PathTemplate{} = template
       ) do
    if assignment.direction == template.direction and
         assignment.selection_role == template.selection_role do
      :ok
    else
      {:error, :link_assignment_path_template_mismatch}
    end
  end

  defp validate_link_assignment_ref_existence(%LinkAssignment{} = assignment) do
    with :ok <-
           validate_link_assignment_provider_refs(
             assignment.organization_id,
             assignment.mission_id,
             assignment.provider_profile_refs
           ) do
      validate_link_assignment_transport_refs(
        assignment.organization_id,
        assignment.mission_id,
        assignment.transport_profile_refs
      )
    end
  end

  defp validate_link_assignment_provider_refs(organization_id, mission_id, refs) do
    Enum.reduce_while(refs, :ok, fn ref, :ok ->
      case fetch_provider_profile_ref_for_scope(organization_id, mission_id, ref) do
        {:ok, %ProviderProfile{}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_link_assignment_transport_refs(organization_id, mission_id, refs) do
    Enum.reduce_while(refs, :ok, fn ref, :ok ->
      case fetch_transport_profile_ref_for_scope(organization_id, mission_id, ref) do
        {:ok, %TransportProfile{}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_link_assignment_refs(%LinkAssignment{} = assignment) do
    case validate_reusable_path_refs(
           ids_from_refs(assignment.provider_profile_refs, "provider_profile_id")
         ) do
      :ok ->
        validate_reusable_path_refs(
          ids_from_refs(assignment.transport_profile_refs, "transport_profile_id")
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    with :ok <- validate_mission_id(scheduled_contact.mission_id),
         :ok <- validate_starts_before_end(scheduled_contact.starts_at, scheduled_contact.ends_at),
         {:ok, resolved_paths} <- resolve_scheduled_contact_paths(scheduled_contact),
         :ok <- validate_non_empty_paths(resolved_paths),
         :ok <- validate_selected_path_presence(resolved_paths),
         :ok <- validate_contact_intents(resolved_paths, scheduled_contact.contact_intents) do
      validate_unique_path_ids(resolved_paths)
    end
  end

  defp validate_realized_contact(%RealizedContact{} = realized_contact) do
    validate_mission_id(realized_contact.mission_id)
  end

  defp validate_mission_id(mission_id) when is_binary(mission_id) and mission_id != "", do: :ok
  defp validate_mission_id(_mission_id), do: {:error, :missing_mission_id}

  defp validate_required_binary(value, _reason) when is_binary(value) and value != "", do: :ok
  defp validate_required_binary(_value, reason), do: {:error, reason}

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

  defp validate_selected_path_presence(paths) do
    if Enum.any?(paths, &(&1.selection_role == :selected)) do
      :ok
    else
      {:error, :scheduled_contact_requires_selected_path}
    end
  end

  defp validate_contact_intents(paths, contact_intents) do
    with :ok <- validate_telemetry_downlink_intent(paths, contact_intents) do
      validate_command_window_intent(paths, contact_intents)
    end
  end

  defp validate_telemetry_downlink_intent(paths, contact_intents) do
    if :telemetry_downlink in contact_intents and not selected_direction?(paths, :downlink) do
      {:error, :scheduled_contact_requires_selected_downlink_path}
    else
      :ok
    end
  end

  defp validate_command_window_intent(paths, contact_intents) do
    if :command_window in contact_intents and not selected_direction?(paths, :uplink) do
      {:error, :scheduled_contact_requires_selected_uplink_path}
    else
      :ok
    end
  end

  defp selected_direction?(paths, direction) do
    Enum.any?(paths, &(&1.direction == direction and &1.selection_role == :selected))
  end

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
        scheduled_contact
        |> realized_scheduled_contact_projection(active_realized_contact)
        |> maybe_notify_contact_changed(opts)

        active_realized_contact
        |> maybe_notify_contact_changed(opts)
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
          canceled_scheduled_contact
          |> notify_contact_changed()
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
      stopped_realized_contact
      |> notify_contact_changed()
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
    |> Multi.run(:realized_contact_operational_event, fn repo, %{realized_contact: row} ->
      row
      |> RealizedContactRow.to_domain()
      |> persist_contact_operational_event(repo)
    end)
    |> Multi.run(:scheduled_contact_operational_event, fn repo, %{scheduled_contact: row} ->
      row
      |> ScheduledContactRow.to_domain()
      |> persist_contact_operational_event(repo)
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
         {:ok, %RealizedContact{} = stopped_realized_contact} <-
           mark_realized_contact_stopped(persisted_realized_contact, metadata_patch),
         :ok <-
           Runtime.stop_realized_contact_sync(
             stopped_realized_contact.mission_id,
             stopped_realized_contact.realized_contact_id
           ) do
      {:ok, stopped_realized_contact}
    end
  end

  defp mark_realized_contact_stopped(
         %RealizedContact{lifecycle_state: state} = realized_contact,
         _metadata_patch
       )
       when state in [:stopped, :completed],
       do: {:ok, realized_contact}

  defp mark_realized_contact_stopped(%RealizedContact{} = realized_contact, metadata_patch) do
    update_realized_contact_lifecycle(
      realized_contact,
      :stopped,
      metadata_patch
    )
  end

  defp complete_realized_contact(
         %RealizedContact{} = realized_contact,
         metadata_patch
       )
       when is_map(metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized_contact(realized_contact),
         {:ok, %RealizedContact{} = completed_realized_contact} <-
           update_realized_contact_lifecycle(
             persisted_realized_contact,
             :completed,
             metadata_patch
           ),
         :ok <-
           Runtime.stop_realized_contact_sync(
             completed_realized_contact.mission_id,
             completed_realized_contact.realized_contact_id
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
    |> Multi.run(:contact_action_operational_event, fn repo, %{contact_action: row} ->
      row
      |> ContactActionRow.to_domain()
      |> OperationalEvent.from_contact_action()
      |> then(&OperationalEvents.persist_event(repo, &1))
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
        Multi.new()
        |> Multi.update(
          :scheduled_contact,
          ScheduledContactRow.lifecycle_changeset(row, lifecycle_state, metadata_patch)
        )
        |> Multi.run(:operational_event, fn repo, %{scheduled_contact: updated_row} ->
          updated_row
          |> ScheduledContactRow.to_domain()
          |> persist_contact_operational_event(repo)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{scheduled_contact: %ScheduledContactRow{} = updated_row}} ->
            {:ok, ScheduledContactRow.to_domain(updated_row)}

          {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
            {:error, changeset}

          {:error, _operation, reason, _changes_so_far} ->
            {:error, reason}
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
        Multi.new()
        |> Multi.update(
          :realized_contact,
          RealizedContactRow.lifecycle_changeset(row, lifecycle_state, metadata_patch)
        )
        |> Multi.run(:operational_event, fn repo, %{realized_contact: updated_row} ->
          updated_row
          |> RealizedContactRow.to_domain()
          |> persist_contact_operational_event(repo)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{realized_contact: %RealizedContactRow{} = updated_row}} ->
            {:ok, RealizedContactRow.to_domain(updated_row)}

          {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
            {:error, changeset}

          {:error, _operation, reason, _changes_so_far} ->
            {:error, reason}
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
          contact_intents: scheduled_contact.contact_intents,
          link_assignment_refs: scheduled_contact.link_assignment_refs,
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
         contact_intents: scheduled_contact.contact_intents,
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
    with {:ok, assignment_paths} <-
           resolve_link_assignment_paths(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.link_assignment_refs
           ),
         {:ok, template_paths} <-
           resolve_path_templates(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.path_template_ids,
             scheduled_contact.path_template_refs
           ) do
      {:ok, assignment_paths ++ template_paths ++ scheduled_contact.paths}
    end
  end

  defp resolve_link_assignment_paths(_organization_id, _mission_id, []), do: {:ok, []}

  defp resolve_link_assignment_paths(organization_id, mission_id, link_assignment_refs)
       when is_binary(mission_id) and is_list(link_assignment_refs) do
    Enum.reduce_while(link_assignment_refs, {:ok, []}, fn ref, {:ok, acc} ->
      with {:ok, %LinkAssignment{} = assignment} <-
             fetch_link_assignment_ref_for_scope(organization_id, mission_id, ref),
           {:ok, %PathTemplate{} = path_template} <-
             fetch_path_template_ref_for_scope(organization_id, mission_id, %{
               "path_template_id" => assignment.path_template_id,
               "version" => assignment.path_template_version
             }),
           {:ok, %Path{} = resolved_path} <-
             assignment_path_template(assignment, path_template)
             |> resolve_path_template() do
        {:cont, {:ok, acc ++ [resolved_path]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp assignment_path_template(%LinkAssignment{} = assignment, %PathTemplate{} = path_template) do
    provider_profile_refs =
      if assignment.provider_profile_refs == [] do
        path_template.provider_profile_refs
      else
        assignment.provider_profile_refs
      end

    transport_profile_refs =
      if assignment.transport_profile_refs == [] do
        path_template.transport_profile_refs
      else
        assignment.transport_profile_refs
      end

    metadata =
      path_template.metadata
      |> Map.merge(assignment.metadata)
      |> Map.put("link_assignment_id", assignment.link_assignment_id)
      |> Map.put("spacecraft_id", assignment.spacecraft_id)

    %PathTemplate{
      path_template
      | path_id: assignment.link_assignment_id,
        direction: assignment.direction,
        selection_role: assignment.selection_role,
        source_endpoint_ref: assignment.source_endpoint_ref,
        provider_path_ref: assignment.provider_path_ref || path_template.provider_path_ref,
        provider_profile_ids: ids_from_refs(provider_profile_refs, "provider_profile_id"),
        provider_profile_refs: provider_profile_refs,
        transport_profile_ids: ids_from_refs(transport_profile_refs, "transport_profile_id"),
        transport_profile_refs: transport_profile_refs,
        metadata: metadata
    }
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

  defp fetch_link_assignment_for_scope(organization_id, mission_id, link_assignment_id)
       when is_binary(organization_id) and organization_id != "" do
    fetch_link_assignment(organization_id, mission_id, link_assignment_id)
  end

  defp fetch_link_assignment_for_scope(_organization_id, mission_id, link_assignment_id) do
    fetch_link_assignment(mission_id, link_assignment_id)
  end

  defp fetch_link_assignment_ref_for_scope(organization_id, mission_id, ref) do
    case Map.get(ref, "link_assignment_id") do
      link_assignment_id when is_binary(link_assignment_id) and link_assignment_id != "" ->
        fetch_link_assignment_for_scope(organization_id, mission_id, link_assignment_id)

      _other ->
        {:error, :invalid_contact_runtime_config_reference}
    end
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
         | source_endpoint_ref: nil,
           provider_profile_ids: ids_from_refs(provider_profile_refs, "provider_profile_id"),
           provider_profile_refs: provider_profile_refs,
           transport_profile_ids: ids_from_refs(transport_profile_refs, "transport_profile_id"),
           transport_profile_refs: transport_profile_refs
       }}
    end
  end

  defp prepare_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    with :ok <- validate_ref_list(scheduled_contact.link_assignment_refs, "link_assignment_id"),
         {:ok, link_assignments} <-
           resolve_link_assignment_refs(
             scheduled_contact.organization_id,
             scheduled_contact.mission_id,
             scheduled_contact.link_assignment_refs
           ),
         :ok <-
           validate_reusable_path_refs(
             ids_from_refs(scheduled_contact.link_assignment_refs, "link_assignment_id")
           ),
         {:ok, path_template_refs} <-
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
      source_endpoint_refs =
        scheduled_contact.source_endpoint_refs
        |> Kernel.++(Enum.map(link_assignments, & &1.source_endpoint_ref))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      {:ok,
       %ScheduledContact{
         scheduled_contact
         | source_endpoint_refs: source_endpoint_refs,
           link_assignment_refs: Enum.map(link_assignments, &link_assignment_ref_from_resource/1),
           path_template_ids: ids_from_refs(path_template_refs, "path_template_id"),
           path_template_refs: path_template_refs
       }}
    end
  end

  defp resolve_link_assignment_refs(organization_id, mission_id, link_assignment_refs)
       when is_list(link_assignment_refs) do
    Enum.reduce_while(link_assignment_refs, {:ok, []}, fn ref, {:ok, acc} ->
      case fetch_link_assignment_ref_for_scope(organization_id, mission_id, ref) do
        {:ok, %LinkAssignment{} = assignment} -> {:cont, {:ok, acc ++ [assignment]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp link_assignment_ref_from_resource(%LinkAssignment{} = assignment) do
    %{"link_assignment_id" => assignment.link_assignment_id}
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
         source_endpoint_ref: nil,
         provider_path_ref: Map.get(attrs, :provider_path_ref, path_template.provider_path_ref),
         provider_profile_ids: provider_profile_ids,
         provider_profile_refs: provider_profile_refs,
         transport_profile_ids: transport_profile_ids,
         transport_profile_refs: transport_profile_refs,
         metadata: Map.merge(path_template.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  defp list_due_scheduled_contacts(%DateTime{} = reference_time, mission_id) do
    ScheduledContactRow
    |> where(
      [row],
      row.lifecycle_state == "scheduled" and row.starts_at <= ^reference_time and
        (is_nil(row.ends_at) or row.ends_at > ^reference_time)
    )
    |> maybe_filter_scheduled_contacts_by_mission(mission_id)
    |> order_by([row], asc: row.starts_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp list_expired_scheduled_contacts(%DateTime{} = reference_time, mission_id) do
    ScheduledContactRow
    |> where(
      [row],
      row.lifecycle_state == "scheduled" and not is_nil(row.ends_at) and
        row.ends_at <= ^reference_time
    )
    |> maybe_filter_scheduled_contacts_by_mission(mission_id)
    |> order_by([row], asc: row.ends_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp list_completed_scheduled_contacts(%DateTime{} = reference_time, mission_id) do
    ScheduledContactRow
    |> where(
      [row],
      row.lifecycle_state == "realized" and not is_nil(row.ends_at) and
        row.ends_at <= ^reference_time
    )
    |> maybe_filter_scheduled_contacts_by_mission(mission_id)
    |> order_by([row], asc: row.ends_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  defp list_active_realized_contacts_to_restart(%DateTime{} = reference_time, mission_id) do
    RealizedContactRow
    |> join(
      :left,
      [realized_contact_row],
      scheduled_contact_row in ScheduledContactRow,
      on:
        realized_contact_row.mission_id == scheduled_contact_row.mission_id and
          realized_contact_row.scheduled_contact_id == scheduled_contact_row.scheduled_contact_id
    )
    |> where(
      [realized_contact_row, scheduled_contact_row],
      realized_contact_row.lifecycle_state == "active" and
        (is_nil(scheduled_contact_row.scheduled_contact_id) or
           is_nil(scheduled_contact_row.ends_at) or
           scheduled_contact_row.ends_at > ^reference_time)
    )
    |> maybe_filter_joined_realized_contacts_by_mission(mission_id)
    |> order_by([realized_contact_row, _scheduled_contact_row],
      asc: realized_contact_row.realized_at,
      asc: realized_contact_row.realized_contact_id
    )
    |> select([realized_contact_row, _scheduled_contact_row], realized_contact_row)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  defp list_expired_active_realized_contacts(%DateTime{} = reference_time, mission_id) do
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
    |> maybe_filter_joined_realized_contacts_by_mission(mission_id)
    |> order_by(
      [realized_contact_row, scheduled_contact_row],
      asc: scheduled_contact_row.ends_at,
      asc: realized_contact_row.realized_contact_id
    )
    |> select([realized_contact_row, _scheduled_contact_row], realized_contact_row)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  defp maybe_filter_scheduled_contacts_by_mission(query, nil), do: query

  defp maybe_filter_scheduled_contacts_by_mission(query, mission_id) when is_binary(mission_id) do
    where(query, [row], row.mission_id == ^mission_id)
  end

  defp maybe_filter_joined_realized_contacts_by_mission(query, nil), do: query

  defp maybe_filter_joined_realized_contacts_by_mission(query, mission_id)
       when is_binary(mission_id) do
    where(
      query,
      [realized_contact_row, _scheduled_contact_row],
      realized_contact_row.mission_id == ^mission_id
    )
  end

  defp scheduled_contact_scheduler_wakeups(%ScheduledContactRow{} = row, reference_time) do
    case row.lifecycle_state do
      "scheduled" ->
        scheduled_contact_scheduled_wakeup(row, reference_time)

      "realized" ->
        scheduled_contact_realized_wakeup(row, reference_time)
    end
  end

  defp scheduled_contact_scheduled_wakeup(
         %ScheduledContactRow{ends_at: %DateTime{} = ends_at} = row,
         reference_time
       ) do
    cond do
      DateTime.compare(ends_at, reference_time) != :gt ->
        [%{mission_id: row.mission_id, wake_at: reference_time}]

      DateTime.compare(row.starts_at, reference_time) != :gt ->
        [%{mission_id: row.mission_id, wake_at: reference_time}]

      true ->
        [%{mission_id: row.mission_id, wake_at: row.starts_at}]
    end
  end

  defp scheduled_contact_scheduled_wakeup(%ScheduledContactRow{} = row, reference_time) do
    if DateTime.compare(row.starts_at, reference_time) == :gt do
      [%{mission_id: row.mission_id, wake_at: row.starts_at}]
    else
      [%{mission_id: row.mission_id, wake_at: reference_time}]
    end
  end

  defp scheduled_contact_realized_wakeup(%ScheduledContactRow{ends_at: nil}, _reference_time),
    do: []

  defp scheduled_contact_realized_wakeup(
         %ScheduledContactRow{ends_at: ends_at} = row,
         reference_time
       ) do
    [%{mission_id: row.mission_id, wake_at: max_datetime(ends_at, reference_time)}]
  end

  defp normalize_scheduler_wakeup(%{wake_at: %DateTime{} = wake_at} = wakeup, reference_time) do
    %{wakeup | wake_at: max_datetime(wake_at, reference_time)}
  end

  defp group_scheduler_wakeups(wakeups) do
    wakeups
    |> Enum.group_by(& &1.mission_id)
    |> Enum.map(fn {mission_id, mission_wakeups} ->
      %{
        mission_id: mission_id,
        wake_at: Enum.min_by(mission_wakeups, &datetime_sort_key(&1.wake_at)).wake_at
      }
    end)
  end

  defp max_datetime(%DateTime{} = datetime, %DateTime{} = minimum) do
    if DateTime.compare(datetime, minimum) == :lt, do: minimum, else: datetime
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp persist_contact_operational_event(%ScheduledContact{} = scheduled_contact, repo) do
    scheduled_contact
    |> OperationalEvent.from_scheduled_contact_interval()
    |> then(&OperationalEvents.persist_event(repo, &1))
  end

  defp persist_contact_operational_event(%RealizedContact{} = realized_contact, repo) do
    realized_contact
    |> OperationalEvent.from_realized_contact_interval()
    |> then(&OperationalEvents.persist_event(repo, &1))
  end

  defp notify_contact_changed(%ScheduledContact{} = scheduled_contact) do
    Scheduler.notify_contact_changed(scheduled_contact)
    invalidate_dashboard_events(scheduled_contact)
    {:ok, scheduled_contact}
  end

  defp notify_contact_changed(%RealizedContact{} = realized_contact) do
    Scheduler.notify_contact_changed(realized_contact)
    Cadence.Commanding.notify_release_target_available(realized_contact)
    invalidate_dashboard_events(realized_contact)
    {:ok, realized_contact}
  end

  defp maybe_notify_contact_changed(contact, opts) do
    if Keyword.get(opts, :notify_scheduler?, true) do
      notify_contact_changed(contact)
    else
      {:ok, contact}
    end
  end

  defp invalidate_dashboard_events(%{organization_id: organization_id, mission_id: mission_id})
       when is_binary(organization_id) and is_binary(mission_id) do
    RuntimeInvalidation.events_changed(%{
      organization_id: organization_id,
      mission_id: mission_id
    })

    :ok
  end

  defp invalidate_dashboard_events(_contact), do: :ok

  defp realized_scheduled_contact_projection(
         %ScheduledContact{} = scheduled_contact,
         %RealizedContact{} = realized_contact
       ) do
    %ScheduledContact{
      scheduled_contact
      | lifecycle_state: :realized,
        realized_contact_id: realized_contact.realized_contact_id
    }
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

  defp shared_link_context(organization_id, mission_id, attrs) do
    with {:ok, display_name} <- required_text(attrs["display_name"], "Link name is required."),
         {:ok, direction} <- shared_link_direction(attrs["direction"]),
         {:ok, selection_role} <- selection_role(attrs["selection_role"]),
         {:ok, provider_configuration} <- provider_configuration(attrs, direction),
         {:ok, heartbeat_enabled} <- boolean(attrs["heartbeat_enabled"]),
         {:ok, heartbeat_interval_ms} <-
           heartbeat_interval(attrs["heartbeat_interval_ms"], heartbeat_enabled) do
      {:ok,
       %{
         organization_id: organization_id,
         mission_id: mission_id,
         display_name: display_name,
         direction: direction,
         selection_role: selection_role,
         provider_configuration: provider_configuration,
         heartbeat_enabled: heartbeat_enabled,
         heartbeat_interval_ms: heartbeat_interval_ms,
         attrs: attrs
       }}
    end
  end

  defp unwrap_transaction_result({:ok, result}), do: result
  defp unwrap_transaction_result({:error, reason}), do: Repo.rollback(reason)

  defp persist_shared_link_records(context) do
    %{
      organization_id: organization_id,
      mission_id: mission_id,
      display_name: display_name,
      direction: direction,
      selection_role: selection_role,
      provider_configuration: provider_configuration,
      heartbeat_enabled: heartbeat_enabled,
      heartbeat_interval_ms: heartbeat_interval_ms,
      attrs: attrs
    } = context

    with {:ok, provider} <-
           persist_shared_link_provider(
             organization_id,
             mission_id,
             display_name,
             provider_configuration
           ),
         {:ok, transport} <-
           maybe_persist_heartbeat(
             organization_id,
             mission_id,
             display_name,
             heartbeat_enabled,
             heartbeat_interval_ms
           ),
         {:ok, path_templates} <-
           persist_shared_link_path_templates(
             organization_id,
             mission_id,
             display_name,
             direction,
             selection_role,
             provider,
             transport,
             attrs
           ) do
      {:ok, %{provider: provider, transport: transport, path_templates: path_templates}}
    end
  end

  defp persist_shared_link_provider(organization_id, mission_id, display_name, configuration) do
    provider =
      ProviderProfile.new(%{
        mission_id: mission_id,
        adapter_key: :tcp_socket,
        configuration: configuration,
        metadata: %{"display_name" => "#{display_name} Provider"}
      })

    persist_provider_profile(organization_id, provider)
  end

  defp maybe_persist_heartbeat(
         organization_id,
         mission_id,
         display_name,
         true,
         heartbeat_interval_ms
       ) do
    transport =
      TransportProfile.new(%{
        mission_id: mission_id,
        family_key: :heartbeat_monitor,
        target_scope: :path,
        configuration: %{"heartbeat_interval_ms" => heartbeat_interval_ms},
        metadata: %{"display_name" => "#{display_name} Heartbeat"}
      })

    persist_transport_profile(organization_id, transport)
  end

  defp maybe_persist_heartbeat(_organization_id, _mission_id, _display_name, false, _interval) do
    {:ok, nil}
  end

  defp persist_shared_link_path_templates(
         organization_id,
         mission_id,
         display_name,
         direction,
         selection_role,
         provider,
         transport,
         attrs
       ) do
    direction
    |> path_directions()
    |> Enum.reduce_while({:ok, []}, fn path_direction, {:ok, path_templates} ->
      path_template =
        PathTemplate.new(%{
          mission_id: mission_id,
          direction: path_direction,
          selection_role: selection_role,
          source_endpoint_ref: nil,
          provider_path_ref: provider_path_ref(attrs, display_name, path_direction),
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          transport_profile_refs: transport_refs(transport),
          metadata: %{
            "display_name" => path_display_name(display_name, direction, path_direction),
            "created_from_link_builder" => true
          }
        })

      case persist_path_template(organization_id, path_template) do
        {:ok, path_template} -> {:cont, {:ok, [path_template | path_templates]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, path_templates} -> {:ok, Enum.reverse(path_templates)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_link_template_row(
         organization_id,
         mission_id,
         source_template,
         spacecraft,
         attrs,
         source_endpoints,
         path_templates,
         link_assignments
       ) do
    endpoint_refs = endpoint_refs_for_spacecraft(spacecraft, source_endpoints)

    cond do
      is_nil(spacecraft.scid) ->
        application_row(
          spacecraft,
          :skipped,
          :info,
          "Skipped",
          "Set SCID before Cadence can generate a spacecraft telemetry identity."
        )

      assigned_path_exists?(endpoint_refs, path_templates, link_assignments, source_template) ->
        application_row(
          spacecraft,
          :skipped,
          :info,
          "Skipped",
          "#{source_template.direction |> Atom.to_string() |> String.upcase()} #{human_atom(source_template.selection_role)} link already exists."
        )

      true ->
        apply_available_link_template_row(
          organization_id,
          mission_id,
          source_template,
          spacecraft,
          attrs,
          path_templates,
          link_assignments
        )
    end
  end

  defp apply_available_link_template_row(
         organization_id,
         mission_id,
         source_template,
         spacecraft,
         attrs,
         path_templates,
         link_assignments
       ) do
    provider_path_ref =
      render_pattern(attrs["provider_path_ref_pattern"], spacecraft, source_template.direction)

    if provider_path_ref_collision?(provider_path_ref, path_templates, link_assignments) do
      application_row(
        spacecraft,
        :skipped,
        :attention,
        "Conflict",
        "Provider path ref #{provider_path_ref} is already used by another link template."
      )
    else
      persist_spacecraft_link_assignment(
        organization_id,
        mission_id,
        source_template,
        spacecraft,
        attrs,
        provider_path_ref
      )
    end
  end

  defp persist_spacecraft_link_assignment(
         organization_id,
         mission_id,
         source_template,
         spacecraft,
         attrs,
         provider_path_ref
       ) do
    with {:ok, endpoint} <-
           SpacecraftStore.ensure_managed_source_endpoint(organization_id, spacecraft),
         {:ok, _assignment} <-
           persist_link_assignment(
             organization_id,
             LinkAssignment.new(%{
               mission_id: mission_id,
               spacecraft_id: spacecraft.spacecraft_id,
               path_template_id: source_template.path_template_id,
               path_template_version: source_template.version,
               direction: source_template.direction,
               selection_role: source_template.selection_role,
               source_endpoint_ref: endpoint.source_endpoint_id,
               provider_path_ref: provider_path_ref,
               provider_profile_refs: source_template.provider_profile_refs,
               transport_profile_refs: source_template.transport_profile_refs,
               metadata:
                 Map.merge(source_template.metadata, %{
                   "display_name" =>
                     render_pattern(
                       attrs["display_name_pattern"],
                       spacecraft,
                       source_template.direction
                     ),
                   "applied_from_template_ui" => true,
                   "source_path_template_id" => source_template.path_template_id,
                   "source_path_template_version" => source_template.version
                 })
             })
           ) do
      application_row(spacecraft, :applied, :ready, "Applied", "Link assignment was created.")
    else
      {:error, reason} ->
        application_row(spacecraft, :failed, :blocked, "Failed", inspect(reason))
    end
  end

  defp application_row(spacecraft, kind, status, label, detail) do
    %{
      id: spacecraft.spacecraft_id,
      spacecraft: spacecraft,
      kind: kind,
      status: status,
      label: label,
      detail: detail
    }
  end

  defp endpoint_refs_for_spacecraft(spacecraft, source_endpoints) do
    managed_id = "spacecraft_runtime:" <> spacecraft.spacecraft_id

    endpoint_refs =
      Enum.flat_map(source_endpoints, fn endpoint ->
        if endpoint_matches_spacecraft?(endpoint, spacecraft) do
          [endpoint.source_endpoint_id]
        else
          []
        end
      end)

    Enum.uniq([managed_id | endpoint_refs])
  end

  defp endpoint_matches_spacecraft?(endpoint, spacecraft) do
    endpoint.spacecraft_id == spacecraft.spacecraft_id
  end

  defp assigned_path_exists?(endpoint_refs, _path_templates, link_assignments, source_template) do
    Enum.any?(link_assignments, fn assignment ->
      assignment.source_endpoint_ref in endpoint_refs and
        assignment.direction == source_template.direction and
        assignment.selection_role == source_template.selection_role and
        assignment.provider_profile_refs != []
    end)
  end

  defp provider_path_ref_collision?(nil, _path_templates, _link_assignments), do: false

  defp provider_path_ref_collision?(provider_path_ref, path_templates, link_assignments) do
    Enum.any?(path_templates, &(&1.provider_path_ref == provider_path_ref)) or
      Enum.any?(link_assignments, &(&1.provider_path_ref == provider_path_ref))
  end

  defp provider_configuration(attrs, direction) do
    with {:ok, mode} <- tcp_mode(attrs["tcp_mode"]),
         {:ok, provider_direction} <- provider_direction(direction),
         {:ok, host} <- required_text(attrs["host"], "Host is required."),
         {:ok, port} <- port(attrs["port"]),
         {:ok, framing_mode} <- framing_mode(attrs["framing_mode"]),
         {:ok, frame_size} <- frame_size(attrs["frame_size"], framing_mode),
         {:ok, tls_enabled} <- boolean(attrs["tls_enabled"]) do
      {:ok,
       %{
         "adapter" => "tcp_socket",
         "mode" => mode,
         "direction" => provider_direction,
         "host" => host,
         "port" => port,
         "framing" => compact(%{"mode" => framing_mode, "fixed_message_bytes" => frame_size}),
         "tls" => %{"enabled" => tls_enabled},
         "reconnect" => reconnect_configuration(mode)
       }
       |> maybe_put_fixed_message_bytes(frame_size)}
    end
  end

  defp required_text(value, message) do
    case normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil

  defp render_pattern(pattern, spacecraft, direction) do
    (normalize_text(pattern) || "{spacecraft_name} {direction}")
    |> String.replace("{spacecraft_id}", spacecraft.spacecraft_id)
    |> String.replace("{spacecraft_name}", spacecraft.display_name)
    |> String.replace("{scid}", Integer.to_string(spacecraft.scid))
    |> String.replace("{direction}", Atom.to_string(direction))
  end

  defp heartbeat_interval(_value, false), do: {:ok, nil}

  defp heartbeat_interval(value, true) do
    case parse_integer(value) do
      {:ok, interval} when interval > 0 -> {:ok, interval}
      _other -> {:error, "Heartbeat interval must be a positive integer."}
    end
  end

  defp tcp_mode("listen"), do: {:ok, "listen"}
  defp tcp_mode("connect"), do: {:ok, "connect"}
  defp tcp_mode(_value), do: {:error, "TCP mode is invalid."}

  defp shared_link_direction("downlink"), do: {:ok, :downlink}
  defp shared_link_direction("uplink"), do: {:ok, :uplink}
  defp shared_link_direction("bidirectional"), do: {:ok, :bidirectional}
  defp shared_link_direction(_value), do: {:error, "Direction is invalid."}

  defp provider_direction(:downlink), do: {:ok, "downlink"}
  defp provider_direction(:uplink), do: {:ok, "uplink"}
  defp provider_direction(:bidirectional), do: {:ok, "bidirectional"}

  defp selection_role("selected"), do: {:ok, :selected}
  defp selection_role("candidate"), do: {:ok, :candidate}
  defp selection_role("contributing"), do: {:ok, :contributing}
  defp selection_role(_value), do: {:error, "Assignment role is invalid."}

  defp port(value) do
    case parse_integer(value) do
      {:ok, port} when port >= 1 and port <= 65_535 -> {:ok, port}
      _other -> {:error, "Port must be an integer from 1 to 65535."}
    end
  end

  defp framing_mode("raw"), do: {:ok, "raw"}
  defp framing_mode("fixed_size"), do: {:ok, "fixed_size"}
  defp framing_mode("line_delimited"), do: {:ok, "line_delimited"}
  defp framing_mode(_value), do: {:error, "Framing mode is invalid."}

  defp frame_size(value, "fixed_size") do
    case parse_integer(value) do
      {:ok, frame_size} when frame_size > 0 -> {:ok, frame_size}
      _other -> {:error, "Fixed frame size must be a positive integer."}
    end
  end

  defp frame_size(_value, _framing_mode), do: {:ok, nil}

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(true), do: {:ok, true}
  defp boolean(false), do: {:ok, false}
  defp boolean(_value), do: {:error, "Boolean option is invalid."}

  defp reconnect_configuration("connect"), do: %{"policy" => "always"}
  defp reconnect_configuration("listen"), do: %{"policy" => "on_disconnect"}

  defp maybe_put_fixed_message_bytes(configuration, nil), do: configuration

  defp maybe_put_fixed_message_bytes(configuration, frame_size) do
    Map.put(configuration, "fixed_message_bytes", frame_size)
  end

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_value), do: :error

  defp path_directions(:bidirectional), do: [:downlink, :uplink]
  defp path_directions(direction), do: [direction]

  defp path_display_name(display_name, :bidirectional, direction) do
    "#{display_name} #{human_atom(direction)}"
  end

  defp path_display_name(display_name, _builder_direction, _path_direction), do: display_name

  defp provider_path_ref(attrs, display_name, direction) do
    case normalize_text(attrs["provider_path_ref"]) do
      nil -> "#{slug(display_name)}-#{Atom.to_string(direction)}"
      value -> value
    end
  end

  defp transport_refs(nil), do: []

  defp transport_refs(transport) do
    [%{"transport_profile_id" => transport.transport_profile_id, "version" => transport.version}]
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp human_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
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

  defp put_organization_scope(%LinkAssignment{} = assignment, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case assignment.organization_id do
      nil ->
        {:ok, %LinkAssignment{assignment | organization_id: organization_id}}

      ^organization_id ->
        {:ok, assignment}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          assignment.mission_id}}
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
