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
    CommandRequestRow,
    QueueLaneLock,
    RequestQueueStore
  }

  alias Cadence.Repo

  @spec persist(binary(), CommandReleaseAttempt.t()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def persist(organization_id, %CommandReleaseAttempt{} = command_release_attempt)
      when is_binary(organization_id) do
    with {:ok, scoped_command_release_attempt} <-
           put_organization_scope(command_release_attempt, organization_id),
         {:ok, %CommandReleaseAttemptRow{} = row} <-
           Repo.insert(CommandReleaseAttemptRow.changeset(scoped_command_release_attempt)) do
      {:ok, CommandReleaseAttemptRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Claims the lane and persists its exact attempt atomically, before transmission."
  def claim(%CommandQueueEntryRow{} = queue, %CommandRequestRow{} = request, attempt, opts \\ []) do
    Repo.transaction(fn ->
      with :ok <- matching_basis(queue, request, attempt),
           {:ok, claimed} <-
             RequestQueueStore.claim_for_release(
               queue,
               Keyword.put(opts, :expected_request, request)
             ),
           {:ok, persisted} <- persist(queue.organization_id, attempt),
           {:ok, owned} <-
             Repo.update(
               Changeset.change(claimed,
                 active_release_attempt_id: persisted.command_release_attempt_id
               )
             ) do
        %{queue: owned, attempt: persisted}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Serializes completion with the exact current claim; terminal completion is idempotent."
  def with_claim(queue, request, attempt, complete) when is_function(complete, 3) do
    Repo.transaction(fn ->
      with {:ok, current_request} <- lock_request(request),
           :ok <-
             QueueLaneLock.acquire(queue.organization_id, queue.mission_id, queue.queue_lane_key),
           {:ok, current_queue} <- lock_queue(queue),
           {:ok, current_attempt} <-
             fetch_row(
               attempt.organization_id,
               attempt.mission_id,
               attempt.command_release_attempt_id
             ),
           :ok <-
             current_claim(
               current_queue,
               current_request,
               current_attempt,
               queue,
               request,
               attempt
             ) do
        complete_claim(current_queue, current_request, current_attempt, complete)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Records an ambiguous transmission without reopening its lane or replacing earlier evidence."
  def mark_uncertain(queue, request, attempt, reason) do
    with_claim(queue, request, attempt, fn _queue, _request, row ->
      if row.lifecycle_state == "release_uncertain" do
        {:ok, :retained}
      else
        %CommandReleaseAttempt{} = stored_attempt = CommandReleaseAttemptRow.to_domain(row)

        uncertain = %CommandReleaseAttempt{
          stored_attempt
          | lifecycle_state: :release_uncertain,
            failure_reason: inspect(reason),
            released_at: nil
        }

        row |> CommandReleaseAttemptRow.update_changeset(uncertain) |> Repo.update()
      end
    end)
  end

  defp complete_claim(queue, request, %{lifecycle_state: "released"} = attempt, _complete),
    do: {:already_completed, queue, request, attempt}

  defp complete_claim(queue, request, attempt, complete) do
    case complete.(queue, request, attempt) do
      {:ok, result} -> result
      {:error, _operation, reason, _changes} -> Repo.rollback(reason)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp matching_basis(queue, request, %CommandReleaseAttempt{} = attempt) do
    identity_fields = [
      :organization_id,
      :mission_id,
      :command_queue_entry_id,
      :command_request_id,
      :source_endpoint_ref
    ]

    command_fields = [:mission_model_revision_id, :command_id]
    expected = Map.merge(Map.take(queue, identity_fields), Map.take(request, command_fields))

    if is_nil(queue.active_release_attempt_id) and attempt.lifecycle_state == :release_pending and
         same_request?(queue, request) and
         Map.take(attempt, identity_fields ++ command_fields) == expected,
       do: :ok,
       else: {:error, :command_release_claim_mismatch}
  end

  defp lock_request(expected) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^expected.organization_id and r.mission_id == ^expected.mission_id and
        r.command_request_id == ^expected.command_request_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> found(:command_request_not_found)
  end

  defp lock_queue(expected) do
    CommandQueueEntryRow
    |> where(
      [q],
      q.organization_id == ^expected.organization_id and q.mission_id == ^expected.mission_id and
        q.command_queue_entry_id == ^expected.command_queue_entry_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> found(:command_queue_entry_not_found)
  end

  defp found(nil, reason), do: {:error, reason}
  defp found(row, _reason), do: {:ok, row}

  defp current_claim(queue, request, row, expected_queue, expected_request, attempt) do
    if bound_claim?(queue, request, row, attempt) and
         queue_basis(queue) == queue_basis(expected_queue) and
         immutable_attempt(CommandReleaseAttemptRow.to_domain(row)) == immutable_attempt(attempt) and
         request_basis(request) == request_basis(expected_request) and
         completion_state?(queue, request, row),
       do: :ok,
       else: {:error, :command_release_claim_changed}
  end

  defp same_request?(left, right),
    do:
      Map.take(left, [:organization_id, :mission_id, :command_request_id]) ==
        Map.take(right, [:organization_id, :mission_id, :command_request_id])

  defp bound_claim?(queue, request, row, attempt),
    do:
      queue.active_release_attempt_id == attempt.command_release_attempt_id and
        same_request?(queue, request) and same_request?(queue, row) and
        row.command_queue_entry_id == queue.command_queue_entry_id

  defp completion_state?(queue, request, row) do
    case {queue.lifecycle_state, request.lifecycle_state, row.lifecycle_state} do
      {"released", "released", "released"} ->
        true

      {"release_pending", "queued", state}
      when state in ["release_pending", "release_uncertain"] ->
        true

      _ ->
        false
    end
  end

  defp immutable_attempt(attempt),
    do:
      Map.drop(Map.from_struct(attempt), [
        :lifecycle_state,
        :verification_state,
        :failure_reason,
        :released_at
      ])

  defp request_basis(request),
    do:
      request
      |> CommandRequestRow.to_domain()
      |> Map.from_struct()
      |> Map.drop([:lifecycle_state, :verification_state])

  defp queue_basis(queue),
    do:
      queue
      |> CommandQueueEntryRow.to_domain()
      |> Map.from_struct()
      |> Map.delete(:lifecycle_state)

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
