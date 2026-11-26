defmodule Cadence.Protocol.RecordArchive.FileSystem.Index do
  @moduledoc """
  The archive's Postgres index (#688 PR 2): one summary row per segment, and one narrow identity
  row per record.

  `protocol_archive_segments` holds what replay needs to pick segments (mission, receipt range,
  the spacecraft, contact, source and evidence ids a segment holds), so a read loads the matching
  segments and filters their entries in memory. `protocol_archive_record_identities` holds only
  `(record_kind, record_id, content_sha256, segment_id)`, and its primary key is what DECISIONS #88's
  identity-conflict check and the replay dedupe stand on.

  A record id that is already indexed was archived before when it is the same record and its
  segment object is on disk. `content_sha256` decides "the same record", and is `digest/1`: a
  versioned, explicit encoding of the record's identity columns and the hash of its payload bytes.
  It is persisted and recomputed on every replay, so it must never depend on Erlang's term format
  (DECISIONS #108): an OTP upgrade must not turn every replay into a conflict. The transport fields
  (evidence id, receipt time, batch metadata) are left out on purpose: a replay may group the same
  journal records into different evidence than the run that archived them, and 11-14's pass,
  interrupted mid-batch, replayed into a permanent conflict that stalled the mission's ingest.
  Another frame sequence, another APID, or other packet bytes at the same id has another digest,
  which is a real conflict.

  A transfer frame's entry carries no payload bytes (the evidence's bytes live in the ingress
  archive, and its hash changes when a replay regroups the journal), so its digest covers its
  identity columns and its lengths.
  """

  import Ecto.Query

  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.{IdentityRow, SegmentRow}
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  require Logger

  @frame_kind "transfer_frame_record"
  @packet_kind "packet_record"

  @frame_identity ~w(mission_id spacecraft_id protocol_family direction scid vcid map_id frame_seq)
  @packet_identity ~w(mission_id spacecraft_id protocol_family direction apid packet_kind)

  @chunk 1_000

  @doc """
  Indexes one segment object: its summary row and an identity row per new record, in one
  transaction. `:ok`, `{:error, {:protocol_archive_record_identity_conflict, ids}}`, or
  `{:error, {:protocol_archive_invalid_entries, ids}}` for entries whose bytes cannot be read. A
  segment whose every record was archived before is not indexed and its object is removed.
  """
  @spec persist_segment(binary(), [map()], keyword()) :: :ok | {:error, term()}
  def persist_segment(_segment_ref, entries, opts) do
    object_key = Keyword.fetch!(opts, :object_key)
    repo = repo(opts)
    invalid = Enum.reject(entries, &valid_payload?/1)

    if invalid == [] do
      index_entries(repo, entries, Enum.map(entries, &record(&1, opts)), object_key, opts)
    else
      # Entries that can never be indexed are named so #88 quarantines them, not raised.
      ids = Enum.map(invalid, &FileSystem.entry_index_record_id(&1, opts))
      {:error, {:protocol_archive_invalid_entries, ids}}
    end
  end

  defp index_entries(repo, entries, rows, object_key, opts) do
    result =
      repo.transaction(fn ->
        if segment_indexed?(repo, object_key),
          do: :already_indexed,
          else: index_segment(repo, entries, rows, object_key, opts)
      end)

    case result do
      {:ok, _segment_or_noop} -> :ok
      {:error, :already_archived} -> drop_unreferenced_object(object_key, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  # A packet whose stored bytes are not valid base64 cannot be digested.
  defp valid_payload?(%{"record_kind" => @packet_kind} = entry),
    do: match?({:ok, _bytes}, entry |> Map.get("packet_data_base64", "") |> Base.decode64())

  defp valid_payload?(_entry), do: true

  # A retry of a segment that is already indexed has nothing to do (and must not remove its object).
  defp segment_indexed?(repo, object_key),
    do: repo.exists?(from(s in SegmentRow, where: s.object_key == ^object_key))

  defp index_segment(repo, entries, rows, object_key, opts) do
    segment = repo.insert!(segment_row(entries, object_key, opts))

    case insert_identities(repo, segment.id, rows, opts) do
      {:ok, []} -> repo.rollback(:already_archived)
      {:ok, inserted} -> record_frames(repo, segment, inserted)
      {:error, reason} -> repo.rollback(reason)
    end
  end

  @doc "The segments that can hold records for `scope`, oldest first (so a duplicate resolves to its original)."
  @spec candidate_segments(binary(), Scope.t(), binary(), keyword()) :: [SegmentRow.t()]
  def candidate_segments(mission_id, %Scope{} = scope, record_kind, opts) do
    backend = FileSystem.archive_backend(opts)

    SegmentRow
    |> where([s], s.archive_backend == ^backend and s.mission_id == ^mission_id)
    |> where_kind(record_kind)
    |> where_range(scope)
    |> where_holds(:evidence_ids, scope.evidence_ids && Enum.uniq(scope.evidence_ids))
    |> where_holds(:spacecraft_ids, scope.spacecraft_id && [scope.spacecraft_id])
    |> where_holds(:source_refs, scope.source_ref && [scope.source_ref])
    |> where_holds(
      :realized_contact_ids,
      scope.realized_contact_id && [scope.realized_contact_id]
    )
    |> order_by([s], asc: s.id)
    |> repo(opts).all()
  end

  @doc "Transfer frames archived per realized contact, from the segments' own counts."
  @spec received_frames(binary(), [binary()], keyword()) :: %{binary() => non_neg_integer()}
  def received_frames(_mission_id, [], _opts), do: %{}

  def received_frames(mission_id, realized_contact_ids, opts) do
    SegmentRow
    |> where([s], s.mission_id == ^mission_id and s.frame_count > 0)
    |> where(
      [s],
      fragment("? && ?", s.realized_contact_ids, type(^realized_contact_ids, {:array, :string}))
    )
    |> select([s], s.frames_by_contact)
    |> repo(opts).all()
    |> Enum.reduce(%{}, fn by_contact, acc ->
      by_contact
      |> Map.take(realized_contact_ids)
      |> Enum.reduce(acc, fn {contact, count}, acc ->
        Map.update(acc, contact, count, &(&1 + count))
      end)
    end)
  end

  defp where_kind(query, @frame_kind), do: where(query, [s], s.frame_count > 0)
  defp where_kind(query, @packet_kind), do: where(query, [s], s.packet_count > 0)
  defp where_kind(query, _kind), do: query

  defp where_range(query, scope) do
    query |> where_from(scope.from_receipt_time) |> where_to(scope.to_receipt_time)
  end

  defp where_from(query, nil), do: query
  defp where_from(query, from), do: where(query, [s], s.last_receipt_time >= ^from)

  defp where_to(query, nil), do: query
  defp where_to(query, to), do: where(query, [s], s.first_receipt_time <= ^to)

  defp where_holds(query, _field, nil), do: query
  defp where_holds(query, _field, []), do: query

  defp where_holds(query, field, values),
    do: where(query, [s], fragment("? && ?", field(s, ^field), type(^values, {:array, :string})))

  defp record(entry, opts) do
    %{
      record_kind: Map.fetch!(entry, "record_kind"),
      record_id: FileSystem.entry_index_record_id(entry, opts),
      content_sha256: digest(entry),
      entry: entry
    }
  end

  @digest_version "archive_identity_v1"

  # sha256(version <> canonical JSON of [[name, value], ...] in a fixed order <> sha256 of the payload)
  @doc false
  @spec digest(map()) :: binary()
  def digest(%{"record_kind" => @frame_kind} = entry),
    do: digest(entry, @frame_identity ++ ~w(raw_frame_length_bytes payload_length_bytes), <<>>)

  def digest(%{"record_kind" => @packet_kind} = entry),
    do: digest(entry, @packet_identity, packet_bytes(entry))

  def digest(entry), do: digest(entry, ~w(mission_id record_kind record_id), <<>>)

  defp digest(entry, fields, payload) do
    named = Jason.encode!(Enum.map(fields, &[&1, Map.get(entry, &1)]))
    :crypto.hash(:sha256, [@digest_version, named, :crypto.hash(:sha256, payload)])
  end

  defp packet_bytes(entry) do
    case entry |> Map.get("packet_data_base64", "") |> Base.decode64() do
      {:ok, bytes} -> bytes
      :error -> raise ArgumentError, "invalid archive packet data for #{entry["record_id"]}"
    end
  end

  defp receipt_time(entry) do
    {:ok, time, _offset} = entry |> Map.fetch!("receipt_time") |> DateTime.from_iso8601()
    time
  end

  defp segment_row(entries, object_key, opts) do
    times = Enum.map(entries, &receipt_time/1)
    kinds = Enum.frequencies_by(entries, &Map.fetch!(&1, "record_kind"))

    %SegmentRow{
      archive_backend: FileSystem.archive_backend(opts),
      mission_id: entries |> hd() |> Map.fetch!("mission_id"),
      organization_id: Keyword.get(opts, :organization_id),
      object_key: object_key,
      packet_count: Map.get(kinds, @packet_kind, 0),
      frame_count: Map.get(kinds, @frame_kind, 0),
      first_receipt_time: usec(Enum.min(times, DateTime)),
      last_receipt_time: usec(Enum.max(times, DateTime)),
      spacecraft_ids: distinct_values(entries, &Map.get(&1, "spacecraft_id")),
      realized_contact_ids: distinct_values(entries, &contact_id/1),
      source_refs: distinct_values(entries, &Map.get(&1, "source_ref")),
      evidence_ids: distinct_values(entries, &Map.get(&1, "evidence_id"))
    }
  end

  defp contact_id(entry), do: get_in(entry, ["metadata", "realized_contact_id"])

  defp distinct_values(entries, fun),
    do: entries |> Enum.map(fun) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

  defp usec(%DateTime{} = time) do
    {microsecond, _precision} = time.microsecond
    %{time | microsecond: {microsecond, 6}}
  end

  # Chunked below PostgreSQL's 65,535 parameter limit, inside the caller's transaction. Returns the
  # records that were new (a conflicting row is skipped by the insert and judged afterwards).
  defp insert_identities(repo, segment_id, rows, opts) do
    rows
    |> Enum.chunk_every(@chunk)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, inserted} ->
      case insert_chunk(repo, segment_id, chunk, opts) do
        {:ok, new} -> {:cont, {:ok, new ++ inserted}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_chunk(repo, segment_id, chunk, opts) do
    identities =
      Enum.map(chunk, &Map.take(&1, [:record_kind, :record_id, :content_sha256]))
      |> Enum.map(&Map.put(&1, :segment_id, segment_id))

    # A backlog-sized VALUES plan can retain megabytes in every pool connection after the flush.
    # These variable-size batches are transient.
    {_count, returned} =
      repo.insert_all(IdentityRow, identities,
        cache_statement: false,
        on_conflict: :nothing,
        conflict_target: [:record_kind, :record_id],
        returning: [:record_kind, :record_id]
      )

    new = MapSet.new(returned, &{&1.record_kind, &1.record_id})

    {fresh, skipped} =
      Enum.split_with(chunk, &MapSet.member?(new, {&1.record_kind, &1.record_id}))

    case conflicting(skipped, opts) do
      [] -> {:ok, fresh}
      ids -> {:error, {:protocol_archive_record_identity_conflict, ids}}
    end
  end

  # The skipped records that are not the same record as the one already indexed under their id.
  defp conflicting([], _opts), do: []

  defp conflicting(skipped, opts) do
    repo = repo(opts)
    kinds = skipped |> Enum.map(& &1.record_kind) |> Enum.uniq()
    ids = Enum.map(skipped, & &1.record_id)

    existing =
      IdentityRow
      |> join(:inner, [i], s in SegmentRow, on: s.id == i.segment_id)
      |> where([i], i.record_kind in ^kinds and i.record_id in ^ids)
      |> select([i, s], %{
        key: {i.record_kind, i.record_id},
        sha: i.content_sha256,
        object_key: s.object_key
      })
      |> repo.all()
      |> Map.new(&{&1.key, &1})

    skipped
    |> Enum.reject(fn row ->
      case Map.fetch(existing, {row.record_kind, row.record_id}) do
        {:ok, found} -> same_record?(row, found, opts)
        # Skipped by the insert but not found: a concurrent rollback. Index it next time.
        :error -> false
      end
    end)
    |> Enum.map(& &1.record_id)
    |> Enum.sort()
  end

  defp same_record?(row, %{object_key: object_key} = found, opts),
    do: found.sha == row.content_sha256 and segment_present?(object_key, opts)

  defp segment_present?(object_key, opts) do
    case Keyword.fetch(opts, :base_path) do
      {:ok, base_path} -> File.regular?(Path.join(base_path, object_key))
      :error -> true
    end
  end

  # The frames this segment newly archived, per realized contact (a replayed duplicate was
  # already counted by the segment that archived it).
  defp record_frames(repo, segment, inserted) do
    by_contact =
      inserted
      |> Enum.filter(&(&1.record_kind == @frame_kind))
      |> Enum.map(&contact_id(&1.entry))
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    segment |> Ecto.Changeset.change(frames_by_contact: by_contact) |> repo.update!()
  end

  # Every record was already archived (a replay of frames archived before a stop): no index row
  # points at this segment, so its object would be duplicate bytes nobody can reach (#71 follow-up).
  defp drop_unreferenced_object(object_key, opts) do
    with {:ok, base_path} <- Keyword.fetch(opts, :base_path),
         path = Path.join(base_path, object_key),
         {:error, reason} when reason != :enoent <- File.rm(path) do
      Logger.warning("could not remove unreferenced archive segment #{path}: #{inspect(reason)}")
    end

    :ok
  end

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
end
