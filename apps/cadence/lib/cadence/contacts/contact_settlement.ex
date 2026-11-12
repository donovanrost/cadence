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

  alias Cadence.Contacts.{ContactStore, RealizedContact}
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

  defp filter_mission(query, nil), do: query
  defp filter_mission(query, mission_id), do: where(query, [row], row.mission_id == ^mission_id)

  @doc """
  Records the settler's outcome on the contact as it reads now. `backlog` is the runtime's
  `%{journals, persistence_errors}`; `stop` is how stopping its runtime went.
  """
  @spec record(
          RealizedContact.t(),
          :settled | :absent | {:unsettled, binary(), term()},
          map(),
          term()
        ) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def record(%RealizedContact{} = contact, outcome, backlog, stop) do
    with {:ok, current} <-
           ContactStore.fetch_realized(contact.mission_id, contact.realized_contact_id) do
      settlement =
        current.metadata
        |> Map.get("settlement", %{})
        |> Map.merge(outcome_fields(outcome, backlog, DateTime.utc_now()))
        |> put_stop(stop)

      ContactStore.update_realized_lifecycle(current, current.lifecycle_state, %{
        "settlement" => settlement
      })
    end
  end

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
  defp failure(_reason, _error, storage_error) when is_binary(storage_error),
    do: {@storage_failure, truncate(storage_error)}

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

  defp put_stop(settlement, :ok), do: Map.delete(settlement, "stop_error")

  defp put_stop(settlement, {:error, reason}),
    do: Map.put(settlement, "stop_error", inspect(reason))

  defp truncate(text) when byte_size(text) <= @max_message_bytes, do: text
  defp truncate(text), do: binary_part(text, 0, @max_message_bytes) <> "…"
end
