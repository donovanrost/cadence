# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.IngressArchive.FileSystem do
  @moduledoc """
  Local filesystem ingress archive backend.

  Legacy callers may buffer raw evidence in memory before a flush. Journal
  consumers use the batch-native API, which writes and indexes a deterministic
  segment before returning a durable receipt.

  Independently supervised instances use `:name` for the writer address and
  `:instance_id` for the durable index namespace. `:base_path` and `:repo`
  complete the instance state. Omitting those identity options keeps the
  legacy module-named writer, unqualified index keys, and `Cadence.Repo`;
  named writers without an explicit instance ID derive one from their root.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Ids
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.{Batch, Receipt}
  alias Cadence.IngressArchive.FileSystem.EvidenceEntryRow, as: IngressArchiveEvidenceEntryRow
  alias Cadence.IngressArchive.FileSystem.Writer
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  @behaviour Cadence.IngressArchive
  @archive_backend "filesystem"

  @impl true
  def child_spec(opts) when is_list(opts) do
    Writer.child_spec(opts)
  end

  @impl true
  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{}), do: multi

  @impl true
  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{}, backend_opts)
      when is_list(backend_opts),
      do: multi

  @impl true
  def persist_raw_evidence(%RawEvidence{} = raw_evidence) do
    persist_raw_evidence(raw_evidence, configured_backend_opts())
  end

  @impl true
  def persist_raw_evidence(%RawEvidence{} = raw_evidence, backend_opts)
      when is_list(backend_opts) do
    Writer.enqueue(writer_name(backend_opts), raw_evidence)
  end

  @impl true
  def persist_batch(%Batch{} = batch) do
    persist_batch(batch, configured_backend_opts())
  end

  @impl true
  def persist_batch(%Batch{} = batch, backend_opts) when is_list(backend_opts) do
    mission_id = batch.raw_evidences |> List.first() |> Map.fetch!(:mission_id)
    organization_id = OrganizationScope.organization_id_for_mission(mission_id)

    if archived_evidence_ids?(batch.raw_evidences, backend_opts) do
      {:ok, Receipt.for_batch(batch, :durable)}
    else
      with {:ok, object_key, _segment_size_bytes} <-
             store_segment_object(batch.batch_id, batch.raw_evidences,
               base_path: Keyword.fetch!(backend_opts, :base_path)
             ),
           :ok <-
             persist_segment(
               batch.batch_id,
               batch.raw_evidences,
               Keyword.merge(backend_opts,
                 object_key: object_key,
                 organization_id: organization_id
               )
             ) do
        {:ok, Receipt.for_batch(batch, :durable)}
      end
    end
  end

  @impl true
  def persist_raw_evidences(raw_evidences) when is_list(raw_evidences) do
    persist_raw_evidences(raw_evidences, configured_backend_opts())
  end

  @impl true
  def persist_raw_evidences(raw_evidences, backend_opts)
      when is_list(raw_evidences) and is_list(backend_opts) do
    Writer.enqueue_many(writer_name(backend_opts), raw_evidences)
  end

  @impl true
  def fetch_raw_evidences(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_raw_evidences(mission_id, scope, configured_backend_opts())
  end

  @impl true
  def fetch_raw_evidences(mission_id, %Scope{} = scope, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    with :ok <- flush(mission_id, backend_opts),
         rows <- query_rows(mission_id, scope, backend_opts),
         {:ok, raw_evidences} <- load_raw_evidences(rows, scope, backend_opts) do
      case scope.evidence_ids do
        evidence_ids when is_list(evidence_ids) and evidence_ids != [] ->
          unique_evidence_ids = Enum.uniq(evidence_ids)
          found_ids = MapSet.new(Enum.map(raw_evidences, & &1.evidence_id))

          missing_evidence_ids =
            Enum.reject(unique_evidence_ids, &MapSet.member?(found_ids, &1))

          if missing_evidence_ids == [] do
            {:ok, order_raw_evidences_by_ids(raw_evidences, unique_evidence_ids)}
          else
            {:error, {:evidence_not_found, missing_evidence_ids}}
          end

        _other ->
          case raw_evidences do
            [] -> {:error, :empty_replay_scope}
            _ -> {:ok, raw_evidences}
          end
      end
    end
  end

  @impl true
  def flush(mission_id \\ nil) do
    flush(mission_id, configured_backend_opts())
  end

  @impl true
  def flush(mission_id, backend_opts) when is_list(backend_opts) do
    Writer.flush(writer_name(backend_opts), mission_id)
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
      IngressArchiveEvidenceEntryRow
      |> where([row], row.archive_backend == ^archive_backend)
      |> repo.delete_all()

    Writer.reset(writer_name(backend_opts))
  end

  @impl true
  def stats(mission_id) when is_binary(mission_id) do
    stats(mission_id, configured_backend_opts())
  end

  @impl true
  def stats(mission_id, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    Writer.stats(writer_name(backend_opts), mission_id)
  end

  @impl true
  def reset_stats(mission_id) when is_binary(mission_id) do
    reset_stats(mission_id, configured_backend_opts())
  end

  @impl true
  def reset_stats(mission_id, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    Writer.reset_stats(writer_name(backend_opts), mission_id)
  end

  @spec persist_segment(binary(), [RawEvidence.t()], keyword()) :: :ok | {:error, term()}
  def persist_segment(segment_id, raw_evidences, opts \\ [])
      when is_binary(segment_id) and is_list(raw_evidences) do
    object_key = Keyword.fetch!(opts, :object_key)
    archive_backend = archive_backend(opts)
    repo = repo(opts)
    inserted_at = normalize_datetime(DateTime.utc_now())

    rows =
      Enum.map(raw_evidences, fn %RawEvidence{} = raw_evidence ->
        metadata = raw_evidence.metadata || %{}

        %{
          evidence_id: database_evidence_id(raw_evidence.evidence_id, opts),
          segment_id: segment_id,
          object_key: object_key,
          archive_backend: archive_backend,
          mission_id: raw_evidence.mission_id,
          organization_id: Keyword.get(opts, :organization_id),
          source_endpoint_ref: raw_evidence.source_endpoint_ref,
          spacecraft_id: raw_evidence.spacecraft_id,
          protocol_family: Atom.to_string(raw_evidence.protocol_family),
          direction: Atom.to_string(raw_evidence.direction),
          source_time: normalize_datetime(raw_evidence.source_time),
          receipt_time: normalize_datetime(raw_evidence.receipt_time),
          source_ref: raw_evidence.source_ref,
          realized_contact_id: Map.get(metadata, "realized_contact_id"),
          path_id: Map.get(metadata, "path_id"),
          provider_binding_id: Map.get(metadata, "provider_binding_id"),
          raw_size_bytes: byte_size(raw_evidence.raw),
          metadata: metadata,
          inserted_at: inserted_at
        }
      end)

    case repo.insert_all(
           IngressArchiveEvidenceEntryRow,
           rows,
           on_conflict: :nothing,
           conflict_target: [:evidence_id]
         ) do
      {count, _rows} when count == length(rows) ->
        :ok

      {_count, _rows} ->
        if archived_evidence_ids?(raw_evidences, opts) do
          :ok
        else
          {:error, {:archive_index_insert_mismatch, length(rows)}}
        end
    end
  end

  @spec store_segment_object(binary(), [RawEvidence.t()], keyword()) ::
          {:ok, binary(), non_neg_integer()} | {:error, term()}
  def store_segment_object(segment_id, raw_evidences, opts \\ [])
      when is_binary(segment_id) and is_list(raw_evidences) do
    base_path = Keyword.fetch!(opts, :base_path)
    mission_id = raw_evidences |> List.first() |> Map.fetch!(:mission_id)

    receipt_date =
      raw_evidences |> List.first() |> Map.fetch!(:receipt_time) |> DateTime.to_date()

    object_key =
      Path.join([
        mission_id,
        Date.to_iso8601(receipt_date),
        "#{segment_id}.bin"
      ])

    absolute_path = Path.join(base_path, object_key)
    temp_path = absolute_path <> ".tmp"

    payload =
      raw_evidences
      |> Enum.map(&encode_raw_evidence/1)
      |> then(fn entries -> %{version: 1, entries: entries} end)
      |> :erlang.term_to_binary(compressed: 6)

    case File.read(absolute_path) do
      {:ok, ^payload} ->
        {:ok, object_key, byte_size(payload)}

      {:ok, _different_payload} ->
        {:error, {:archive_segment_identity_collision, absolute_path}}

      {:error, :enoent} ->
        with :ok <- File.mkdir_p(Path.dirname(absolute_path)),
             :ok <- write_synced_segment(temp_path, absolute_path, payload) do
          {:ok, object_key, byte_size(payload)}
        else
          {:error, reason} ->
            _ = File.rm(temp_path)
            {:error, {:archive_segment_write_failed, absolute_path, reason}}
        end

      {:error, reason} ->
        {:error, {:archive_segment_read_failed, absolute_path, reason}}
    end
  end

  @spec load_segment_object(binary(), keyword()) :: {:ok, [RawEvidence.t()]} | {:error, term()}
  def load_segment_object(object_key, opts \\ []) when is_binary(object_key) do
    base_path = Keyword.fetch!(opts, :base_path)
    absolute_path = Path.join(base_path, object_key)

    with {:ok, payload} <- File.read(absolute_path),
         %{version: 1, entries: entries} <- :erlang.binary_to_term(payload),
         true <- is_list(entries) do
      {:ok, Enum.map(entries, &decode_raw_evidence/1)}
    else
      {:error, reason} ->
        {:error, {:archive_segment_read_failed, absolute_path, reason}}

      _other ->
        {:error, {:archive_segment_decode_failed, absolute_path}}
    end
  end

  defp query_rows(mission_id, %Scope{} = scope, backend_opts) do
    archive_backend = archive_backend(backend_opts)
    repo = repo(backend_opts)

    IngressArchiveEvidenceEntryRow
    |> where([row], row.mission_id == ^mission_id)
    |> where([row], row.archive_backend == ^archive_backend)
    |> maybe_filter_scope(scope, backend_opts)
    |> order_by([row], asc: row.receipt_time, asc: row.evidence_id)
    |> maybe_limit_scope(scope.limit)
    |> repo.all()
  end

  defp maybe_filter_scope(query, %Scope{} = scope, backend_opts) do
    query
    |> maybe_filter_evidence_ids(scope.evidence_ids, backend_opts)
    |> maybe_filter_from_receipt_time(scope.from_receipt_time)
    |> maybe_filter_to_receipt_time(scope.to_receipt_time)
    |> maybe_filter_spacecraft(scope.spacecraft_id)
    |> maybe_filter_source_ref(scope.source_ref)
    |> maybe_filter_realized_contact_id(scope.realized_contact_id)
  end

  defp maybe_filter_evidence_ids(query, nil, _backend_opts), do: query

  defp maybe_filter_evidence_ids(query, evidence_ids, backend_opts)
       when is_list(evidence_ids) and evidence_ids != [] do
    unique_evidence_ids =
      evidence_ids
      |> Enum.uniq()
      |> Enum.map(&database_evidence_id(&1, backend_opts))

    where(query, [row], row.evidence_id in ^unique_evidence_ids)
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

  defp maybe_limit_scope(query, nil), do: query
  defp maybe_limit_scope(query, limit), do: limit(query, ^limit)

  defp load_raw_evidences(rows, %Scope{} = scope, backend_opts) do
    rows
    |> Enum.group_by(& &1.object_key)
    |> Enum.reduce_while({:ok, []}, fn {object_key, grouped_rows}, {:ok, acc} ->
      case load_segment_object(object_key, backend_opts) do
        {:ok, raw_evidences} ->
          selected_ids = MapSet.new(Enum.map(grouped_rows, & &1.evidence_id))

          selected_raw_evidences =
            raw_evidences
            |> Enum.filter(
              &selected_raw_evidence?(&1, selected_ids, scope.metadata_match, backend_opts)
            )

          {:cont, {:ok, selected_raw_evidences ++ acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, raw_evidences} ->
        {:ok,
         raw_evidences
         |> Enum.sort_by(fn %RawEvidence{} = raw_evidence ->
           {raw_evidence.receipt_time, raw_evidence.evidence_id}
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp matches_metadata_scope?(_raw_evidence, nil), do: true

  defp matches_metadata_scope?(%RawEvidence{metadata: metadata}, metadata_match)
       when is_map(metadata_match) do
    Enum.all?(metadata_match, fn {key, value} ->
      Map.get(metadata || %{}, to_string(key)) == value or Map.get(metadata || %{}, key) == value
    end)
  end

  defp encode_raw_evidence(%RawEvidence{} = raw_evidence) do
    %{
      "evidence_id" => raw_evidence.evidence_id,
      "mission_id" => raw_evidence.mission_id,
      "source_endpoint_ref" => raw_evidence.source_endpoint_ref,
      "spacecraft_id" => raw_evidence.spacecraft_id,
      "protocol_family" => Atom.to_string(raw_evidence.protocol_family),
      "direction" => Atom.to_string(raw_evidence.direction),
      "raw_base64" => Base.encode64(raw_evidence.raw),
      "source_time" => encode_datetime(raw_evidence.source_time),
      "receipt_time" => DateTime.to_iso8601(raw_evidence.receipt_time),
      "source_ref" => raw_evidence.source_ref,
      "metadata" => raw_evidence.metadata || %{}
    }
  end

  defp decode_raw_evidence(entry) when is_map(entry) do
    RawEvidence.new(%{
      evidence_id: Map.fetch!(entry, "evidence_id"),
      mission_id: Map.fetch!(entry, "mission_id"),
      source_endpoint_ref: Map.get(entry, "source_endpoint_ref"),
      spacecraft_id: Map.get(entry, "spacecraft_id"),
      protocol_family: String.to_existing_atom(Map.fetch!(entry, "protocol_family")),
      direction: String.to_existing_atom(Map.fetch!(entry, "direction")),
      raw: entry |> Map.fetch!("raw_base64") |> Base.decode64!(),
      source_time: decode_datetime(Map.get(entry, "source_time")),
      receipt_time: decode_datetime(Map.fetch!(entry, "receipt_time")),
      source_ref: Map.get(entry, "source_ref"),
      metadata: Map.get(entry, "metadata", %{})
    })
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp decode_datetime(nil), do: nil

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, reason} -> raise "invalid archive datetime #{inspect(value)}: #{inspect(reason)}"
    end
  end

  defp normalize_datetime(nil), do: nil

  defp normalize_datetime(%DateTime{} = value) do
    naive = DateTime.to_naive(value)
    {microsecond, _precision} = naive.microsecond
    with_usec = %{naive | microsecond: {microsecond, 6}}
    DateTime.from_naive!(with_usec, "Etc/UTC")
  end

  defp order_raw_evidences_by_ids(raw_evidences, evidence_ids) do
    evidence_order = Map.new(Enum.with_index(evidence_ids))

    Enum.sort_by(raw_evidences, fn %RawEvidence{} = raw_evidence ->
      Map.fetch!(evidence_order, raw_evidence.evidence_id)
    end)
  end

  defp selected_raw_evidence?(
         %RawEvidence{} = raw_evidence,
         selected_ids,
         metadata_match,
         backend_opts
       ) do
    MapSet.member?(selected_ids, database_evidence_id(raw_evidence.evidence_id, backend_opts)) and
      matches_metadata_scope?(raw_evidence, metadata_match)
  end

  defp configured_backend_opts do
    Application.get_env(:cadence, :ingress_archive, [])
  end

  defp archived_evidence_ids?(raw_evidences, backend_opts) do
    expected_ids =
      raw_evidences
      |> Enum.map(fn %RawEvidence{} = raw_evidence ->
        database_evidence_id(raw_evidence.evidence_id, backend_opts)
      end)
      |> Enum.uniq()

    archive_backend = archive_backend(backend_opts)
    repo = repo(backend_opts)

    found_ids =
      IngressArchiveEvidenceEntryRow
      |> where([row], row.evidence_id in ^expected_ids)
      |> where([row], row.archive_backend == ^archive_backend)
      |> select([row], row.evidence_id)
      |> repo.all()
      |> MapSet.new()

    MapSet.equal?(found_ids, MapSet.new(expected_ids))
  end

  @spec new_segment_id() :: binary()
  def new_segment_id, do: Ids.new("ingress_segment")

  defp writer_name(backend_opts), do: Writer.process_name(backend_opts)

  defp repo(backend_opts), do: Keyword.get(backend_opts, :repo, Repo)

  defp instance_id(backend_opts) do
    case Keyword.fetch(backend_opts, :instance_id) do
      {:ok, instance_id} when is_binary(instance_id) ->
        instance_id

      {:ok, nil} ->
        nil

      :error ->
        default_instance_id(backend_opts)
    end
  end

  defp default_instance_id(backend_opts) do
    if writer_name(backend_opts) == Writer do
      nil
    else
      backend_opts
      |> Keyword.fetch!(:base_path)
      |> Path.expand()
    end
  end

  defp archive_backend(backend_opts) do
    archive_backend = Keyword.get(backend_opts, :archive_backend, @archive_backend)

    case instance_id(backend_opts) do
      nil -> archive_backend
      instance_id -> archive_backend <> ":" <> encode_instance_id(instance_id)
    end
  end

  defp database_evidence_id(evidence_id, backend_opts) do
    case instance_id(backend_opts) do
      nil -> evidence_id
      instance_id -> "ingress_archive:" <> encode_instance_id(instance_id) <> ":" <> evidence_id
    end
  end

  defp encode_instance_id(instance_id) when is_binary(instance_id) do
    Base.url_encode64(instance_id, padding: false)
  end

  defp write_synced_segment(temp_path, absolute_path, payload) do
    with :ok <- File.write(temp_path, payload, [:binary]),
         {:ok, file} <- :file.open(temp_path, [:read, :write, :binary, :raw]) do
      sync_result = :file.sync(file)
      close_result = :file.close(file)

      with :ok <- sync_result,
           :ok <- close_result do
        File.rename(temp_path, absolute_path)
      end
    end
  end
end
