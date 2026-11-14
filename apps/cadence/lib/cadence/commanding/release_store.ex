defmodule Cadence.Commanding.ReleaseStore do
  @moduledoc """
  Persists and retrieves command release attempts.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequestRow
  }

  alias Cadence.Repo

  @spec persist(binary(), CommandReleaseAttempt.t()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def persist(organization_id, %CommandReleaseAttempt{} = command_release_attempt)
      when is_binary(organization_id) do
    with {:ok, scoped_command_release_attempt} <-
           put_organization_scope(command_release_attempt, organization_id),
         {:ok, %CommandReleaseAttemptRow{} = row} <-
           Repo.insert(CommandReleaseAttemptRow.changeset(scoped_command_release_attempt),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_release_attempt_id]
           ) do
      {:ok, CommandReleaseAttemptRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Records a release refused before anything was sent (SAFETY #38: the contact, path or gateway
  doesn't belong to the request's target spacecraft), as develop does: the attempt fails and its
  request and queue entry close.

  The rows are re-read under lock in the transaction (request, then queue entry, then attempt).
  The command closes only if it is still exactly as this release claimed it (entry
  `release_pending`, request `queued`), and the attempt fails only if it is still
  `release_pending`, so a concurrent cancel, abort or completion is never overwritten.
  `closed: false` says the command had already moved on.
  """
  @spec mark_refused(struct(), struct(), CommandReleaseAttempt.t(), term()) ::
          {:ok, %{closed: boolean()}} | {:error, term()}
  def mark_refused(queue_entry_row, request_row, %CommandReleaseAttempt{} = attempt, reason) do
    Repo.transaction(fn ->
      request = lock_row(CommandRequestRow, :command_request_id, request_row)
      queue = lock_row(CommandQueueEntryRow, :command_queue_entry_id, queue_entry_row)
      attempt_row = lock_row(CommandReleaseAttemptRow, :command_release_attempt_id, attempt)

      :ok = fail_pending_attempt(attempt_row, attempt, reason)

      closes? =
        match?(%{lifecycle_state: "release_pending"}, queue) and
          match?(%{lifecycle_state: "queued"}, request)

      if closes? do
        {:ok, _queue} = Repo.update(CommandQueueEntryRow.lifecycle_changeset(queue, :canceled))
        {:ok, _request} = Repo.update(CommandRequestRow.lifecycle_changeset(request, :canceled))
      end

      %{closed: closes?}
    end)
  end

  defp lock_row(schema, id_field, %{organization_id: org, mission_id: mission} = expected) do
    id = Map.fetch!(expected, id_field)

    schema
    |> where([row], row.organization_id == ^org and row.mission_id == ^mission)
    |> where([row], field(row, ^id_field) == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp fail_pending_attempt(
         %CommandReleaseAttemptRow{lifecycle_state: "release_pending"} = row,
         %CommandReleaseAttempt{} = attempt,
         reason
       ) do
    refused = %CommandReleaseAttempt{
      attempt
      | lifecycle_state: :release_failed,
        failure_reason: "refused: " <> inspect(reason),
        released_at: nil
    }

    {:ok, _row} = row |> CommandReleaseAttemptRow.update_changeset(refused) |> Repo.update()
    :ok
  end

  defp fail_pending_attempt(_row_moved_on_or_missing, _attempt, _reason), do: :ok

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def fetch(organization_id, mission_id, command_release_attempt_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_release_attempt_id) do
    with {:ok, %CommandReleaseAttemptRow{} = row} <-
           fetch_row(organization_id, mission_id, command_release_attempt_id) do
      {:ok, CommandReleaseAttemptRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [CommandReleaseAttempt.t()]
  def list(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandReleaseAttemptRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:command_queue_entry_id, Keyword.get(opts, :command_queue_entry_id))
    |> maybe_filter_equals(:realized_contact_id, Keyword.get(opts, :realized_contact_id))
    |> maybe_filter_equals(:lifecycle_state, normalized_filter(opts, :lifecycle_state))
    |> order_by([row], asc: row.attempted_at, asc: row.command_release_attempt_id)
    |> Repo.all()
    |> Enum.map(&CommandReleaseAttemptRow.to_domain/1)
  end

  @spec fetch_row(binary(), binary(), binary()) :: {:ok, struct()} | {:error, term()}
  def fetch_row(organization_id, mission_id, command_release_attempt_id) do
    fetch_row(Repo, organization_id, mission_id, command_release_attempt_id)
  end

  @spec fetch_row(module(), binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, term()}
  def fetch_row(repo, organization_id, mission_id, command_release_attempt_id) do
    case repo.get_by(CommandReleaseAttemptRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_release_attempt_id: command_release_attempt_id
         ) do
      nil -> {:error, :command_release_attempt_not_found}
      %CommandReleaseAttemptRow{} = row -> {:ok, row}
    end
  end

  defp normalized_filter(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp put_organization_scope(%CommandReleaseAttempt{} = command_release_attempt, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_release_attempt.organization_id do
      nil ->
        {:ok, %CommandReleaseAttempt{command_release_attempt | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_release_attempt}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_release_attempt.mission_id}}
    end
  end
end
