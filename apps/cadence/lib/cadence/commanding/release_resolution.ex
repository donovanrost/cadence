defmodule Cadence.Commanding.ReleaseResolution do
  @moduledoc false
  import Ecto.Query
  alias Cadence.Commanding

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    QueueLaneLock
  }

  alias Cadence.Platform.{ContentHash, ResolutionEvidence}
  alias Cadence.Platform.ScopedReadUpdates, as: ReadUpdates
  alias Cadence.Repo
  alias Ecto.Changeset

  def review(org, mission, id) do
    with {:ok, {queue, request, attempt}} <- records(org, mission, id) do
      {:ok, summary(queue, request, attempt, "review")}
    end
  end

  def resolve(org, mission, id, evidence) do
    with {:ok, {queue, request, _attempt}} <- records(org, mission, id) do
      Repo.transaction(fn -> resolve_claim_locked(org, mission, id, queue, request, evidence) end)
      |> ReadUpdates.publish_result(:commanding_changed, org, mission)
    end
  end

  defp resolve_claim_locked(org, mission, id, queue, request, evidence) do
    request =
      Repo.one!(
        from(r in CommandRequestRow,
          where:
            r.command_request_id == ^request.command_request_id and r.organization_id == ^org and
              r.mission_id == ^mission,
          lock: "FOR UPDATE"
        )
      )

    :ok = QueueLaneLock.acquire(org, mission, queue.queue_lane_key)

    queue =
      Repo.one!(
        from(q in CommandQueueEntryRow,
          where:
            q.command_queue_entry_id == ^queue.command_queue_entry_id and
              q.organization_id == ^org and q.mission_id == ^mission,
          lock: "FOR UPDATE"
        )
      )

    attempt =
      Repo.one!(
        from(a in CommandReleaseAttemptRow,
          where:
            a.command_release_attempt_id == ^id and a.organization_id == ^org and
              a.mission_id == ^mission,
          lock: "FOR UPDATE"
        )
      )

    with true <-
           queue.active_release_attempt_id == id and
             queue.command_request_id == request.command_request_id,
         true <- evidence["basis_sha256"] == basis(queue, request, attempt),
         true <- is_binary(evidence["session_ref"]) do
      resolve_locked(queue, request, attempt, evidence)
    else
      _ -> Repo.rollback(:command_resolution_basis_changed)
    end
  end

  defp records(org, mission, id) do
    attempt =
      Repo.get_by(CommandReleaseAttemptRow,
        organization_id: org,
        mission_id: mission,
        command_release_attempt_id: id
      )

    if attempt do
      queue =
        Repo.get_by(CommandQueueEntryRow,
          organization_id: org,
          mission_id: mission,
          command_queue_entry_id: attempt.command_queue_entry_id
        )

      request =
        Repo.get_by(CommandRequestRow,
          organization_id: org,
          mission_id: mission,
          command_request_id: attempt.command_request_id
        )

      if queue && request,
        do: {:ok, {queue, request, attempt}},
        else: {:error, :command_release_claim_changed}
    else
      {:error, :command_release_attempt_not_found}
    end
  end

  defp resolve_locked(queue, request, attempt, evidence) do
    case ResolutionEvidence.existing(attempt.resolution_evidence, evidence) do
      {:ok, entry} ->
        summary(queue, request, attempt, entry["disposition"])

      {:error, reason} ->
        Repo.rollback(reason)

      :new ->
        disposition = apply_outcome(queue, request, attempt, evidence)
        attempt = Repo.get!(CommandReleaseAttemptRow, attempt.command_release_attempt_id)

        with {:ok, log} <-
               ResolutionEvidence.append(attempt.resolution_evidence, evidence, disposition),
             {:ok, attempt} <- Repo.update(Changeset.change(attempt, resolution_evidence: log)) do
          summary(
            Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id),
            Repo.get!(CommandRequestRow, request.command_request_id),
            attempt,
            disposition
          )
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp apply_outcome(_queue, _request, %{lifecycle_state: "released"}, evidence) do
    if evidence["outcome"] in ~w(not_sent rejected),
      do: "contradictory",
      else: "retained_terminal"
  end

  defp apply_outcome(_queue, _request, %{lifecycle_state: state}, evidence)
       when state in ~w(release_failed canceled) do
    if evidence["outcome"] == "accepted", do: "contradictory", else: "retained_terminal"
  end

  defp apply_outcome(
         %{lifecycle_state: "release_pending"} = queue,
         %{lifecycle_state: "queued"} = request,
         %{lifecycle_state: state} = attempt,
         evidence
       )
       when state in ~w(release_pending release_uncertain) do
    case evidence["outcome"] do
      "unknown" ->
        Repo.update!(Changeset.change(attempt, lifecycle_state: "release_uncertain"))
        "held_unknown"

      "accepted" ->
        {:ok, at, 0} = DateTime.from_iso8601(evidence["observed_at"])

        case Commanding.complete_release_resolution(queue, request, attempt, at) do
          {:ok, _} -> "accepted"
          {:error, :verification_basis_unavailable} -> "held_verification_basis_unavailable"
          {:error, reason} -> Repo.rollback(reason)
        end

      outcome when outcome in ~w(not_sent rejected) ->
        Repo.update!(
          Changeset.change(attempt,
            lifecycle_state: "release_failed",
            failure_reason: "resolved: #{outcome}"
          )
        )

        Repo.update!(Changeset.change(queue, lifecycle_state: "canceled"))
        Repo.update!(Changeset.change(request, lifecycle_state: "canceled"))
        "closed_without_resend"
    end
  end

  defp apply_outcome(_queue, _request, _attempt, _evidence),
    do: Repo.rollback(:command_release_claim_changed)

  defp summary(queue, request, attempt, disposition) do
    %{
      basis_sha256: basis(queue, request, attempt),
      disposition: disposition,
      lane_held?: queue.lifecycle_state == "release_pending",
      release_attempt: CommandReleaseAttemptRow.to_domain(attempt),
      queue_entry: CommandQueueEntryRow.to_domain(queue),
      command_request: CommandRequestRow.to_domain(request)
    }
  end

  defp basis(queue, request, attempt) do
    ContentHash.term_sha256({
      queue
      |> CommandQueueEntryRow.to_domain()
      |> Map.from_struct()
      |> Map.drop([:lifecycle_state]),
      request
      |> CommandRequestRow.to_domain()
      |> Map.from_struct()
      |> Map.drop([:lifecycle_state, :verification_state]),
      attempt
      |> CommandReleaseAttemptRow.to_domain()
      |> Map.from_struct()
      |> Map.drop([
        :lifecycle_state,
        :verification_state,
        :failure_reason,
        :released_at,
        :resolution_evidence
      ])
    })
  end
end
