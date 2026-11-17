defmodule Cadence.Contacts.ContactSettlement do
  @moduledoc """
  A realized contact's settlement after it ends (DECISIONS #71), kept durably in its
  `metadata["settlement"]`:

  - `"settling"`: ended; its runtime takes no new data and drains its journal to the TSDB.
  - `"settled"`: drained and stopped.
  - `"unsettled"`: stopped with telemetry still in its on-disk journal, named in
    `unpersisted_journal` (`[%{path_id, provider_binding_id, from_offset, to_offset, entries,
    bytes}]`). `reason` is `"settle_deadline"` or `"settle_failed"`; `failure_kind` is
    `"telemetry_storage_unavailable"` when storing failed, and nil for a slow drain.
  """

  import Ecto.Query

  alias Cadence.Contacts.{ContactStore, RealizedContact, ScidMismatch}
  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Control.Contacts, as: Runtime
  alias Cadence.Repo

  @storage_failure "telemetry_storage_unavailable"
  @max_message_bytes 500
  @default_deadline_ms 6 * 60 * 60 * 1000

  @doc """
  How long a settler waits for the drain before recording `unsettled` (default 6 h; config
  `:cadence, :contact_settlement, deadline_ms:`). It bounds resources; nothing waits on it.
  """
  @spec deadline_ms() :: pos_integer()
  def deadline_ms do
    :cadence
    |> Application.get_env(:contact_settlement, [])
    |> Keyword.get(:deadline_ms, @default_deadline_ms)
  end

  @default_replay_deadline_ms 30 * 60 * 1000
  @replay_backoff_ms 5 * 60 * 1000
  @replay_backoff_max_ms 2 * 60 * 60 * 1000
  @replay_attempts 6

  @doc "A replay's drain deadline (director 2026-11-11: 30 min; config `:replay_deadline_ms`)."
  @spec replay_deadline_ms() :: pos_integer()
  def replay_deadline_ms do
    :cadence
    |> Application.get_env(:contact_settlement, [])
    |> Keyword.get(:replay_deadline_ms, @default_replay_deadline_ms)
  end

  @doc "Marks a replay as running on the contact (its attention item shows the attempt)."
  @spec replay_started(RealizedContact.t()) :: {:ok, RealizedContact.t()} | {:error, term()}
  def replay_started(%RealizedContact{} = contact) do
    with {:ok, current} <-
           ContactStore.fetch_realized(contact.mission_id, contact.realized_contact_id) do
      # A contact ended before #71 has no settlement: "inspecting" keeps the settle sweep (which
      # takes ended contacts with none and a running runtime) off it while its replay runs.
      settlement =
        current.metadata
        |> Map.get("settlement", %{})
        |> Map.put_new("state", "inspecting")
        |> Map.merge(%{
          "replay" => "running",
          "last_attempt_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      ContactStore.update_realized_lifecycle(current, current.lifecycle_state, %{
        "settlement" => settlement
      })
    end
  end

  @doc """
  Records a replay's outcome. Drained: `settled` and `inspected_at`, plus `replayed_at` when it
  had been `unsettled` (its attention item resolves as replayed). Not drained: `unsettled` again,
  the backlog re-read, `attempts` + 1 and `next_attempt_at` backing off 5 min doubling to 2 h;
  after 6 failed replays, `retry` turns `manual` and only an operator's retry starts another
  (director 2026-11-12).
  """
  @spec record_replay(RealizedContact.t(), term(), map(), term()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def record_replay(%RealizedContact{} = contact, outcome, backlog, stop) do
    with {:ok, current} <-
           ContactStore.fetch_realized(contact.mission_id, contact.realized_contact_id) do
      previous = Map.get(current.metadata, "settlement", %{})
      now = DateTime.utc_now()

      settlement =
        previous
        |> Map.merge(replay_fields(outcome, previous, backlog, now))
        |> put_stop(stop)

      ContactStore.update_realized_lifecycle(current, current.lifecycle_state, %{
        "settlement" => settlement
      })
    end
  end

  # A drained replay has inspected the journal, whichever way it was picked: an unsettled
  # contact's replay must not leave it looking uninspected (39LEY, 11-14: a never-inspected contact
  # whose first replay failed was replayed a second time after it drained).
  defp replay_fields(:settled, previous, _backlog, now) do
    at = DateTime.to_iso8601(now)

    %{
      "state" => "settled",
      "settled_at" => at,
      "inspected_at" => at,
      "replay" => "done",
      "retry" => nil,
      "next_attempt_at" => nil
    }
    |> maybe_put("replayed_at", previous["state"] == "unsettled", at)
  end

  defp replay_fields(outcome, previous, backlog, now) do
    {:unsettled, _reason, _error} = unsettled = normalize_replay_outcome(outcome)
    fields = outcome_fields(unsettled, backlog, now)
    attempts = (previous["attempts"] || 0) + 1
    manual? = attempts >= @replay_attempts

    fields
    |> Map.merge(%{
      "attempts" => attempts,
      "replay" => if(manual?, do: "stopped", else: "waiting"),
      "retry" => if(manual?, do: "manual", else: "automatic"),
      "next_attempt_at" =>
        if(manual?,
          do: nil,
          else: now |> DateTime.add(backoff_ms(attempts), :millisecond) |> DateTime.to_iso8601()
        ),
      "first_failure_kind" =>
        previous["first_failure_kind"] || previous["failure_kind"] || fields["failure_kind"]
    })
  end

  defp maybe_put(map, key, true, value), do: Map.put(map, key, value)
  defp maybe_put(map, _key, false, _value), do: map

  defp normalize_replay_outcome({:unsettled, _reason, _error} = outcome), do: outcome
  defp normalize_replay_outcome(other), do: {:unsettled, "settle_failed", other}

  defp backoff_ms(attempts),
    do: min(@replay_backoff_ms * Integer.pow(2, attempts - 1), @replay_backoff_max_ms)

  @doc """
  An operator's retry of a contact whose replay stopped (`retry` `manual`): attempts reset, due
  now. `{:error, :retry_not_manual}` otherwise.
  """
  @spec retry(RealizedContact.t()) :: {:ok, RealizedContact.t()} | {:error, term()}
  def retry(
        %RealizedContact{metadata: %{"settlement" => %{"retry" => "manual"} = settlement}} =
          contact
      ) do
    ContactStore.update_realized_lifecycle(contact, contact.lifecycle_state, %{
      "settlement" =>
        Map.merge(settlement, %{
          "attempts" => 0,
          "retry" => "automatic",
          "replay" => "waiting",
          "next_attempt_at" => DateTime.to_iso8601(DateTime.utc_now())
        })
    })
  end

  def retry(%RealizedContact{}), do: {:error, :retry_not_manual}

  @doc "The settlement patch `ContactLifecycle` records with the end."
  @spec settling(DateTime.t(), pos_integer()) :: map()
  def settling(%DateTime{} = now, deadline_ms \\ deadline_ms()) do
    %{
      "settlement" => %{
        "state" => "settling",
        "started_at" => DateTime.to_iso8601(now),
        # Director (2026-11-12): with the journal off, nothing survives a stop; say so.
        "journal" => if(Runtime.ingress_journal_enabled?(), do: "enabled", else: "disabled"),
        "deadline_at" => now |> DateTime.add(deadline_ms, :millisecond) |> DateTime.to_iso8601()
      }
    }
  end

  @doc "The contact's settlement state, or nil (ended before #71, or not ended)."
  @spec state(RealizedContact.t()) :: binary() | nil
  def state(%RealizedContact{metadata: %{"settlement" => %{"state" => state}}}), do: state
  def state(%RealizedContact{}), do: nil

  @doc """
  Ended contacts a settler should have and may not (reconcile's sweep): `settling` ones (a node
  restart loses their settler), and ones ended before #71 whose runtime is still among
  `running_ids`. `mission_id` nil sweeps every mission's `settling` contacts.
  """
  @spec sweep_candidates(binary() | nil, [binary()]) :: [RealizedContact.t()]
  def sweep_candidates(mission_id, running_ids) do
    from(row in RealizedContactRow,
      where:
        row.lifecycle_state in ["stopped", "completed"] and
          (fragment("? -> 'value' -> 'settlement' ->> 'state' = 'settling'", row.metadata) or
             (fragment("? -> 'value' -> 'settlement' IS NULL", row.metadata) and
                row.realized_contact_id in ^running_ids))
    )
    |> filter_mission(mission_id)
    |> order_by([row], asc: row.realized_contact_id)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  @doc """
  The next contact to replay, if any (reconcile runs one per mission at a time): an `unsettled`
  contact whose replay is due, oldest first; else an ended contact whose journal is on disk
  (`journaled_ids`) but wasn't inspected: settled with `runtime: "absent"`, or ended before #71.
  Never one whose runtime is in `running_ids`.
  """
  @spec next_replay(binary(), MapSet.t(binary()), [binary()], DateTime.t()) ::
          RealizedContact.t() | nil
  def next_replay(mission_id, journaled_ids, running_ids, %DateTime{} = now) do
    running = MapSet.new(running_ids)

    (due_replays(mission_id, now) ++ uninspected(mission_id, MapSet.to_list(journaled_ids)))
    |> Enum.find(&(not MapSet.member?(running, &1.realized_contact_id)))
  end

  defp due_replays(mission_id, now) do
    from(row in RealizedContactRow,
      where:
        row.mission_id == ^mission_id and
          fragment("? -> 'value' -> 'settlement' ->> 'state' = 'unsettled'", row.metadata),
      order_by: [asc: row.realized_contact_id]
    )
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
    |> Enum.filter(&replay_due?(&1, now))
  end

  defp uninspected(_mission_id, []), do: []

  defp uninspected(mission_id, ids) do
    from(row in RealizedContactRow,
      where:
        row.mission_id == ^mission_id and row.realized_contact_id in ^ids and
          row.lifecycle_state in ["stopped", "completed"] and
          (fragment("? -> 'value' -> 'settlement' IS NULL", row.metadata) or
             fragment("? -> 'value' -> 'settlement' ->> 'state' = 'inspecting'", row.metadata) or
             (fragment("? -> 'value' -> 'settlement' ->> 'runtime' = 'absent'", row.metadata) and
                fragment("? -> 'value' -> 'settlement' -> 'inspected_at' IS NULL", row.metadata))),
      order_by: [asc: row.realized_contact_id]
    )
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  # Due: journal on, not lost, not handed to an operator, and its backoff has passed.
  defp replay_due?(%RealizedContact{metadata: %{"settlement" => settlement}}, now) do
    settlement["journal"] != "disabled" and
      not get_in(settlement, ["backlog", "lost"]) == true and
      settlement["retry"] != "manual" and
      due_at?(settlement["next_attempt_at"], now)
  end

  defp due_at?(nil, _now), do: true

  defp due_at?(at, now) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> DateTime.compare(at, now) != :gt
      _invalid -> true
    end
  end

  defp filter_mission(query, nil), do: query
  defp filter_mission(query, mission_id), do: where(query, [row], row.mission_id == ^mission_id)

  @doc """
  Records the settler's outcome on the contact as it reads now. `backlog` is the runtime's
  `%{journals, persistence_errors}`; `stop` is how stopping its runtime went. `listener_refusal`
  (ux U50, `ListenerRefusalAttention.settlement_document/2`) is kept in
  `metadata["listener_refusal"]` when the contact had a shared listener.
  """
  @spec record(
          RealizedContact.t(),
          :settled | :absent | {:unsettled, binary(), term()},
          map(),
          term(),
          map() | nil,
          [map()],
          [map()]
        ) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def record(
        %RealizedContact{} = contact,
        outcome,
        backlog,
        stop,
        listener_refusal \\ nil,
        incomplete \\ [],
        scid_checks \\ []
      ) do
    with {:ok, current} <-
           ContactStore.fetch_realized(contact.mission_id, contact.realized_contact_id) do
      now = DateTime.utc_now()
      scid_mismatch = ScidMismatch.settlement_entries(scid_checks, ground_station_ref(current))

      settlement =
        current.metadata
        |> Map.get("settlement", %{})
        |> Map.merge(outcome_fields(outcome, backlog, now))
        |> put_stop(stop)
        |> put_incomplete(incomplete)
        |> put_scid_mismatch(scid_mismatch)

      metadata =
        if listener_refusal,
          do: %{"settlement" => settlement, "listener_refusal" => listener_refusal},
          else: %{"settlement" => settlement}

      with {:ok, updated} <-
             ContactStore.update_realized_lifecycle(current, current.lifecycle_state, metadata) do
        # Only a fresh read raises the event; a later settle reads nothing (#102).
        _ = ScidMismatch.record_event(updated, scid_mismatch, now)
        {:ok, updated}
      end
    end
  end

  # The frame-SCID cross-check (DECISIONS #102): an empty read keeps what an earlier settle stored,
  # as incomplete_at_end does.
  defp put_scid_mismatch(settlement, []), do: settlement

  defp put_scid_mismatch(settlement, entries),
    do: Map.put(settlement, "scid_mismatch", entries)

  defp ground_station_ref(%RealizedContact{metadata: metadata}),
    do: (metadata || %{})["ground_station_ref"]

  # No runtime to drain: whatever its journal holds on disk wasn't inspected (replay does).
  defp outcome_fields(:absent, _backlog, now),
    do: %{"state" => "settled", "settled_at" => DateTime.to_iso8601(now), "runtime" => "absent"}

  defp outcome_fields(:settled, _backlog, now),
    do: %{"state" => "settled", "settled_at" => DateTime.to_iso8601(now)}

  defp outcome_fields({:unsettled, reason, error}, backlog, now) do
    journals = Enum.map(Map.get(backlog, :journals, []), &journal_document/1)
    storage_error = List.first(Map.get(backlog, :persistence_errors, []))
    {kind, message} = failure(reason, error, storage_error)

    %{
      "state" => "unsettled",
      "unsettled_at" => DateTime.to_iso8601(now),
      "reason" => reason,
      "failure_kind" => kind,
      "failure_message" => message,
      "unpersisted_journal" => journals,
      "backlog" => %{
        "entries" => journals |> Enum.map(& &1["entries"]) |> Enum.sum(),
        "bytes" => journals |> Enum.map(& &1["bytes"]) |> Enum.sum(),
        "journals" => length(journals),
        "queued" => Map.get(backlog, :queued, 0),
        # Without a journal, the queued batches lived only in memory and went with the runtime.
        "lost" => not Runtime.ingress_journal_enabled?()
      }
    }
  end

  # A storing failure names the cause, whatever ended the wait; a deadline with no error is a
  # slow drain (failure_kind nil).
  # #99 follow-up (ux U84): storage stuck on a replay-id conflict is its own kind, so the item
  # folds under the Stuck processing item and offers no retry.
  defp failure(_reason, _error, storage_error) when is_binary(storage_error) do
    kind =
      if String.contains?(storage_error, ":replay_id_conflict"),
        do: "replay_id_conflict",
        else: @storage_failure

    {kind, truncate(storage_error)}
  end

  defp failure("settle_failed", error, nil), do: {"settle_failed", truncate(inspect(error))}
  defp failure(_reason, _error, nil), do: {nil, nil}

  defp journal_document(journal) do
    %{
      "path_id" => journal.path_id,
      "provider_binding_id" => journal.provider_binding_id,
      "from_offset" => journal.from_offset,
      "to_offset" => journal.to_offset,
      "entries" => journal.entries,
      "bytes" => journal.bytes
    }
  end

  # What streams gave up at their end (a frame or packet that never completed), per path and
  # binding. An empty read keeps what an earlier settle stored: a later settle of the same contact
  # runs with the runtime gone and reads nothing, and must not erase the one record (api-ops).
  defp put_incomplete(settlement, []), do: settlement

  defp put_incomplete(settlement, incomplete) do
    Map.put(
      settlement,
      "incomplete_at_end",
      Enum.map(incomplete, fn item ->
        Map.new(
          [:path_id, :provider_binding_id, :frame_bytes, :packet_octets, :journal_bytes],
          &{Atom.to_string(&1), Map.get(item, &1)}
        )
      end)
    )
  end

  defp put_stop(settlement, :ok), do: Map.delete(settlement, "stop_error")

  defp put_stop(settlement, {:error, reason}),
    do: Map.put(settlement, "stop_error", inspect(reason))

  defp truncate(text) when byte_size(text) <= @max_message_bytes, do: text
  defp truncate(text), do: binary_part(text, 0, @max_message_bytes) <> "…"
end
