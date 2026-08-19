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
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Protocol.{PacketRecord, ProtocolAnomaly, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.Postgres.ProtocolAnomalyRow
  alias Cadence.Replay.Scope

  @default_backend Cadence.Protocol.RecordArchive.Postgres

  @type backend_opts :: keyword()
  @type policy :: %{
          required(:backend) => module(),
          required(:backend_opts) => backend_opts()
        }

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

  @callback persist_records_multi(
              Multi.t(),
              RawEvidence.t(),
              [TransferFrameRecord.t()],
              [PacketRecord.t()],
              backend_opts()
            ) :: Multi.t()

  @callback persist_records(
              RawEvidence.t(),
              [TransferFrameRecord.t()],
              [PacketRecord.t()],
              backend_opts()
            ) :: :ok | {:error, term()}

  @callback fetch_packet_records(binary(), Scope.t(), backend_opts()) ::
              {:ok, [PacketRecord.t()]} | {:error, term()}

  @callback fetch_transfer_frame_records(binary(), Scope.t(), backend_opts()) ::
              {:ok, [TransferFrameRecord.t()]} | {:error, term()}

  @callback flush(binary() | nil, backend_opts()) :: :ok | {:error, term()}
  @callback reset(backend_opts()) :: :ok
  @callback stats(binary(), backend_opts()) :: stats()
  @callback reset_stats(binary(), backend_opts()) :: :ok

  @callback persist_records_many([
              {RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}
            ]) :: :ok | {:error, term()}

  @callback persist_records_many(
              [{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}],
              backend_opts()
            ) :: :ok | {:error, term()}

  @optional_callbacks persist_records_many: 1,
                      persist_records_many: 2,
                      persist_records_multi: 5,
                      persist_records: 4,
                      fetch_packet_records: 3,
                      fetch_transfer_frame_records: 3,
                      flush: 2,
                      reset: 1,
                      stats: 2,
                      reset_stats: 2

  @doc """
  Builds a child spec from the current application configuration.

  This compatibility arity reads application configuration when called. The
  supervised runtime uses `child_spec/1` with a policy captured at startup.
  """
  @spec child_spec() :: Supervisor.child_spec() | nil
  def child_spec, do: child_spec(configured_policy())

  @spec child_spec(policy()) :: Supervisor.child_spec() | nil
  def child_spec(%{backend: backend, backend_opts: backend_opts}) do
    backend = ensure_backend_loaded!(backend)

    if function_exported?(backend, :child_spec, 1) do
      backend.child_spec(backend_opts)
    end
  end

  @spec add_anomaly_inserts(Multi.t(), [ProtocolAnomaly.t()]) :: Multi.t()
  def add_anomaly_inserts(%Multi{} = multi, anomalies) when is_list(anomalies) do
    inserted_at = DateTime.utc_now()

    organization_id =
      case anomalies do
        [%ProtocolAnomaly{mission_id: mission_id} | _rest] ->
          OrganizationScope.organization_id_for_mission(mission_id)

        _other ->
          nil
      end

    rows =
      Enum.map(anomalies, fn %ProtocolAnomaly{} = anomaly ->
        ProtocolAnomalyRow.row_attrs(
          anomaly,
          organization_id: organization_id,
          inserted_at: inserted_at
        )
      end)

    if rows == [] do
      multi
    else
      Multi.insert_all(
        multi,
        :protocol_anomalies,
        ProtocolAnomalyRow,
        rows,
        on_conflict: :nothing,
        conflict_target: [:anomaly_id]
      )
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
    persist_records_multi(
      configured_policy(),
      multi,
      raw_evidence,
      transfer_frame_records,
      packet_records
    )
  end

  @spec persist_records_multi(
          policy(),
          Multi.t(),
          RawEvidence.t(),
          [TransferFrameRecord.t()],
          [PacketRecord.t()]
        ) :: Multi.t()
  def persist_records_multi(
        %{} = policy,
        %Multi{} = multi,
        %RawEvidence{} = raw_evidence,
        transfer_frame_records,
        packet_records
      )
      when is_list(transfer_frame_records) and is_list(packet_records) do
    call_backend(policy, :persist_records_multi, [
      multi,
      raw_evidence,
      transfer_frame_records,
      packet_records
    ])
  end

  @spec persist_records(RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]) ::
          :ok | {:error, term()}
  def persist_records(%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records)
      when is_list(transfer_frame_records) and is_list(packet_records) do
    persist_records(configured_policy(), raw_evidence, transfer_frame_records, packet_records)
  end

  @spec persist_records(
          policy(),
          RawEvidence.t(),
          [TransferFrameRecord.t()],
          [PacketRecord.t()]
        ) :: :ok | {:error, term()}
  def persist_records(
        %{} = policy,
        %RawEvidence{} = raw_evidence,
        transfer_frame_records,
        packet_records
      )
      when is_list(transfer_frame_records) and is_list(packet_records) do
    call_backend(policy, :persist_records, [
      raw_evidence,
      transfer_frame_records,
      packet_records
    ])
  end

  @spec persist_records_many([{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}]) ::
          :ok | {:error, term()}
  def persist_records_many(records_batch) when is_list(records_batch),
    do: persist_records_many(configured_policy(), records_batch)

  @spec persist_records_many(
          policy(),
          [{RawEvidence.t(), [TransferFrameRecord.t()], [PacketRecord.t()]}]
        ) :: :ok | {:error, term()}
  def persist_records_many(%{} = policy, records_batch) when is_list(records_batch) do
    backend = backend(policy)

    cond do
      records_batch == [] ->
        :ok

      backend_call_exported?(backend, :persist_records_many, 1) ->
        call_backend(policy, :persist_records_many, [records_batch])

      true ->
        Enum.reduce_while(records_batch, :ok, fn
          {%RawEvidence{} = raw_evidence, transfer_frame_records, packet_records}, :ok
          when is_list(transfer_frame_records) and is_list(packet_records) ->
            persist_record_batch_entry(
              policy,
              raw_evidence,
              transfer_frame_records,
              packet_records
            )

          _other, :ok ->
            {:halt, {:error, :invalid_protocol_record_batch}}
        end)
    end
  end

  defp persist_record_batch_entry(
         policy,
         %RawEvidence{} = raw_evidence,
         transfer_frame_records,
         packet_records
       ) do
    case call_backend(policy, :persist_records, [
           raw_evidence,
           transfer_frame_records,
           packet_records
         ]) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  @spec fetch_packet_records(binary(), Scope.t()) ::
          {:ok, [PacketRecord.t()]} | {:error, term()}
  def fetch_packet_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_packet_records(configured_policy(), mission_id, scope)
  end

  @spec fetch_packet_records(policy(), binary(), Scope.t()) ::
          {:ok, [PacketRecord.t()]} | {:error, term()}
  def fetch_packet_records(%{} = policy, mission_id, %Scope{} = scope)
      when is_binary(mission_id),
      do: call_backend(policy, :fetch_packet_records, [mission_id, scope])

  @spec fetch_transfer_frame_records(binary(), Scope.t()) ::
          {:ok, [TransferFrameRecord.t()]} | {:error, term()}
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_transfer_frame_records(configured_policy(), mission_id, scope)
  end

  @spec fetch_transfer_frame_records(policy(), binary(), Scope.t()) ::
          {:ok, [TransferFrameRecord.t()]} | {:error, term()}
  def fetch_transfer_frame_records(%{} = policy, mission_id, %Scope{} = scope)
      when is_binary(mission_id),
      do: call_backend(policy, :fetch_transfer_frame_records, [mission_id, scope])

  @spec flush(binary() | nil) :: :ok | {:error, term()}
  def flush(mission_id \\ nil), do: flush(configured_policy(), mission_id)

  @spec flush(policy(), binary() | nil) :: :ok | {:error, term()}
  def flush(%{} = policy, mission_id) do
    backend = backend(policy)

    if backend_call_exported?(backend, :flush, 1) do
      call_backend(policy, :flush, [mission_id])
    else
      :ok
    end
  end

  @spec reset() :: :ok
  def reset, do: reset(configured_policy())

  @spec reset(policy()) :: :ok
  def reset(%{} = policy) do
    backend = backend(policy)

    if backend_call_exported?(backend, :reset, 0) do
      call_backend(policy, :reset, [])
    else
      :ok
    end
  end

  @spec stats(binary()) :: stats()
  def stats(mission_id) when is_binary(mission_id) do
    stats(configured_policy(), mission_id)
  end

  @spec stats(policy(), binary()) :: stats()
  def stats(%{} = policy, mission_id) when is_binary(mission_id) do
    backend = backend(policy)

    if backend_call_exported?(backend, :stats, 1) do
      call_backend(policy, :stats, [mission_id])
    else
      empty_stats()
    end
  end

  @spec reset_stats(binary()) :: :ok
  def reset_stats(mission_id) when is_binary(mission_id) do
    reset_stats(configured_policy(), mission_id)
  end

  @spec reset_stats(policy(), binary()) :: :ok
  def reset_stats(%{} = policy, mission_id) when is_binary(mission_id) do
    backend = backend(policy)

    if backend_call_exported?(backend, :reset_stats, 1) do
      call_backend(policy, :reset_stats, [mission_id])
    else
      :ok
    end
  end

  @doc false
  @spec policy(keyword() | map()) :: policy()
  def policy(config) when is_list(config) or is_map(config) do
    config = if is_map(config), do: Map.to_list(config), else: config

    %{
      backend: Keyword.get(config, :module, @default_backend),
      backend_opts: Keyword.delete(config, :module)
    }
  end

  @doc false
  @spec configured_policy() :: policy()
  def configured_policy do
    :cadence
    |> Application.get_env(:protocol_record_archive, [])
    |> policy()
  end

  defp backend(%{backend: backend}), do: ensure_backend_loaded!(backend)

  defp call_backend(%{backend_opts: backend_opts} = policy, function, args) do
    backend = backend(policy)

    if function_exported?(backend, function, length(args) + 1) do
      apply(backend, function, args ++ [backend_opts])
    else
      apply(backend, function, args)
    end
  end

  defp backend_call_exported?(backend, function, arity) do
    function_exported?(backend, function, arity + 1) or
      function_exported?(backend, function, arity)
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
