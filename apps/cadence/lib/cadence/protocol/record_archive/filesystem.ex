# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Protocol.RecordArchive.FileSystem do
  @moduledoc """
  Local filesystem protocol-record archive backend.

  Packet and transfer-frame records are buffered in memory, flushed into
  segment files, and indexed in Postgres with lightweight metadata rows for
  archive lookup.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Ids
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}

  alias Cadence.Protocol.RecordArchive.FileSystem.RecordEntryRow,
    as: ProtocolArchiveRecordEntryRow

  alias Cadence.Protocol.RecordArchive.FileSystem.Writer
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  @behaviour Cadence.Protocol.RecordArchive
  @archive_backend "filesystem"

  @packet_record_kind "packet_record"
  @transfer_frame_record_kind "transfer_frame_record"

  @impl true
  def child_spec(opts) when is_list(opts) do
    Writer.child_spec(opts)
  end

  @impl true
  def persist_records_multi(
        %Multi{} = multi,
        %RawEvidence{},
        _transfer_frame_records,
        _packet_records
      ),
      do: multi

  @impl true
  def persist_records(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    Writer.enqueue(raw_evidence, transfer_frame_records, packet_records)
  end

  def persist_records_many(records_batch) when is_list(records_batch) do
    Writer.enqueue_many(records_batch)
  end

  @impl true
  def fetch_packet_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_records(mission_id, scope, @packet_record_kind)
  end

  @impl true
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_records(mission_id, scope, @transfer_frame_record_kind)
  end

  @impl true
  def flush(mission_id \\ nil) do
    Writer.flush(mission_id)
  end

  @impl true
  def reset do
    _ = Repo.delete_all(ProtocolArchiveRecordEntryRow)
    Writer.reset()
  end

  @impl true
  def stats(mission_id) when is_binary(mission_id) do
    Writer.stats(mission_id)
  end

  @impl true
  def reset_stats(mission_id) when is_binary(mission_id) do
    Writer.reset_stats(mission_id)
  end

  @spec persist_segment(binary(), [map()], keyword()) :: :ok | {:error, term()}
  def persist_segment(segment_id, entries, opts \\ [])
      when is_binary(segment_id) and is_list(entries) do
    object_key = Keyword.fetch!(opts, :object_key)
    archive_backend = Keyword.get(opts, :archive_backend, @archive_backend)
    inserted_at = normalize_datetime(DateTime.utc_now())

    rows =
      Enum.map(entries, fn entry ->
        %{
          entry_id: entry_id(entry),
          record_kind: Map.fetch!(entry, "record_kind"),
          record_id: Map.fetch!(entry, "record_id"),
          segment_id: segment_id,
          object_key: object_key,
          archive_backend: archive_backend,
          mission_id: Map.fetch!(entry, "mission_id"),
          organization_id: Keyword.get(opts, :organization_id),
          evidence_id: Map.fetch!(entry, "evidence_id"),
          source_endpoint_ref: Map.get(entry, "source_endpoint_ref"),
          spacecraft_id: Map.get(entry, "spacecraft_id"),
          protocol_family: Map.fetch!(entry, "protocol_family"),
          direction: Map.get(entry, "direction"),
          source_time: normalize_datetime(decode_datetime(Map.get(entry, "source_time"))),
          receipt_time: normalize_datetime(decode_datetime(Map.fetch!(entry, "receipt_time"))),
          source_ref: Map.get(entry, "source_ref"),
          realized_contact_id: get_in(entry, ["metadata", "realized_contact_id"]),
          path_id: get_in(entry, ["metadata", "path_id"]),
          provider_binding_id: get_in(entry, ["metadata", "provider_binding_id"]),
          apid: Map.get(entry, "apid"),
          packet_kind: Map.get(entry, "packet_kind"),
          scid: Map.get(entry, "scid"),
          vcid: Map.get(entry, "vcid"),
          map_id: Map.get(entry, "map_id"),
          frame_seq: Map.get(entry, "frame_seq"),
          metadata: Map.get(entry, "metadata", %{}),
          inserted_at: inserted_at
        }
      end)

    case Repo.insert_all(
           ProtocolArchiveRecordEntryRow,
           rows,
           on_conflict: :nothing,
           conflict_target: [:record_kind, :record_id]
         ) do
      {count, _rows} when count == length(rows) ->
        :ok

      {_count, _rows} ->
        if archived_record_ids?(rows) do
          :ok
        else
          {:error, {:protocol_archive_index_insert_mismatch, length(rows)}}
        end
    end
  end

  @spec store_segment_object(binary(), [map()], keyword()) ::
          {:ok, binary(), non_neg_integer()} | {:error, term()}
  def store_segment_object(segment_id, entries, opts \\ [])
      when is_binary(segment_id) and is_list(entries) do
    base_path = Keyword.fetch!(opts, :base_path)
    mission_id = entries |> List.first() |> Map.fetch!("mission_id")

    receipt_date =
      entries
      |> List.first()
      |> Map.fetch!("receipt_time")
      |> decode_datetime()
      |> DateTime.to_date()

    object_key =
      Path.join([
        mission_id,
        Date.to_iso8601(receipt_date),
        "#{segment_id}.bin"
      ])

    absolute_path = Path.join(base_path, object_key)
    temp_path = absolute_path <> ".tmp"
    payload = :erlang.term_to_binary(%{version: 1, entries: entries}, compressed: 6)

    with :ok <- File.mkdir_p(Path.dirname(absolute_path)),
         :ok <- File.write(temp_path, payload, [:binary]),
         :ok <- File.rename(temp_path, absolute_path) do
      {:ok, object_key, byte_size(payload)}
    else
      {:error, reason} ->
        _ = File.rm(temp_path)
        {:error, {:protocol_archive_segment_write_failed, absolute_path, reason}}
    end
  end

  @spec load_segment_object(binary(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def load_segment_object(object_key, opts \\ []) when is_binary(object_key) do
    base_path = Keyword.fetch!(opts, :base_path)
    absolute_path = Path.join(base_path, object_key)

    with {:ok, payload} <- File.read(absolute_path),
         %{version: 1, entries: entries} <- :erlang.binary_to_term(payload),
         true <- is_list(entries) do
      {:ok, entries}
    else
      {:error, reason} ->
        {:error, {:protocol_archive_segment_read_failed, absolute_path, reason}}

      _other ->
        {:error, {:protocol_archive_segment_decode_failed, absolute_path}}
    end
  end

  @spec build_entries(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]) :: [map()]
  def build_entries(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    metadata = normalize_metadata(raw_evidence.metadata)

    frame_entries =
      Enum.map(transfer_frame_records, fn %TransferFrameRecord{} = frame_record ->
        %{
          "record_kind" => @transfer_frame_record_kind,
          "record_id" => frame_record.frame_record_id,
          "evidence_id" => frame_record.evidence_id,
          "mission_id" => frame_record.mission_id,
          "source_endpoint_ref" => frame_record.source_endpoint_ref,
          "spacecraft_id" => frame_record.spacecraft_id,
          "protocol_family" => Atom.to_string(frame_record.protocol_family),
          "direction" => Atom.to_string(frame_record.direction),
          "scid" => frame_record.scid,
          "vcid" => frame_record.vcid,
          "map_id" => frame_record.map_id,
          "frame_seq" => frame_record.frame_seq,
          "raw_frame_offset_bytes" => frame_record.raw_frame_offset_bytes,
          "raw_frame_length_bytes" => frame_record.raw_frame_length_bytes,
          "payload_length_bytes" => frame_record.payload_length_bytes,
          "first_header_pointer" => frame_record.first_header_pointer,
          "quality" => encode_atom(frame_record.quality),
          "source_time" => encode_datetime(frame_record.source_time),
          "receipt_time" => encode_datetime(frame_record.receipt_time),
          "source_ref" => raw_evidence.source_ref,
          "metadata" => metadata,
          "record_metadata" => frame_record.metadata || %{}
        }
      end)

    packet_entries =
      Enum.map(packet_records, fn %PacketRecord{} = packet_record ->
        %{
          "record_kind" => @packet_record_kind,
          "record_id" => packet_record.packet_id,
          "evidence_id" => packet_record.evidence_id,
          "mission_id" => packet_record.mission_id,
          "source_endpoint_ref" => packet_record.source_endpoint_ref,
          "spacecraft_id" => packet_record.spacecraft_id,
          "protocol_family" => Atom.to_string(packet_record.protocol_family),
          "direction" => Atom.to_string(raw_evidence.direction),
          "apid" => packet_record.apid,
          "packet_kind" => Atom.to_string(packet_record.packet_kind),
          "sequence_flags" => packet_record.sequence_flags,
          "sequence_count" => packet_record.sequence_count,
          "secondary_header" => packet_record.secondary_header?,
          "packet_data_base64" => Base.encode64(packet_record.packet_data),
          "source_time" => encode_datetime(packet_record.source_time),
          "receipt_time" => encode_datetime(packet_record.receipt_time),
          "source_ref" => raw_evidence.source_ref,
          "metadata" => metadata,
          "provenance" => packet_record.provenance || %{}
        }
      end)

    frame_entries ++ packet_entries
  end

  @spec new_segment_id() :: binary()
  def new_segment_id, do: Ids.new("protocol_segment")

  defp fetch_records(mission_id, %Scope{} = scope, record_kind) do
    with :ok <- flush(mission_id),
         rows <- query_rows(mission_id, scope, record_kind),
         {:ok, records} <- load_records(rows, scope, record_kind) do
      case scope.evidence_ids do
        evidence_ids when is_list(evidence_ids) and evidence_ids != [] ->
          missing_evidence_ids = missing_evidence_ids(records, evidence_ids)

          if missing_evidence_ids == [] do
            {:ok, records}
          else
            {:error, {:evidence_not_found, missing_evidence_ids}}
          end

        _other ->
          case records do
            [] -> {:error, :empty_replay_scope}
            _ -> {:ok, records}
          end
      end
    end
  end

  defp query_rows(mission_id, %Scope{} = scope, record_kind) do
    ProtocolArchiveRecordEntryRow
    |> where([row], row.mission_id == ^mission_id and row.record_kind == ^record_kind)
    |> maybe_filter_scope(scope)
    |> order_by([row], asc: row.receipt_time, asc: row.record_id)
    |> maybe_limit_scope(scope.limit)
    |> Repo.all()
  end

  defp maybe_filter_scope(query, %Scope{} = scope) do
    query
    |> maybe_filter_evidence_ids(scope.evidence_ids)
    |> maybe_filter_from_receipt_time(scope.from_receipt_time)
    |> maybe_filter_to_receipt_time(scope.to_receipt_time)
    |> maybe_filter_spacecraft(scope.spacecraft_id)
    |> maybe_filter_source_ref(scope.source_ref)
    |> maybe_filter_realized_contact_id(scope.realized_contact_id)
    |> maybe_filter_metadata_match(scope.metadata_match)
  end

  defp maybe_filter_evidence_ids(query, nil), do: query

  defp maybe_filter_evidence_ids(query, evidence_ids)
       when is_list(evidence_ids) and evidence_ids != [] do
    where(query, [row], row.evidence_id in ^Enum.uniq(evidence_ids))
  end

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = from_receipt_time) do
    where(query, [row], row.receipt_time >= ^from_receipt_time)
  end

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = to_receipt_time) do
    where(query, [row], row.receipt_time <= ^to_receipt_time)
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) when is_binary(spacecraft_id) do
    where(query, [row], row.spacecraft_id == ^spacecraft_id)
  end

  defp maybe_filter_source_ref(query, nil), do: query

  defp maybe_filter_source_ref(query, source_ref) when is_binary(source_ref) do
    where(query, [row], row.source_ref == ^source_ref)
  end

  defp maybe_filter_realized_contact_id(query, nil), do: query

  defp maybe_filter_realized_contact_id(query, realized_contact_id)
       when is_binary(realized_contact_id) do
    where(query, [row], row.realized_contact_id == ^realized_contact_id)
  end

  defp maybe_filter_metadata_match(query, nil), do: query

  defp maybe_filter_metadata_match(query, metadata_match)
       when is_map(metadata_match) and map_size(metadata_match) > 0 do
    Enum.reduce(metadata_match, query, fn {key, value}, acc ->
      where(acc, [row], fragment("? ->> ? = ?", row.metadata, ^to_string(key), ^to_string(value)))
    end)
  end

  defp maybe_filter_metadata_match(query, _metadata_match), do: query

  defp maybe_limit_scope(query, nil), do: query
  defp maybe_limit_scope(query, limit), do: limit(query, ^limit)

  defp load_records(rows, %Scope{} = scope, record_kind) do
    backend_opts = backend_opts()

    rows
    |> Enum.group_by(& &1.object_key)
    |> Enum.reduce_while({:ok, []}, fn {object_key, grouped_rows}, {:ok, acc} ->
      case load_segment_object(object_key, backend_opts) do
        {:ok, entries} ->
          selected_ids = MapSet.new(Enum.map(grouped_rows, & &1.record_id))

          selected_records =
            entries
            |> Enum.filter(
              &selected_record_entry?(&1, record_kind, selected_ids, scope.metadata_match)
            )
            |> Enum.map(&decode_record/1)

          {:cont, {:ok, selected_records ++ acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, records} ->
        {:ok, Enum.sort_by(records, &record_sort_key/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp matches_metadata_scope?(_entry, nil), do: true

  defp matches_metadata_scope?(entry, metadata_match) when is_map(metadata_match) do
    metadata = Map.get(entry, "metadata", %{})

    Enum.all?(metadata_match, fn {key, value} ->
      Map.get(metadata, to_string(key)) == value or Map.get(metadata, key) == value
    end)
  end

  defp selected_record_entry?(entry, record_kind, selected_ids, metadata_match) do
    Map.get(entry, "record_kind") == record_kind and
      MapSet.member?(selected_ids, Map.get(entry, "record_id")) and
      matches_metadata_scope?(entry, metadata_match)
  end

  defp decode_record(%{"record_kind" => @packet_record_kind} = entry) do
    %PacketRecord{
      packet_id: Map.fetch!(entry, "record_id"),
      evidence_id: Map.fetch!(entry, "evidence_id"),
      mission_id: Map.fetch!(entry, "mission_id"),
      source_endpoint_ref: Map.get(entry, "source_endpoint_ref"),
      spacecraft_id: Map.get(entry, "spacecraft_id"),
      protocol_family: String.to_existing_atom(Map.fetch!(entry, "protocol_family")),
      packet_kind: String.to_existing_atom(Map.fetch!(entry, "packet_kind")),
      apid: Map.fetch!(entry, "apid"),
      sequence_flags: Map.fetch!(entry, "sequence_flags"),
      sequence_count: Map.fetch!(entry, "sequence_count"),
      secondary_header?: Map.fetch!(entry, "secondary_header"),
      packet_data: entry |> Map.fetch!("packet_data_base64") |> Base.decode64!(),
      source_time: decode_datetime(Map.get(entry, "source_time")),
      receipt_time: decode_datetime(Map.fetch!(entry, "receipt_time")),
      provenance: Map.get(entry, "provenance", %{})
    }
  end

  defp decode_record(%{"record_kind" => @transfer_frame_record_kind} = entry) do
    %TransferFrameRecord{
      frame_record_id: Map.fetch!(entry, "record_id"),
      evidence_id: Map.fetch!(entry, "evidence_id"),
      mission_id: Map.fetch!(entry, "mission_id"),
      source_endpoint_ref: Map.get(entry, "source_endpoint_ref"),
      spacecraft_id: Map.get(entry, "spacecraft_id"),
      protocol_family: String.to_existing_atom(Map.fetch!(entry, "protocol_family")),
      direction: String.to_existing_atom(Map.fetch!(entry, "direction")),
      scid: Map.fetch!(entry, "scid"),
      vcid: Map.fetch!(entry, "vcid"),
      map_id: Map.get(entry, "map_id"),
      frame_seq: Map.fetch!(entry, "frame_seq"),
      raw_frame_offset_bytes: Map.fetch!(entry, "raw_frame_offset_bytes"),
      raw_frame_length_bytes: Map.fetch!(entry, "raw_frame_length_bytes"),
      payload_length_bytes: Map.fetch!(entry, "payload_length_bytes"),
      first_header_pointer: Map.get(entry, "first_header_pointer"),
      quality: decode_atom(Map.get(entry, "quality")),
      source_time: decode_datetime(Map.get(entry, "source_time")),
      receipt_time: decode_datetime(Map.fetch!(entry, "receipt_time")),
      metadata: Map.get(entry, "record_metadata", %{})
    }
  end

  defp record_sort_key(%PacketRecord{} = record), do: {record.receipt_time, record.packet_id}

  defp record_sort_key(%TransferFrameRecord{} = record),
    do: {record.receipt_time, record.frame_record_id}

  defp normalize_metadata(nil), do: %{}

  defp normalize_metadata(metadata) when is_map(metadata) do
    Enum.into(metadata, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp decode_datetime(nil), do: nil

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, reason} ->
        raise "invalid protocol archive datetime #{inspect(value)}: #{inspect(reason)}"
    end
  end

  defp normalize_datetime(nil), do: nil

  defp normalize_datetime(%DateTime{} = value) do
    naive = DateTime.to_naive(value)
    {microsecond, _precision} = naive.microsecond
    with_usec = %{naive | microsecond: {microsecond, 6}}
    DateTime.from_naive!(with_usec, "Etc/UTC")
  end

  defp encode_atom(nil), do: nil
  defp encode_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp decode_atom(nil), do: nil
  defp decode_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp entry_id(entry) do
    "#{Map.fetch!(entry, "record_kind")}:#{Map.fetch!(entry, "record_id")}"
  end

  defp missing_evidence_ids(records, evidence_ids) do
    found_ids = MapSet.new(Enum.map(records, & &1.evidence_id))
    Enum.reject(Enum.uniq(evidence_ids), &MapSet.member?(found_ids, &1))
  end

  defp backend_opts do
    Application.get_env(:cadence, :protocol_record_archive, [])
  end

  defp archived_record_ids?(rows) do
    expected_pairs =
      rows
      |> Enum.map(&{Map.fetch!(&1, :record_kind), Map.fetch!(&1, :record_id)})
      |> Enum.uniq()

    expected_set = MapSet.new(expected_pairs)
    record_kinds = expected_pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    record_ids = expected_pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    found_pairs =
      ProtocolArchiveRecordEntryRow
      |> where([row], row.record_kind in ^record_kinds and row.record_id in ^record_ids)
      |> select([row], {row.record_kind, row.record_id})
      |> Repo.all()
      |> Enum.filter(&MapSet.member?(expected_set, &1))
      |> MapSet.new()

    MapSet.equal?(found_pairs, expected_set)
  end
end
