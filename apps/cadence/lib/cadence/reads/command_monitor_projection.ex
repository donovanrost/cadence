defmodule Cadence.Reads.CommandMonitorProjection do
  @moduledoc "Finite browser projection of canonical command status and evidence identities."
  @request_states ~w(draft validated approval_pending approved rejected queued released canceled)
  @statuses @request_states ++ ~w(failed indeterminate release_pending in_flight)
  @verification_states ~w(not_required pending satisfied failed timed_out)

  def statuses, do: @statuses

  def row(row, org, mission) do
    id = text(row.command_request_id)
    verifiers = row.verifier_instances

    %{
      id: id,
      command_id: optional(row.command_id),
      name: text(row.command_name, 512),
      status: state(row.status, @statuses),
      target: optional(row.target),
      requested_by: text(row.requested_by, 512),
      requested_at: time(row.requested_at),
      occurred_at: time(row.occurred_at),
      request_state: state(row.request_state, @request_states),
      verification_state: verification(row.verification_state),
      queue: queue(row.queue_entry, org, mission, id),
      release: release(row.release_attempt, org, mission, id),
      verifiers: verifiers |> Enum.take(20) |> Enum.map(&verifier(&1, org, mission, id)),
      verifier_total: Map.get(row, :verifier_total, length(verifiers))
    }
  end

  defp queue(nil, _, _, _), do: nil

  defp queue(record, org, mission, id) do
    scoped!(record, org, mission, id)

    %{
      id: text(record.command_queue_entry_id),
      state: state(record.lifecycle_state, ~w(pending release_pending released canceled)),
      lane: text(record.queue_lane_key),
      enqueued_at: time(record.enqueued_at)
    }
  end

  defp release(nil, _, _, _), do: nil

  defp release(record, org, mission, id) do
    scoped!(record, org, mission, id)

    %{
      id: text(record.command_release_attempt_id),
      queue_entry_id: text(record.command_queue_entry_id),
      state:
        state(
          record.lifecycle_state,
          ~w(release_pending released release_failed release_uncertain canceled)
        ),
      verification_state: verification(record.verification_state),
      contact_id: text(record.realized_contact_id),
      attempted_at: time(record.attempted_at),
      released_at: time(record.released_at)
    }
  end

  defp verifier(record, org, mission, id) do
    scoped!(record, org, mission, id)

    %{
      id: text(record.command_verifier_instance_id),
      release_attempt_id: text(record.command_release_attempt_id),
      name: text(record.verifier_name, 512),
      state: state(record.lifecycle_state, ~w(pending satisfied failed timed_out canceled)),
      matched_at: time(record.matched_at),
      timeout_at: time(record.timeout_at),
      matched_record_kind:
        optional_state(
          record.matched_record_kind,
          ~w(telemetry_sample transport_action_request transport_capability_record)
        ),
      matched_record_id: optional(record.matched_record_id)
    }
  end

  defp scoped!(
         %{organization_id: org, mission_id: mission, command_request_id: id},
         org,
         mission,
         id
       ),
       do: :ok

  defp scoped!(_, _, _, _), do: raise(ArgumentError, "invalid command evidence scope")
  def time(nil), do: nil
  def time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp verification(value), do: optional_state(value, @verification_states)
  defp optional_state(nil, _), do: nil
  defp optional_state(value, allowed), do: state(value, allowed)

  defp state(value, allowed) do
    value = to_string(value)
    if value in allowed, do: value, else: raise(ArgumentError, "invalid command state")
  end

  defp optional(nil), do: nil
  defp optional(value), do: text(value)

  defp text(value, max \\ 256) do
    if is_binary(value) and String.valid?(value) and byte_size(value) in 1..max,
      do: value,
      else: raise(ArgumentError, "invalid command text")
  end
end
