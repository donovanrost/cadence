defmodule Cadence.Contacts.ContactStore do
  @moduledoc """
  Persists scheduled contacts, realized contacts, and their lifecycle actions.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Contacts.ContactAction
  alias Cadence.Contacts.ContactStore.ContactActionRow
  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Contacts.ScheduledContactRevisions
  alias Cadence.Contacts.Scheduler
  alias Cadence.Contacts.SchedulerReadModel
  alias Cadence.Contacts.Validation
  alias Cadence.Control.Commanding
  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Repo

  @spec persist_scheduled(ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled(%ScheduledContact{} = scheduled_contact) do
    Multi.new()
    |> Multi.insert(
      :scheduled_contact,
      ScheduledContactRow.changeset(scheduled_contact),
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

  @spec fetch_scheduled(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled(mission_id, scheduled_contact_id)
      when is_binary(mission_id) and is_binary(scheduled_contact_id) do
    case Repo.get_by(ScheduledContactRow,
           mission_id: mission_id,
           scheduled_contact_id: scheduled_contact_id
         ) do
      nil -> {:error, :scheduled_contact_not_found}
      %ScheduledContactRow{} = row -> {:ok, ScheduledContactRow.to_domain(row)}
    end
  end

  @spec fetch_scheduled(binary(), binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled(organization_id, mission_id, scheduled_contact_id)
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

  @spec fetch_scheduled_by_provider_ref(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, :scheduled_contact_not_found}
  def fetch_scheduled_by_provider_ref(mission_id, provider_contact_ref)
      when is_binary(mission_id) and is_binary(provider_contact_ref) do
    case Repo.get_by(ScheduledContactRow,
           mission_id: mission_id,
           provider_contact_ref: provider_contact_ref
         ) do
      nil -> {:error, :scheduled_contact_not_found}
      %ScheduledContactRow{} = row -> {:ok, ScheduledContactRow.to_domain(row)}
    end
  end

  @spec list_scheduled(binary()) :: [ScheduledContact.t()]
  def list_scheduled(mission_id) when is_binary(mission_id) do
    ScheduledContactRow
    |> where([row], row.mission_id == ^mission_id)
    |> order_by([row], asc: row.starts_at, asc: row.scheduled_contact_id)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end

  @spec list_scheduled(binary(), binary()) :: [ScheduledContact.t()]
  def list_scheduled(organization_id, mission_id)
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

  @spec list_actions(binary(), keyword()) :: [ContactAction.t()]
  def list_actions(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    ContactActionRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter_contact_actions(opts)
    |> order_by([row], asc: row.occurred_at, asc: row.contact_action_id)
    |> Repo.all()
    |> Enum.map(&ContactActionRow.to_domain/1)
  end

  @spec list_actions(binary(), binary(), keyword()) :: [ContactAction.t()]
  def list_actions(organization_id, mission_id, opts)
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

  @spec persist_realized(RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized(%RealizedContact{} = realized_contact) do
    with :ok <- Validation.realized_contact(realized_contact) do
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

  @spec fetch_realized(binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    case Repo.get_by(RealizedContactRow,
           mission_id: mission_id,
           realized_contact_id: realized_contact_id
         ) do
      nil -> {:error, :realized_contact_not_found}
      %RealizedContactRow{} = row -> {:ok, RealizedContactRow.to_domain(row)}
    end
  end

  @spec fetch_realized(binary(), binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized(organization_id, mission_id, realized_contact_id)
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

  @spec list_realized(binary()) :: [RealizedContact.t()]
  def list_realized(mission_id) when is_binary(mission_id) do
    RealizedContactRow
    |> where([row], row.mission_id == ^mission_id)
    |> order_by([row], asc: row.realized_at, asc: row.realized_contact_id)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  @spec list_realized(binary(), binary()) :: [RealizedContact.t()]
  def list_realized(organization_id, mission_id)
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

  @spec persist_action(ContactAction.t()) :: {:ok, ContactAction.t()} | {:error, term()}
  def persist_action(%ContactAction{} = contact_action) do
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

  @spec persist_realization(ScheduledContact.t(), RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realization(
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

  @spec update_scheduled_lifecycle(ScheduledContact.t(), atom(), map()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def update_scheduled_lifecycle(
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

  @spec update_realized_lifecycle(RealizedContact.t(), atom(), map()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def update_realized_lifecycle(
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

  @spec due_scheduled(DateTime.t(), binary() | nil) :: [ScheduledContact.t()]
  def due_scheduled(%DateTime{} = reference_time, mission_id) do
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

  @spec expired_scheduled(DateTime.t(), binary() | nil) :: [ScheduledContact.t()]
  def expired_scheduled(%DateTime{} = reference_time, mission_id) do
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

  @spec completed_scheduled(DateTime.t(), binary() | nil) :: [ScheduledContact.t()]
  def completed_scheduled(%DateTime{} = reference_time, mission_id) do
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

  @spec active_realized_to_restart(DateTime.t(), binary() | nil) :: [RealizedContact.t()]
  def active_realized_to_restart(%DateTime{} = reference_time, mission_id) do
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

  @spec expired_active_realized(DateTime.t(), binary() | nil) :: [RealizedContact.t()]
  def expired_active_realized(%DateTime{} = reference_time, mission_id) do
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

  @spec scheduler_wakeups(DateTime.t(), binary() | nil) :: [
          %{mission_id: binary(), wake_at: DateTime.t()}
        ]
  def scheduler_wakeups(%DateTime{} = reference_time, mission_id) do
    scheduled_contacts =
      ScheduledContactRow
      |> where([row], row.lifecycle_state in ["scheduled", "realized"])
      |> maybe_filter_scheduled_contacts_by_mission(mission_id)
      |> Repo.all()
      |> Enum.map(&ScheduledContactRow.to_domain/1)

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

    SchedulerReadModel.wakeups(scheduled_contacts, active_realized_wakeups, reference_time)
  end

  @spec scheduler_projection(binary()) :: %{
          scheduled_contacts: %{optional(binary()) => ScheduledContact.t()}
        }
  def scheduler_projection(mission_id) when is_binary(mission_id) do
    ScheduledContactRow
    |> where(
      [row],
      row.mission_id == ^mission_id and row.lifecycle_state in ["scheduled", "realized"]
    )
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
    |> SchedulerReadModel.projection()
  end

  @spec notify_contact_changed(ScheduledContact.t() | RealizedContact.t()) ::
          {:ok, ScheduledContact.t() | RealizedContact.t()}
  def notify_contact_changed(%ScheduledContact{} = scheduled_contact) do
    Scheduler.notify_contact_changed(scheduled_contact)
    invalidate_dashboard_events(scheduled_contact)
    {:ok, scheduled_contact}
  end

  def notify_contact_changed(%RealizedContact{} = realized_contact) do
    Scheduler.notify_contact_changed(realized_contact)
    Commanding.notify_release_target_available(realized_contact)
    invalidate_dashboard_events(realized_contact)
    {:ok, realized_contact}
  end

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

  defp invalidate_dashboard_events(%{organization_id: organization_id, mission_id: mission_id})
       when is_binary(organization_id) and is_binary(mission_id) do
    RuntimeInvalidation.events_changed(%{
      organization_id: organization_id,
      mission_id: mission_id
    })

    :ok
  end

  defp invalidate_dashboard_events(_contact), do: :ok

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
end
