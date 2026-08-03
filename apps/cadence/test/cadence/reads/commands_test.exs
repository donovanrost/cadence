defmodule Cadence.Reads.CommandsTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance
  }

  alias Cadence.Reads.Commands

  test "composes command requests through queue, release, and verifier state" do
    observed_at = ~U[2026-08-01 12:10:00Z]

    snapshot =
      Commands.snapshot("org-1", "mission-1",
        observed_at: fn -> observed_at end,
        requests:
          records([
            request("queued", :queued),
            request("pending", :queued),
            request("flight", :released, verification_state: :pending),
            request("failed", :released, verification_state: :failed),
            request("done", :released, verification_state: :satisfied)
          ]),
        queue_entries:
          records([
            queue_entry("queued", :pending),
            queue_entry("pending", :release_pending)
          ]),
        release_attempts:
          records([
            release_attempt("pending", :release_pending),
            release_attempt("flight", :released, verification_state: :pending),
            release_attempt("failed", :released, verification_state: :failed),
            release_attempt("done", :released, verification_state: :satisfied)
          ]),
        verifier_instances:
          records([
            verifier("flight", :pending),
            verifier("failed", :failed),
            verifier("done", :satisfied)
          ])
      )

    assert snapshot.summary.queued_count == 1
    assert snapshot.summary.release_pending_count == 1
    assert snapshot.summary.in_flight_count == 1
    assert snapshot.summary.failed_count == 1
    assert snapshot.summary.released_count == 1
    assert snapshot.summary.active_count == 4
    assert snapshot.summary.status == :critical
    assert snapshot.observed_at == observed_at

    assert Enum.map(snapshot.rows, & &1.status) == [
             :failed,
             :release_pending,
             :in_flight,
             :queued,
             :released
           ]
  end

  test "filters by state, target, and command identity" do
    snapshot =
      Commands.snapshot("org-1", "mission-1",
        requests: records([request("queued", :queued), request("other", :approved)]),
        queue_entries: records([queue_entry("queued", :pending)]),
        release_attempts: records([]),
        verifier_instances: records([]),
        filters: %{"status" => "queued", "target" => "endpoint-queued", "query" => "CMD-QUEUED"}
      )

    assert [%{command_request_id: "queued", status: :queued}] = snapshot.rows
  end

  defp records(records), do: fn _organization_id, _mission_id, [] -> records end

  defp request(id, lifecycle_state, opts \\ []) do
    %CommandRequest{
      command_request_id: id,
      organization_id: "org-1",
      mission_id: "mission-1",
      source_endpoint_ref: "endpoint-#{id}",
      command_snapshot_id: "snapshot-#{id}",
      command_id: "CMD-#{String.upcase(id)}",
      command_name: "CMD-#{String.upcase(id)}",
      requested_by: %{display_name: "Flight Director"},
      requested_at: ~U[2026-08-01 12:00:00Z],
      lifecycle_state: lifecycle_state,
      verification_state: Keyword.get(opts, :verification_state)
    }
  end

  defp queue_entry(id, lifecycle_state) do
    %CommandQueueEntry{
      command_queue_entry_id: "queue-#{id}",
      organization_id: "org-1",
      mission_id: "mission-1",
      command_request_id: id,
      source_endpoint_ref: "endpoint-#{id}",
      queue_lane_key: "endpoint-#{id}",
      queue_sequence: 1,
      lifecycle_state: lifecycle_state,
      enqueued_at: ~U[2026-08-01 12:01:00Z]
    }
  end

  defp release_attempt(id, lifecycle_state, opts \\ []) do
    %CommandReleaseAttempt{
      command_release_attempt_id: "release-#{id}",
      organization_id: "org-1",
      mission_id: "mission-1",
      command_queue_entry_id: "queue-#{id}",
      command_request_id: id,
      source_endpoint_ref: "endpoint-#{id}",
      realized_contact_id: "contact-1",
      command_snapshot_id: "snapshot-#{id}",
      command_id: "CMD-#{String.upcase(id)}",
      lifecycle_state: lifecycle_state,
      verification_state: Keyword.get(opts, :verification_state),
      attempted_at: ~U[2026-08-01 12:02:00Z],
      released_at: if(lifecycle_state == :released, do: ~U[2026-08-01 12:03:00Z])
    }
  end

  defp verifier(id, lifecycle_state) do
    %CommandVerifierInstance{
      command_verifier_instance_id: "verifier-#{id}",
      organization_id: "org-1",
      mission_id: "mission-1",
      command_request_id: id,
      command_release_attempt_id: "release-#{id}",
      source_endpoint_ref: "endpoint-#{id}",
      command_snapshot_id: "snapshot-#{id}",
      command_id: "CMD-#{String.upcase(id)}",
      verifier_id: "completion",
      verifier_name: "Completion",
      lifecycle_state: lifecycle_state,
      timeout_at: ~U[2026-08-01 12:04:00Z]
    }
  end
end
