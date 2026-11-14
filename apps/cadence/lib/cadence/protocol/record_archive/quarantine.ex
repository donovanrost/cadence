defmodule Cadence.Protocol.RecordArchive.Quarantine do
  @moduledoc """
  Archive entries that can never be indexed (DECISIONS #88). The record-archive writer moves
  them out of its mission buffer into this store, so one poisoned entry doesn't stop the
  mission's telemetry storage; the rest of the batch flushes and its samples (theirs included)
  are stored. An operator retries them (once the cause is fixed) or discards them.

  An entry is quarantined only for an error a test proves deterministic: an identity conflict
  that names it, or a data error a bisect isolates to it. Everything else stays transient.
  """

  import Ecto.Query

  alias Cadence.Ids
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.PoisonIsolation
  alias Cadence.Protocol.RecordArchive.Quarantine.{EntryRow, ResolutionRow}
  alias Cadence.Repo

  @max_entries_per_mission 10_000
  @max_error_bytes 300

  @type quarantined :: %{entry: map(), error_code: binary(), error: binary() | nil}

  @doc "The most entries a mission may hold in quarantine; beyond it, failures stay transient."
  @spec max_entries_per_mission() :: pos_integer()
  def max_entries_per_mission, do: @max_entries_per_mission

  @doc """
  Quarantines `quarantined` (all of one mission). A record already quarantined has its
  `last_seen_at` and error refreshed. `{:error, :archive_quarantine_full}` when the mission's
  quarantine would exceed its cap: nothing is written and the caller keeps them transient.
  """
  @spec put(binary(), binary() | nil, [quarantined()], DateTime.t()) :: :ok | {:error, term()}
  def put(_mission_id, _organization_id, [], _now), do: :ok

  def put(mission_id, organization_id, quarantined, %DateTime{} = now) do
    if count(mission_id) + length(quarantined) > @max_entries_per_mission do
      {:error, :archive_quarantine_full}
    else
      rows = Enum.map(quarantined, &row(mission_id, organization_id, &1, now))

      {_count, _} =
        Repo.insert_all(EntryRow, rows,
          on_conflict: {:replace, [:last_seen_at, :error, :error_code, :updated_at]},
          conflict_target: [:mission_id, :record_kind, :record_id]
        )

      :ok
    end
  end

  defp row(mission_id, organization_id, %{entry: entry} = quarantined, now) do
    %{
      quarantine_entry_id: Ids.new("archive_quarantine"),
      mission_id: mission_id,
      organization_id: organization_id,
      realized_contact_id: get_in(entry, ["metadata", "realized_contact_id"]),
      spacecraft_id: Map.get(entry, "spacecraft_id"),
      record_kind: Map.fetch!(entry, "record_kind"),
      record_id: Map.fetch!(entry, "record_id"),
      error_code: quarantined.error_code,
      error: bounded(quarantined.error),
      entry: :erlang.term_to_binary(entry, [:compressed]),
      receipt_time: receipt_time(entry),
      first_seen_at: now,
      last_seen_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp receipt_time(entry) do
    with at when is_binary(at) <- Map.get(entry, "receipt_time"),
         {:ok, time, _offset} <- DateTime.from_iso8601(at) do
      %{time | microsecond: {elem(time.microsecond, 0), 6}}
    else
      _none -> nil
    end
  end

  defp bounded(nil), do: nil
  defp bounded(text) when byte_size(text) <= @max_error_bytes, do: text
  defp bounded(text), do: String.slice(text, 0, @max_error_bytes) <> "…"

  @spec count(binary()) :: non_neg_integer()
  def count(mission_id),
    do: Repo.aggregate(where(EntryRow, [r], r.mission_id == ^mission_id), :count)

  @doc "The mission's quarantined entries (rows), oldest first."
  @spec rows(binary()) :: [EntryRow.t()]
  def rows(mission_id) do
    EntryRow
    |> where([r], r.mission_id == ^mission_id)
    |> order_by([r], asc: r.first_seen_at, asc: r.record_kind, asc: r.record_id)
    |> Repo.all()
  end

  @doc "One item's rows: a contact (or none) and an error code."
  @spec item_rows(binary(), binary() | nil, binary()) :: [EntryRow.t()]
  def item_rows(mission_id, realized_contact_id, error_code) do
    EntryRow
    |> where([r], r.mission_id == ^mission_id and r.error_code == ^error_code)
    |> where_contact(realized_contact_id)
    |> order_by([r], asc: r.record_kind, asc: r.record_id)
    |> Repo.all()
  end

  defp where_contact(query, nil), do: where(query, [r], is_nil(r.realized_contact_id))
  defp where_contact(query, id), do: where(query, [r], r.realized_contact_id == ^id)

  @doc "A quarantined entry as the writer built it."
  @spec entry(EntryRow.t()) :: map()
  def entry(%EntryRow{entry: binary}), do: :erlang.binary_to_term(binary)

  @doc "Removes rows (a discard, or entries a retry indexed)."
  @spec delete([EntryRow.t()]) :: :ok
  def delete([]), do: :ok

  def delete(rows) do
    ids = Enum.map(rows, & &1.quarantine_entry_id)
    {_count, _} = Repo.delete_all(where(EntryRow, [r], r.quarantine_entry_id in ^ids))
    :ok
  end

  @doc "Records a retry on rows that still fail."
  @spec put_last_retry([EntryRow.t()], map()) :: :ok
  def put_last_retry([], _retry), do: :ok

  def put_last_retry(rows, retry) do
    ids = Enum.map(rows, & &1.quarantine_entry_id)

    {_count, _} =
      Repo.update_all(where(EntryRow, [r], r.quarantine_entry_id in ^ids),
        set: [last_retry: retry, updated_at: DateTime.utc_now()]
      )

    :ok
  end

  @doc """
  Re-indexes one item's entries now (an operator's retry, after the cause is fixed). Entries
  that index leave the quarantine; those that still fail stay, with `last_retry`. When none
  fail, the item resolves `retried`. A failure that isolates nothing (e.g. the database is
  down) changes nothing and is returned as `{:error, reason}`.
  """
  @spec retry_item(binary(), binary() | nil, binary(), map(), keyword()) ::
          {:ok, %{indexed: non_neg_integer(), still_failing: non_neg_integer()}}
          | {:error, term()}
  def retry_item(mission_id, realized_contact_id, error_code, actor, opts \\ []) do
    policy = Keyword.get_lazy(opts, :policy, &RecordArchive.configured_policy/0)

    with [_ | _] = rows <- item_rows(mission_id, realized_contact_id, error_code),
         FileSystem <- policy.backend do
      reindex(
        rows,
        actor,
        Keyword.put(policy.backend_opts, :organization_id, hd(rows).organization_id)
      )
    else
      [] -> {:error, :attention_item_not_found}
      _other_backend -> {:error, :archive_backend_unsupported}
    end
  end

  defp reindex(rows, actor, backend_opts) do
    entries = Enum.map(rows, &entry/1)

    case PoisonIsolation.persist(FileSystem.new_segment_id(), entries, backend_opts, fn _ ->
           :ok
         end) do
      {:ok, %{quarantined: still}} ->
        failing = MapSet.new(still, &{&1.entry["record_kind"], &1.entry["record_id"]})

        {stuck, indexed} =
          Enum.split_with(rows, &MapSet.member?(failing, {&1.record_kind, &1.record_id}))

        now = DateTime.utc_now()
        :ok = delete(indexed)

        :ok =
          put_last_retry(stuck, %{
            "by" => actor,
            "at" => DateTime.to_iso8601(now),
            "indexed" => length(indexed)
          })

        if stuck == [], do: :ok = resolve_rows(rows, "retried", actor, nil, now)
        {:ok, %{indexed: length(indexed), still_failing: length(stuck)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Discards one item's entries (an operator's decision, with a reason)."
  @spec discard_item(binary(), binary() | nil, binary(), map(), binary()) ::
          {:ok, %{discarded: pos_integer()}} | {:error, term()}
  def discard_item(mission_id, realized_contact_id, error_code, actor, note) do
    case item_rows(mission_id, realized_contact_id, error_code) do
      [] ->
        {:error, :attention_item_not_found}

      rows ->
        :ok = delete(rows)
        :ok = resolve_rows(rows, "discarded", actor, note, DateTime.utc_now())
        {:ok, %{discarded: length(rows)}}
    end
  end

  @doc "The item id rows belong to: `<realized contact or none>:<error code>`."
  @spec item_id(binary() | nil, binary()) :: binary()
  def item_id(realized_contact_id, error_code),
    do: "#{realized_contact_id || "none"}:#{error_code}"

  @doc "The {realized_contact_id | nil, error_code} an item id names."
  @spec parse_item_id(binary()) :: {:ok, {binary() | nil, binary()}} | :error
  def parse_item_id(id) when is_binary(id) do
    case String.split(id, ":") |> Enum.split(-1) do
      {[_ | _] = contact, [code]} when code != "" ->
        contact = Enum.join(contact, ":")
        {:ok, {if(contact == "none", do: nil, else: contact), code}}

      _invalid ->
        :error
    end
  end

  @doc "Counts by kind: `%{entries, frames, packets}`."
  @spec counts([EntryRow.t()]) :: map()
  def counts(rows) do
    frames = Enum.count(rows, &(&1.record_kind == "transfer_frame_record"))
    packets = Enum.count(rows, &(&1.record_kind == "packet_record"))
    %{entries: length(rows), frames: frames, packets: packets}
  end

  defp resolve_rows([first | _] = rows, action, actor, note, now) do
    record_resolution(%{
      mission_id: first.mission_id,
      item_id: item_id(first.realized_contact_id, first.error_code),
      realized_contact_id: first.realized_contact_id,
      spacecraft_id: Enum.find_value(rows, & &1.spacecraft_id),
      error_code: first.error_code,
      action: action,
      actor: actor,
      note: note,
      counts: counts(rows),
      resolved_at: now
    })
  end

  @doc "Records an item's resolution (retried or discarded) for the attention read."
  @spec record_resolution(map()) :: :ok
  def record_resolution(attrs) do
    {:ok, _row} =
      %ResolutionRow{}
      |> Ecto.Changeset.change(
        Map.put(attrs, :resolution_id, Ids.new("archive_quarantine_resolution"))
      )
      |> Repo.insert()

    :ok
  end

  @doc "Resolutions of the mission's items since `since`, newest first."
  @spec resolutions_since(binary(), DateTime.t()) :: [ResolutionRow.t()]
  def resolutions_since(mission_id, %DateTime{} = since) do
    ResolutionRow
    |> where([r], r.mission_id == ^mission_id and r.resolved_at >= ^since)
    |> order_by([r], desc: r.resolved_at)
    |> Repo.all()
  end
end
