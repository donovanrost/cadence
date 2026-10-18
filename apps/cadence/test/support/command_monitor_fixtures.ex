defmodule Cadence.CommandMonitorFixtures do
  @moduledoc false
  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow
  }

  alias Cadence.CommandReviewFixtures
  alias Cadence.Repo

  def request!(c, id, attrs \\ %{}) do
    CommandReviewFixtures.request!(
      c,
      Map.merge(
        %{
          command_request_id: id,
          command_id: "CMD-#{id}",
          command_name: "Command #{id}",
          command_display_name: nil,
          lifecycle_state: :approved
        },
        attrs
      )
    )
  end

  def queue!(c, request, attrs \\ %{}) do
    queue =
      struct!(
        CommandQueueEntry,
        Map.merge(
          %{
            command_queue_entry_id: "queue-#{request.command_request_id}",
            organization_id: c.org,
            mission_id: c.mission,
            command_request_id: request.command_request_id,
            source_endpoint_ref: request.source_endpoint_ref,
            queue_lane_key: request.source_endpoint_ref,
            queue_sequence: 1,
            lifecycle_state: :released,
            enqueued_at: ~U[2026-09-10 08:01:00.000000Z]
          },
          attrs
        )
      )

    queue
    |> CommandQueueEntryRow.changeset()
    |> Repo.insert!()
    |> CommandQueueEntryRow.to_domain()
  end

  def release!(c, request, queue, id, attrs \\ %{}) do
    release =
      struct!(
        CommandReleaseAttempt,
        Map.merge(
          %{
            command_release_attempt_id: id,
            organization_id: c.org,
            mission_id: c.mission,
            command_queue_entry_id: queue.command_queue_entry_id,
            command_request_id: request.command_request_id,
            source_endpoint_ref: request.source_endpoint_ref,
            realized_contact_id: "contact-a",
            mission_model_revision_id: request.mission_model_revision_id,
            command_id: request.command_id,
            lifecycle_state: :released,
            verification_state: :not_required,
            attempted_at: ~U[2026-09-10 08:02:00.000000Z],
            released_at: ~U[2026-09-10 08:03:00.000000Z]
          },
          attrs
        )
      )

    release
    |> CommandReleaseAttemptRow.changeset()
    |> Repo.insert!()
    |> CommandReleaseAttemptRow.to_domain()
  end

  def verifier!(c, request, release, id, attrs \\ %{}) do
    verifier =
      struct!(
        CommandVerifierInstance,
        Map.merge(
          %{
            command_verifier_instance_id: id,
            organization_id: c.org,
            mission_id: c.mission,
            command_request_id: request.command_request_id,
            command_release_attempt_id: release.command_release_attempt_id,
            source_endpoint_ref: request.source_endpoint_ref,
            mission_model_revision_id: request.mission_model_revision_id,
            command_id: request.command_id,
            verifier_id: id,
            verifier_name: "Verifier #{id}",
            phase: :completion,
            lifecycle_state: :satisfied,
            matched_at: ~U[2026-09-10 08:04:00.000000Z],
            timeout_at: ~U[2026-09-10 08:05:00.000000Z]
          },
          attrs
        )
      )

    row = verifier |> CommandVerifierInstanceRow.changeset() |> Repo.insert!()
    # Fixed persisted timestamps make the identity tie breaker observable.
    row |> Ecto.Changeset.change(inserted_at: ~U[2026-09-10 08:03:00.000000Z]) |> Repo.update!()
    CommandVerifierInstanceRow.to_domain(row)
  end
end
