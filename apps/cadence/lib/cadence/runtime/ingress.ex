defmodule Cadence.Runtime.Ingress do
  @moduledoc """
  Public data-plane ingress boundary.

  Callers provide exact raw evidence whose source-endpoint identity has already
  been resolved by the control handoff and, when bypassing mission
  reconciliation for a deterministic component test, an exact immutable
  binding set. The boundary owns decoding, dispatch, runtime execution,
  persistence, and ingress latency instrumentation without querying another
  plane.
  """

  alias Cadence.ApplicationDispatch.{BindingSet, DispatchDecision, Dispatcher}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime
  alias Cadence.Runtime.IngressEvidence
  alias Cadence.Runtime.Persistence
  alias Cadence.Telemetry.Profiler, as: TelemetryProfiler

  alias Cadence.Protocol.{PacketRecord, ProtocolAnomaly, TMFrameIngress, TransferFrameRecord}
  alias Cadence.Protocol.SpacePacketDecoder

  @type processing_result :: %{
          required(:raw_evidence) => RawEvidence.t(),
          required(:packet_records) => [PacketRecord.t()],
          required(:transfer_frame_records) => [TransferFrameRecord.t()],
          required(:protocol_anomalies) => [ProtocolAnomaly.t()],
          required(:dispatch_decisions) => [DispatchDecision.t()],
          required(:outputs) => [term()],
          required(:runtime_records) => map()
        }

  @spec process(RawEvidence.t(), BindingSet.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process(%RawEvidence{} = raw_evidence, %BindingSet{} = binding_set) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <-
           IngressEvidence.validate(raw_evidence),
         :ok <- validate_binding_set_mission(resolved_raw_evidence, binding_set),
         {:ok, decode_result} <- decode_raw_evidence_packets(resolved_raw_evidence),
         {:ok, dispatch_result} <- execute_dispatches(decode_result, binding_set) do
      {:ok, build_processing_result(resolved_raw_evidence, dispatch_result)}
    end
  end

  @spec process(RawEvidence.t()) :: {:ok, processing_result()} | {:error, term()}
  def process(%RawEvidence{} = raw_evidence) do
    with {:ok, %RawEvidence{} = resolved_raw_evidence} <-
           IngressEvidence.validate(raw_evidence) do
      Runtime.process_telemetry_ingress(resolved_raw_evidence)
    end
  end

  @spec process_and_persist(RawEvidence.t(), BindingSet.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist(%RawEvidence{} = raw_evidence, %BindingSet{} = binding_set) do
    with {:ok, processing_result} <- process(raw_evidence, binding_set) do
      Persistence.persist_processing_result(processing_result)
    end
  end

  @spec process_and_persist(RawEvidence.t()) ::
          {:ok, processing_result()} | {:error, term()}
  def process_and_persist(%RawEvidence{} = raw_evidence) do
    TelemetryProfiler.with_ingress_context(raw_evidence, fn ->
      ingress_started_at = System.monotonic_time()

      resolve_result =
        TelemetryProfiler.with_stage(:resolve, fn -> IngressEvidence.validate(raw_evidence) end)

      resolve_us = elapsed_us(ingress_started_at)

      case resolve_result do
        {:ok, %RawEvidence{} = resolved_raw_evidence} ->
          handle_resolved_ingress(resolved_raw_evidence, ingress_started_at, resolve_us)

        {:error, reason} ->
          TelemetryProfiler.record_ingress_result(
            raw_evidence,
            resolve_us: resolve_us,
            end_to_end_us: elapsed_us(ingress_started_at),
            error?: true
          )

          {:error, reason}
      end
    end)
  end

  defp handle_resolved_ingress(resolved_raw_evidence, ingress_started_at, resolve_us) do
    runtime_started_at = System.monotonic_time()

    runtime_result =
      TelemetryProfiler.with_stage(:runtime, fn ->
        Runtime.process_telemetry_ingress(resolved_raw_evidence)
      end)

    runtime_us = elapsed_us(runtime_started_at)

    case runtime_result do
      {:ok, processing_result} ->
        finalize_persisted_ingress(
          resolved_raw_evidence,
          processing_result,
          ingress_started_at,
          resolve_us,
          runtime_us
        )

      {:error, reason} ->
        TelemetryProfiler.record_ingress_result(
          resolved_raw_evidence,
          resolve_us: resolve_us,
          runtime_us: runtime_us,
          end_to_end_us: elapsed_us(ingress_started_at),
          error?: true
        )

        {:error, reason}
    end
  end

  defp finalize_persisted_ingress(
         resolved_raw_evidence,
         processing_result,
         ingress_started_at,
         resolve_us,
         runtime_us
       ) do
    persistence_started_at = System.monotonic_time()

    persistence_result =
      TelemetryProfiler.with_stage(:persistence, fn ->
        Persistence.persist_processing_result(processing_result)
      end)

    persistence_us = elapsed_us(persistence_started_at)
    end_to_end_us = elapsed_us(ingress_started_at)

    TelemetryProfiler.record_ingress_result(
      resolved_raw_evidence,
      resolve_us: resolve_us,
      runtime_us: runtime_us,
      persistence_us: persistence_us,
      end_to_end_us: end_to_end_us,
      error?: match?({:error, _reason}, persistence_result),
      processing_result: processing_result
    )

    persistence_result
  end

  defp elapsed_us(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family} = raw_evidence)
       when protocol_family in [:space_packet, :packet, :space_packet_stream] do
    with {:ok, %PacketRecord{} = packet_record} <- SpacePacketDecoder.decode(raw_evidence) do
      {:ok,
       %{
         packet_records: [packet_record],
         transfer_frame_records: [],
         protocol_anomalies: []
       }}
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family} = raw_evidence)
       when protocol_family in [:tm, :tm_transfer_frame] do
    with {:ok, pipeline_state} <- TMFrameIngress.init(),
         {:ok, tm_result, <<>>, _pipeline_state, _continuity_state} <-
           TMFrameIngress.process(raw_evidence, pipeline_state, %{}, <<>>) do
      {:ok, tm_result}
    else
      {:ok, _tm_result, rest, _pipeline_state, _continuity_state} ->
        {:error, {:incomplete_tm_frame_bytes, byte_size(rest)}}
    end
  end

  defp decode_raw_evidence_packets(%RawEvidence{protocol_family: protocol_family}) do
    {:error, {:unsupported_ingress_protocol_family, protocol_family}}
  end

  defp execute_dispatches(
         %{
           packet_records: packet_records,
           transfer_frame_records: transfer_frame_records,
           protocol_anomalies: protocol_anomalies
         },
         %BindingSet{} = binding_set
       ) do
    with {:ok, dispatch_results} <- execute_dispatches(packet_records, binding_set) do
      {:ok,
       %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies,
         dispatch_results: dispatch_results
       }}
    end
  end

  defp execute_dispatches(packet_records, binding_set) do
    Enum.reduce_while(packet_records, {:ok, []}, fn packet_record, {:ok, acc} ->
      with {:ok, %DispatchDecision{} = dispatch_decision} <-
             Dispatcher.dispatch(packet_record, binding_set),
           {:ok, outputs} <- Dispatcher.execute(packet_record, dispatch_decision) do
        result = %{
          packet_record: packet_record,
          dispatch_decision: dispatch_decision,
          outputs: outputs
        }

        {:cont, {:ok, [result | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end)
  end

  defp build_processing_result(raw_evidence, decoded) do
    dispatch_decisions = Enum.map(decoded.dispatch_results, & &1.dispatch_decision)
    outputs = Enum.flat_map(decoded.dispatch_results, & &1.outputs)

    %{
      raw_evidence: raw_evidence,
      packet_records: decoded.packet_records,
      transfer_frame_records: decoded.transfer_frame_records,
      protocol_anomalies: decoded.protocol_anomalies,
      dispatch_decisions: dispatch_decisions,
      outputs: outputs,
      runtime_records: %{capability_records: [], action_requests: [], timer_events: []}
    }
  end

  defp validate_binding_set_mission(
         %RawEvidence{mission_id: mission_id},
         %BindingSet{mission_id: mission_id}
       ),
       do: :ok

  defp validate_binding_set_mission(raw_evidence, binding_set) do
    {:error, {:binding_set_mission_mismatch, raw_evidence.mission_id, binding_set.mission_id}}
  end
end
