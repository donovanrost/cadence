defmodule Cadence.Reads.Commands do
  @moduledoc """
  Mission-scoped command status projection composed from canonical request,
  queue, release-attempt, and verifier records.
  """

  alias Cadence.Commanding
  alias Cadence.Commanding.{CommandQueueEntry, CommandReleaseAttempt, CommandRequest}

  def fetch_command_request(organization_id, mission_id, command_request_id) do
    Commanding.fetch_command_request(organization_id, mission_id, command_request_id)
  end

  def fetch_command_queue_entry(organization_id, mission_id, command_queue_entry_id) do
    Commanding.fetch_command_queue_entry(organization_id, mission_id, command_queue_entry_id)
  end

  def fetch_command_release_attempt(organization_id, mission_id, command_release_attempt_id) do
    Commanding.fetch_command_release_attempt(
      organization_id,
      mission_id,
      command_release_attempt_id
    )
  end

  def fetch_command_verifier_instance(
        organization_id,
        mission_id,
        command_verifier_instance_id
      ) do
    Commanding.fetch_command_verifier_instance(
      organization_id,
      mission_id,
      command_verifier_instance_id
    )
  end

  def list_command_queue_entries(organization_id, mission_id, opts) do
    Commanding.list_command_queue_entries(organization_id, mission_id, opts)
  end

  def list_command_release_attempts(organization_id, mission_id, opts) do
    Commanding.list_command_release_attempts(organization_id, mission_id, opts)
  end

  def list_command_verifier_instances(organization_id, mission_id, opts) do
    Commanding.list_command_verifier_instances(organization_id, mission_id, opts)
  end

  @spec snapshot(binary(), binary(), keyword()) :: map()
  def snapshot(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    observed_at = observed_at(opts)
    filters = Keyword.get(opts, :filters, %{})
    requests = records(:requests, organization_id, mission_id, opts)
    queue_entries = records(:queue_entries, organization_id, mission_id, opts)
    release_attempts = records(:release_attempts, organization_id, mission_id, opts)
    verifier_instances = records(:verifier_instances, organization_id, mission_id, opts)

    all_rows = compose_rows(requests, queue_entries, release_attempts, verifier_instances)

    %{
      mission_id: mission_id,
      observed_at: observed_at,
      freshness: :current,
      rows: all_rows |> filter_rows(filters) |> Enum.sort_by(&sort_key/1),
      targets:
        all_rows |> Enum.map(& &1.target) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort(),
      summary: summary_from_rows(mission_id, all_rows, observed_at)
    }
  end

  @spec summary(binary(), binary(), keyword()) :: map()
  def summary(organization_id, mission_id, opts \\ []) do
    snapshot(organization_id, mission_id, opts).summary
  end

  defp records(kind, organization_id, mission_id, opts) do
    case Keyword.get(opts, kind) do
      callback when is_function(callback, 3) -> callback.(organization_id, mission_id, [])
      _missing -> default_records(kind, organization_id, mission_id)
    end
  end

  defp default_records(:requests, organization_id, mission_id),
    do: Commanding.list_command_requests(organization_id, mission_id)

  defp default_records(:queue_entries, organization_id, mission_id),
    do: Commanding.list_command_queue_entries(organization_id, mission_id)

  defp default_records(:release_attempts, organization_id, mission_id),
    do: Commanding.list_command_release_attempts(organization_id, mission_id)

  defp default_records(:verifier_instances, organization_id, mission_id),
    do: Commanding.list_command_verifier_instances(organization_id, mission_id)

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      callback when is_function(callback, 0) -> callback.()
      _missing -> DateTime.utc_now()
    end
  end

  defp compose_rows(requests, queue_entries, release_attempts, verifier_instances) do
    queue_by_request = Enum.group_by(queue_entries, & &1.command_request_id)
    releases_by_request = Enum.group_by(release_attempts, & &1.command_request_id)
    verifiers_by_request = Enum.group_by(verifier_instances, & &1.command_request_id)

    Enum.map(requests, fn %CommandRequest{} = request ->
      queue_entry = queue_by_request |> Map.get(request.command_request_id, []) |> List.last()

      release_attempt =
        releases_by_request |> Map.get(request.command_request_id, []) |> List.last()

      verifiers = Map.get(verifiers_by_request, request.command_request_id, [])

      %{
        id: request.command_request_id,
        command_request_id: request.command_request_id,
        command_name: request.command_display_name || request.command_name || request.command_id,
        command_id: request.command_id,
        target: request.source_endpoint_ref,
        requested_by: requested_by_label(request.requested_by),
        requested_at: request.requested_at,
        significance: request.significance,
        request_state: request.lifecycle_state,
        verification_state: verification_state(request, release_attempt, verifiers),
        queue_entry: queue_entry,
        release_attempt: release_attempt,
        verifier_instances: verifiers,
        status: command_status(request, queue_entry, release_attempt, verifiers),
        occurred_at: latest_occurred_at(request, queue_entry, release_attempt, verifiers)
      }
    end)
  end

  defp command_status(request, queue_entry, release_attempt, verifiers) do
    failed_status(request, release_attempt, verifiers) ||
      release_transition_status(release_attempt) ||
      queue_transition_status(queue_entry) ||
      released_status(request, release_attempt, verifiers) ||
      queued_status(queue_entry) ||
      request.lifecycle_state ||
      :indeterminate
  end

  defp failed_status(request, release_attempt, verifiers) do
    if failed_verification?(request, release_attempt, verifiers), do: :failed
  end

  defp release_transition_status(%CommandReleaseAttempt{lifecycle_state: :release_failed}),
    do: :failed

  defp release_transition_status(%CommandReleaseAttempt{lifecycle_state: :release_pending}),
    do: :release_pending

  defp release_transition_status(_release_attempt), do: nil

  defp queue_transition_status(%CommandQueueEntry{lifecycle_state: :release_pending}),
    do: :release_pending

  defp queue_transition_status(_queue_entry), do: nil

  defp released_status(
         request,
         %CommandReleaseAttempt{lifecycle_state: :released} = release_attempt,
         verifiers
       ) do
    if verification_pending?(request, release_attempt, verifiers),
      do: :in_flight,
      else: :released
  end

  defp released_status(_request, _release_attempt, _verifiers), do: nil

  defp queued_status(%CommandQueueEntry{lifecycle_state: :pending}), do: :queued
  defp queued_status(_queue_entry), do: nil

  defp failed_verification?(request, release_attempt, verifiers) do
    request.verification_state in [:failed, :timed_out] or
      match?(
        %CommandReleaseAttempt{verification_state: state} when state in [:failed, :timed_out],
        release_attempt
      ) or
      Enum.any?(verifiers, &(&1.lifecycle_state in [:failed, :timed_out]))
  end

  defp verification_pending?(request, release_attempt, verifiers) do
    request.verification_state == :pending or
      match?(%CommandReleaseAttempt{verification_state: :pending}, release_attempt) or
      Enum.any?(verifiers, &(&1.lifecycle_state == :pending))
  end

  defp verification_state(request, release_attempt, verifiers) do
    verifier_states = Enum.map(verifiers, & &1.lifecycle_state)

    cond do
      :failed in verifier_states -> :failed
      :timed_out in verifier_states -> :timed_out
      :pending in verifier_states -> :pending
      verifiers != [] and Enum.all?(verifier_states, &(&1 == :satisfied)) -> :satisfied
      match?(%CommandReleaseAttempt{}, release_attempt) -> release_attempt.verification_state
      true -> request.verification_state
    end
  end

  defp filter_rows(rows, filters) do
    Enum.filter(rows, fn row ->
      exact_matches?(row.status, filter(filters, "status", :status)) and
        exact_matches?(row.target, filter(filters, "target", :target)) and
        query_matches?(row, filter(filters, "query", :query))
    end)
  end

  defp exact_matches?(_actual, value) when value in [nil, "", "all"], do: true

  defp exact_matches?(actual, expected) when is_atom(actual),
    do: Atom.to_string(actual) == expected

  defp exact_matches?(actual, expected), do: actual == expected

  defp query_matches?(_row, value) when value in [nil, ""], do: true

  defp query_matches?(row, query) do
    query = String.downcase(query)

    Enum.any?(
      [row.command_name, row.command_id, row.command_request_id, row.target, row.requested_by],
      fn value ->
        is_binary(value) and String.contains?(String.downcase(value), query)
      end
    )
  end

  defp summary_from_rows(mission_id, rows, observed_at) do
    counts = Enum.frequencies_by(rows, & &1.status)
    failed_count = Map.get(counts, :failed, 0)
    indeterminate_count = Map.get(counts, :indeterminate, 0)
    release_pending_count = Map.get(counts, :release_pending, 0)
    queued_count = Map.get(counts, :queued, 0)
    in_flight_count = Map.get(counts, :in_flight, 0)

    status =
      cond do
        failed_count + indeterminate_count > 0 -> :critical
        release_pending_count > 0 -> :warning
        queued_count + in_flight_count > 0 -> :info
        true -> :nominal
      end

    %{
      mission_id: mission_id,
      observed_at: observed_at,
      latest_transition_at: latest_transition_at(rows),
      freshness: :current,
      status: status,
      total_count: length(rows),
      queued_count: queued_count,
      release_pending_count: release_pending_count,
      in_flight_count: in_flight_count,
      released_count: Map.get(counts, :released, 0),
      failed_count: failed_count,
      indeterminate_count: indeterminate_count,
      active_count:
        queued_count + release_pending_count + in_flight_count + failed_count +
          indeterminate_count,
      rows: rows
    }
  end

  defp latest_occurred_at(request, queue_entry, release_attempt, verifiers) do
    [
      request.requested_at,
      queue_entry && queue_entry.enqueued_at,
      release_attempt && release_attempt.attempted_at,
      release_attempt && release_attempt.released_at
      | Enum.flat_map(verifiers, &[&1.matched_at, &1.timeout_at])
    ]
    |> Enum.reject(&is_nil/1)
    |> latest_datetime()
  end

  defp latest_transition_at(rows),
    do: rows |> Enum.map(& &1.occurred_at) |> Enum.reject(&is_nil/1) |> latest_datetime()

  defp latest_datetime([]), do: nil
  defp latest_datetime(datetimes), do: Enum.max_by(datetimes, &DateTime.to_unix(&1, :microsecond))

  defp requested_by_label(requested_by) when is_map(requested_by) do
    requested_by[:display_name] || requested_by["display_name"] || requested_by[:email] ||
      requested_by["email"] || requested_by[:user_id] || requested_by["user_id"] || "Unknown"
  end

  defp requested_by_label(_requested_by), do: "Unknown"

  defp sort_key(row) do
    {status_rank(row.status),
     -((row.occurred_at && DateTime.to_unix(row.occurred_at, :microsecond)) || 0),
     row.command_request_id}
  end

  defp status_rank(:failed), do: 0
  defp status_rank(:indeterminate), do: 1
  defp status_rank(:release_pending), do: 2
  defp status_rank(:in_flight), do: 3
  defp status_rank(:queued), do: 4
  defp status_rank(:approval_pending), do: 5
  defp status_rank(:approved), do: 6
  defp status_rank(:validated), do: 7
  defp status_rank(:released), do: 8
  defp status_rank(_status), do: 9

  defp filter(filters, string_key, atom_key) when is_map(filters),
    do: Map.get(filters, string_key) || Map.get(filters, atom_key)
end
