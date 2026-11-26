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
  alias Cadence.Platform.DurableFile
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}

  alias Cadence.Protocol.RecordArchive.FileSystem.{Index, SegmentRow, Writer}
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  @behaviour Cadence.Protocol.RecordArchive
  @archive_backend "filesystem"
  @instance_record_id_prefix "cadence-instance-record:"

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
  def persist_records_multi(
        %Multi{} = multi,
        %RawEvidence{},
        _transfer_frame_records,
        _packet_records,
        backend_opts
      )
      when is_list(backend_opts),
      do: multi

  @impl true
  def persist_records(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    persist_records(
      raw_evidence,
      transfer_frame_records,
      packet_records,
      configured_backend_opts()
    )
  end

  @impl true
  def persist_records(
        %RawEvidence{} = raw_evidence,
        transfer_frame_records,
        packet_records,
        backend_opts
      )
      when is_list(transfer_frame_records) and is_list(packet_records) and
             is_list(backend_opts) do
    Writer.enqueue(raw_evidence, transfer_frame_records, packet_records, backend_opts)
  end

  @impl true
  def persist_records_many(records_batch) when is_list(records_batch) do
    persist_records_many(records_batch, configured_backend_opts())
  end

  @impl true
  def persist_records_many(records_batch, backend_opts)
      when is_list(records_batch) and is_list(backend_opts) do
    Writer.enqueue_many(records_batch, backend_opts)
  end

  @impl true
  def fetch_packet_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_packet_records(mission_id, scope, configured_backend_opts())
  end

  @impl true
  def fetch_packet_records(mission_id, %Scope{} = scope, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    fetch_records(mission_id, scope, @packet_record_kind, backend_opts)
  end

  @impl true
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_transfer_frame_records(mission_id, scope, configured_backend_opts())
  end

  @impl true
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    fetch_records(mission_id, scope, @transfer_frame_record_kind, backend_opts)
  end

  @impl true
  def flush(mission_id \\ nil) do
    flush(mission_id, configured_backend_opts())
  end

  @impl true
  def flush(mission_id, backend_opts)
      when (is_binary(mission_id) or is_nil(mission_id)) and is_list(backend_opts) do
    Writer.flush(mission_id, backend_opts)
  end

  @impl true
  def reset do
    reset(configured_backend_opts())
  end

  @impl true
  def reset(backend_opts) when is_list(backend_opts) do
    archive_backend = archive_backend(backend_opts)
    repo = repo(backend_opts)

    _ =
      SegmentRow
      |> where([row], row.archive_backend == ^archive_backend)
      |> repo.delete_all()

    Writer.reset(backend_opts)
  end

  @impl true
  def stats(mission_id) when is_binary(mission_id) do
    stats(mission_id, configured_backend_opts())
  end

  @impl true
  def stats(mission_id, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    Writer.stats(mission_id, backend_opts)
  end

  @impl true
  def reset_stats(mission_id) when is_binary(mission_id) do
    reset_stats(mission_id, configured_backend_opts())
  end

  @impl true
  def reset_stats(mission_id, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    Writer.reset_stats(mission_id, backend_opts)
  end

  @spec persist_segment(binary(), [map()], keyword()) :: :ok | {:error, term()}
  def persist_segment(segment_id, entries, opts \\ [])
      when is_binary(segment_id) and is_list(entries),
      do: Index.persist_segment(segment_id, entries, opts)

  @doc "The record id an entry is indexed under (what an identity conflict names)."
  @spec entry_index_record_id(map(), keyword()) :: binary()
  def entry_index_record_id(entry, opts \\ []),
    do: index_record_id(Map.fetch!(entry, "record_id"), archive_backend(opts))

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
    payload = :erlang.term_to_binary(%{version: 1, entries: entries}, compressed: 6)

    case DurableFile.write_new(absolute_path, payload) do
      :ok ->
        {:ok, object_key, byte_size(payload)}

      {:error, reason} ->
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
    evidence_sha256 = Base.encode16(:crypto.hash(:sha256, raw_evidence.raw), case: :lower)

    frame_entries =
      Enum.map(transfer_frame_records, fn %TransferFrameRecord{} = frame_record ->
        %{
          "record_kind" => @transfer_frame_record_kind,
          "record_id" => frame_record.frame_record_id,
          "evidence_id" => frame_record.evidence_id,
          "evidence_sha256" => evidence_sha256,
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
          "evidence_sha256" => evidence_sha256,
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

  @doc false
  @spec archive_backend(keyword()) :: binary()
  def archive_backend(opts) when is_list(opts) do
    case Keyword.fetch(opts, :archive_backend) do
      {:ok, archive_backend} when is_binary(archive_backend) and archive_backend != "" ->
        archive_backend

      {:ok, archive_backend} ->
        raise ArgumentError,
              "expected protocol record archive :archive_backend to be a non-empty string, got: #{inspect(archive_backend)}"

      :error ->
        instance_archive_backend(Keyword.get(opts, :instance_id))
    end
  end

  defp fetch_records(mission_id, %Scope{} = scope, record_kind, backend_opts) do
    with :ok <- flush(mission_id, backend_opts),
         {:ok, records} <- load_records(mission_id, scope, record_kind, backend_opts) do
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

  defp load_records(mission_id, %Scope{} = scope, record_kind, backend_opts) do
    mission_id
    |> Index.candidate_segments(scope, record_kind, backend_opts)
    |> Enum.reduce_while({:ok, {[], MapSet.new()}}, fn segment, {:ok, acc} ->
      case load_segment_object(segment.object_key, backend_opts) do
        {:ok, entries} -> {:cont, {:ok, select_entries(entries, scope, record_kind, acc)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, {records, _seen}} ->
        sorted = Enum.sort_by(records, &record_sort_key/1)
        {:ok, if(scope.limit, do: Enum.take(sorted, scope.limit), else: sorted)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Segments arrive oldest first, so a record archived twice (a replay) resolves to the original.
  defp select_entries(entries, scope, record_kind, {records, seen}) do
    Enum.reduce(entries, {records, seen}, fn entry, {records, seen} ->
      key = {Map.get(entry, "record_kind"), Map.get(entry, "record_id")}

      if Map.get(entry, "record_kind") == record_kind and not MapSet.member?(seen, key) and
           in_scope?(entry, scope) do
        {[decode_record(entry) | records], MapSet.put(seen, key)}
      else
        {records, seen}
      end
    end)
  end

  defp in_scope?(entry, scope) do
    in_time_range?(entry, scope) and in_evidence?(entry, scope.evidence_ids) and
      matches?(entry, "spacecraft_id", scope.spacecraft_id) and
      matches?(entry, "source_ref", scope.source_ref) and
      (is_nil(scope.realized_contact_id) or
         get_in(entry, ["metadata", "realized_contact_id"]) == scope.realized_contact_id) and
      matches_metadata_scope?(entry, scope.metadata_match)
  end

  defp in_evidence?(_entry, evidence_ids) when evidence_ids in [nil, []], do: true
  defp in_evidence?(entry, evidence_ids), do: Map.get(entry, "evidence_id") in evidence_ids

  defp matches?(_entry, _key, nil), do: true
  defp matches?(entry, key, value), do: Map.get(entry, key) == value

  defp in_time_range?(entry, scope) do
    receipt_time = decode_datetime(Map.get(entry, "receipt_time"))

    (is_nil(scope.from_receipt_time) or
       DateTime.compare(receipt_time, scope.from_receipt_time) != :lt) and
      (is_nil(scope.to_receipt_time) or
         DateTime.compare(receipt_time, scope.to_receipt_time) != :gt)
  end

  defp matches_metadata_scope?(_entry, nil), do: true

  defp matches_metadata_scope?(entry, metadata_match) when is_map(metadata_match) do
    metadata = Map.get(entry, "metadata", %{})

    Enum.all?(metadata_match, fn {key, value} ->
      Map.get(metadata, to_string(key)) == value or Map.get(metadata, key) == value
    end)
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

  defp encode_atom(nil), do: nil
  defp encode_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp decode_atom(nil), do: nil
  defp decode_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp missing_evidence_ids(records, evidence_ids) do
    found_ids = MapSet.new(Enum.map(records, & &1.evidence_id))
    Enum.reject(Enum.uniq(evidence_ids), &MapSet.member?(found_ids, &1))
  end

  defp configured_backend_opts do
    :cadence
    |> Application.get_env(:protocol_record_archive, [])
    |> Keyword.delete(:module)
  end

  defp instance_archive_backend(nil), do: @archive_backend

  defp instance_archive_backend(instance_id)
       when is_binary(instance_id) and instance_id != "" do
    encoded_instance_id = Base.url_encode64(instance_id, padding: false)
    "#{@archive_backend}:#{encoded_instance_id}"
  end

  defp instance_archive_backend(instance_id) do
    raise ArgumentError,
          "expected protocol record archive :instance_id to be a non-empty string, got: #{inspect(instance_id)}"
  end

  defp index_record_id(record_id, @archive_backend), do: record_id

  defp index_record_id(record_id, archive_backend) do
    encoded =
      {archive_backend, record_id}
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    @instance_record_id_prefix <> encoded
  end

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)

  @doc false
  @spec received_frames(binary(), [binary()]) :: %{binary() => non_neg_integer()}
  defdelegate received_frames(mission_id, realized_contact_ids), to: Index
end
