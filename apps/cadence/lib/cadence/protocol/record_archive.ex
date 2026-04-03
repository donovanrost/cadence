defmodule Cadence.Protocol.RecordArchive do
  @moduledoc """
  Pluggable archive backend for retained protocol packet and transfer-frame
  records.

  Runtime deployments can archive high-rate protocol records outside the OLTP
  database, while tests and compatibility paths can still use Postgres-backed
  persistence.
  """

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}
  alias Cadence.Replay.Scope

  @type stats :: %{
          queue_depth: non_neg_integer(),
          oldest_buffered_age_ms: non_neg_integer(),
          flush_count: non_neg_integer(),
          flush_failure_count: non_neg_integer(),
          last_flush_error: binary() | nil,
          flushed_count: non_neg_integer(),
          segment_count: non_neg_integer(),
          flush_total_us: non_neg_integer(),
          avg_flush_us: float(),
          flushed_bytes_total: non_neg_integer(),
          avg_segment_bytes: float()
        }

  @callback child_spec(keyword()) :: Supervisor.child_spec() | nil

  @callback persist_records_multi(
              Multi.t(),
              RawEvidence.t(),
              [TransferFrameRecord.t()],
              [PacketRecord.t()]
            ) :: Multi.t()

  @callback persist_records(
              RawEvidence.t(),
              [TransferFrameRecord.t()],
              [PacketRecord.t()]
            ) :: :ok | {:error, term()}

  @callback fetch_packet_records(binary(), Scope.t()) ::
              {:ok, [PacketRecord.t()]} | {:error, term()}

  @callback fetch_transfer_frame_records(binary(), Scope.t()) ::
              {:ok, [TransferFrameRecord.t()]} | {:error, term()}

  @callback flush(binary() | nil) :: :ok | {:error, term()}
  @callback reset() :: :ok
  @callback stats(binary()) :: stats()
  @callback reset_stats(binary()) :: :ok

  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :child_spec, 1) do
      backend.child_spec(backend_opts())
    end
  end

  @spec persist_records_multi(
          Multi.t(),
          RawEvidence.t(),
          [TransferFrameRecord.t()],
          [PacketRecord.t()]
        ) :: Multi.t()
  def persist_records_multi(
        %Multi{} = multi,
        %RawEvidence{} = raw_evidence,
        transfer_frame_records,
        packet_records
      )
      when is_list(transfer_frame_records) and is_list(packet_records) do
    ensure_backend_loaded!(backend_module()).persist_records_multi(
      multi,
      raw_evidence,
      transfer_frame_records,
      packet_records
    )
  end

  @spec persist_records(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]) ::
          :ok | {:error, term()}
  def persist_records(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    ensure_backend_loaded!(backend_module()).persist_records(
      raw_evidence,
      transfer_frame_records,
      packet_records
    )
  end

  @spec persist_records_many([{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}]) ::
          :ok | {:error, term()}
  def persist_records_many(records_batch) when is_list(records_batch) do
    backend = ensure_backend_loaded!(backend_module())

    cond do
      records_batch == [] ->
        :ok

      function_exported?(backend, :persist_records_many, 1) ->
        backend.persist_records_many(records_batch)

      true ->
        Enum.reduce_while(records_batch, :ok, fn
          {%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records}, :ok
          when is_list(transfer_frame_records) and is_list(packet_records) ->
            case backend.persist_records(raw_evidence, transfer_frame_records, packet_records) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          _other, :ok ->
            {:halt, {:error, :invalid_protocol_record_batch}}
        end)
    end
  end

  @spec fetch_packet_records(binary(), Scope.t()) ::
          {:ok, [PacketRecord.t()]} | {:error, term()}
  def fetch_packet_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    ensure_backend_loaded!(backend_module()).fetch_packet_records(mission_id, scope)
  end

  @spec fetch_transfer_frame_records(binary(), Scope.t()) ::
          {:ok, [TransferFrameRecord.t()]} | {:error, term()}
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    ensure_backend_loaded!(backend_module()).fetch_transfer_frame_records(mission_id, scope)
  end

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :flush, 1) do
      backend.flush(mission_id)
    else
      :ok
    end
  end

  @spec reset() :: :ok
  def reset do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :reset, 0) do
      backend.reset()
    else
      :ok
    end
  end

  @spec stats(binary()) :: stats()
  def stats(mission_id) when is_binary(mission_id) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :stats, 1) do
      backend.stats(mission_id)
    else
      empty_stats()
    end
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id) when is_binary(mission_id) do
    backend = ensure_backend_loaded!(backend_module())

    if function_exported?(backend, :reset_stats, 1) do
      backend.reset_stats(mission_id)
    else
      :ok
    end
  end

  defp backend_module do
    Application.get_env(:cadence, :protocol_record_archive, [])
    |> Keyword.get(:module, Cadence.Protocol.RecordArchive.Postgres)
  end

  defp backend_opts do
    Application.get_env(:cadence, :protocol_record_archive, [])
  end

  defp ensure_backend_loaded!(backend) when is_atom(backend) do
    case Code.ensure_loaded(backend) do
      {:module, ^backend} ->
        backend

      {:error, reason} ->
        raise "could not load protocol record archive backend #{inspect(backend)}: #{inspect(reason)}"
    end
  end

  defp empty_stats do
    %{
      queue_depth: 0,
      oldest_buffered_age_ms: 0,
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: 0,
      avg_segment_bytes: 0.0
    }
  end
end
