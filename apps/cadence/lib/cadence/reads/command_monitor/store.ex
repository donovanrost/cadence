defmodule Cadence.Reads.CommandMonitor.Store do
  @moduledoc """
  Scoped database projection for one monitor page and its independent focus.

  One statement observes a consistent database snapshot. PostgreSQL computes
  mission-wide aggregates but returns at most 25 page rows, one focused row,
  20 verifier previews per row and 201 target choices. Each selected row is
  limited to 64 KiB before transmission to the application. Malformed selected
  evidence is unavailable, never truncated into a valid identity.

  These are result materialization bounds, not constant database scan costs.
  Argument documents, wire payloads, verifier criteria and arbitrary metadata
  are not selected. This store performs no command lifecycle effects.
  """

  alias Cadence.Reads.CommandMonitor.{Query, Search}
  alias Cadence.Repo

  @row_fields ~w(command_request_id command_id command_name target requested_by request_state status verification_state verifier_total)a
  @queue_fields ~w(command_queue_entry_id queue_lane_key lifecycle_state)a
  @release_fields ~w(command_release_attempt_id command_queue_entry_id lifecycle_state verification_state realized_contact_id)a
  @verifier_fields ~w(command_verifier_instance_id command_release_attempt_id verifier_name lifecycle_state matched_record_kind matched_record_id)a
  @summary_fields ~w(total_count active_count queued_count release_pending_count in_flight_count released_count failed_count indeterminate_count)a

  def load(org, mission, query, opts \\ []) do
    params =
      [
        org,
        mission,
        query["status"],
        query["target"],
        String.downcase(query["query"]),
        String.to_integer(query["page"]),
        query["focus_command_id"]
      ] ++ Search.parameters()

    execute = Keyword.get(opts, :query, &Repo.query!/2)
    %{rows: [[data]], num_rows: 1} = execute.(Query.statement(), params)
    targets = data["targets"] |> Enum.take(200) |> Enum.map(&target!/1)

    %{
      total: data["total"],
      pages: data["pages"],
      page: data["page"],
      summary: fields(data["summary"], @summary_fields),
      targets: targets,
      targets_limited: length(data["targets"]) > 200,
      rows: Enum.map(data["rows"], &row(&1, org, mission)),
      focus: if(data["focus"], do: row(data["focus"], org, mission))
    }
  end

  defp row(%{"invalid" => true}, _, _), do: raise(ArgumentError, "oversize command evidence")

  defp row(data, org, mission) do
    id = Map.fetch!(data, "command_request_id")
    scope = %{organization_id: org, mission_id: mission, command_request_id: id}

    data
    |> fields(@row_fields)
    |> timestamps(data, [:requested_at, :occurred_at])
    |> Map.merge(%{
      queue_entry: record(data["queue_entry"], @queue_fields, [:enqueued_at], scope),
      release_attempt:
        record(data["release_attempt"], @release_fields, [:attempted_at, :released_at], scope),
      verifier_instances:
        Enum.map(
          data["verifier_instances"],
          &record(&1, @verifier_fields, [:matched_at, :timeout_at], scope)
        )
    })
  end

  defp record(nil, _, _, _), do: nil

  defp record(data, keys, times, scope),
    do: data |> fields(keys) |> timestamps(data, times) |> Map.merge(scope)

  defp fields(data, keys), do: Map.new(keys, &{&1, Map.fetch!(data, Atom.to_string(&1))})

  defp timestamps(record, data, keys),
    do: Enum.reduce(keys, record, &Map.put(&2, &1, time(Map.fetch!(data, Atom.to_string(&1)))))

  defp time(nil), do: nil

  defp time(value) do
    {:ok, naive} = NaiveDateTime.from_iso8601(value)
    # PostgreSQL JSON omits trailing fractional zeroes. Ecto's utc_datetime_usec
    # canonical records always retain six digits, including zero microseconds.
    {microseconds, _precision} = naive.microsecond
    naive |> Map.put(:microsecond, {microseconds, 6}) |> DateTime.from_naive!("Etc/UTC")
  end

  defp target!(value) when is_binary(value) and byte_size(value) in 1..256, do: value
  defp target!(_), do: raise(ArgumentError, "invalid command target")
end
