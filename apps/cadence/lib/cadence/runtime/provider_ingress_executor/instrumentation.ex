defmodule Cadence.Runtime.ProviderIngressExecutor.Instrumentation do
  @moduledoc false

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Observability
  alias Cadence.Observability.AsyncContext

  @event_prefix [:cadence, :runtime, :provider_ingress_executor]

  def trace_enqueue([%RawEvidence{} = first_evidence | _rest] = raw_evidences, fun)
      when is_function(fun, 1) do
    attributes =
      first_evidence
      |> ingress_attributes()
      |> Map.put("cadence.ingress.item.count", length(raw_evidences))

    Observability.with_span(
      "cadence.telemetry.ingress.enqueue",
      %{kind: :producer, attributes: attributes},
      fn ->
        result = fun.(AsyncContext.capture())
        _ = record_enqueue_event(result, length(raw_evidences))
        _ = mark_trace_result(result, "telemetry ingress enqueue failed")
        result
      end
    )
  end

  def trace_stage(name, fun) when is_binary(name) and is_function(fun, 0) do
    Observability.with_span(name, %{}, fn ->
      result = fun.()
      _ = mark_trace_result(result, "#{name} failed")
      result
    end)
  end

  def maybe_record_anomaly_event(%{"cadence.telemetry.anomaly.count" => count})
      when is_integer(count) and count > 0 do
    Observability.add_event("cadence.telemetry.ingress.anomalies_detected", %{
      "cadence.telemetry.anomaly.count" => count
    })
  end

  def maybe_record_anomaly_event(_attributes), do: :ok

  def log_projector_exit(provider_binding_id, reason) do
    Logger.warning(
      "Provider ingress persistence projector exited for #{provider_binding_id}: #{inspect(reason)}"
    )
  end

  def log_processing_failure(provider_binding_id, kind, reason) do
    Logger.warning(
      "Provider ingress executor failed for #{provider_binding_id} (#{kind}): #{reason}"
    )
  end

  def record_processing_failure(%RawEvidence{} = raw_evidence, reason, outcome) do
    error_class = Observability.error_class(reason)

    _ =
      Observability.add_event("cadence.telemetry.ingress.failed", %{
        "cadence.error.class" => error_class,
        "cadence.failure.outcome" => outcome
      })

    Observability.log(
      :warning,
      "cadence.telemetry.ingress.failed",
      "Telemetry ingress processing failed",
      [error_class: error_class] ++ ingress_log_metadata(raw_evidence)
    )
  end

  def ingress_attributes(%RawEvidence{} = raw_evidence) do
    %{
      "cadence.ingress.evidence.id" => raw_evidence.evidence_id,
      "cadence.ingress.raw.size" => byte_size(raw_evidence.raw || <<>>),
      "cadence.mission.id" => raw_evidence.mission_id,
      "cadence.spacecraft.id" => raw_evidence.spacecraft_id,
      "cadence.source_endpoint.id" => raw_evidence.source_endpoint_ref,
      "cadence.telemetry.direction" => to_string(raw_evidence.direction),
      "cadence.telemetry.protocol_family" => to_string(raw_evidence.protocol_family)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  def executor_attributes(state) do
    %{
      "cadence.contact.id" => state.realized_contact_id,
      "cadence.path.id" => state.path_id,
      "cadence.provider.binding.id" => state.provider_binding_id
    }
  end

  def processing_result_attributes(processing_result) when is_map(processing_result) do
    %{
      "cadence.telemetry.anomaly.count" =>
        processing_result |> Map.get(:protocol_anomalies, []) |> length(),
      "cadence.telemetry.dispatch.count" =>
        processing_result |> Map.get(:dispatch_decisions, []) |> length(),
      "cadence.telemetry.output.count" => processing_result |> Map.get(:outputs, []) |> length(),
      "cadence.telemetry.packet.count" =>
        processing_result |> Map.get(:packet_records, []) |> length(),
      "cadence.telemetry.transfer_frame.count" =>
        processing_result |> Map.get(:transfer_frame_records, []) |> length()
    }
  end

  def emit(event, state, measurements, metadata) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      Map.merge(
        %{
          mission_id: state.mission_id,
          realized_contact_id: state.realized_contact_id,
          path_id: state.path_id,
          provider_binding_id: state.provider_binding_id
        },
        metadata
      )
    )
  end

  def run_ingress(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    exception ->
      stacktrace = __STACKTRACE__

      Logger.error(Exception.format(:error, exception, stacktrace))

      {:crash, Exception.format_banner(:error, exception)}
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__

      Logger.error(Exception.format(kind, reason, stacktrace))

      {:crash, Exception.format_banner(kind, reason)}
  end

  defp mark_trace_result(:ok, _error_message), do: Observability.mark_ok()
  defp mark_trace_result({:ok, _value}, _error_message), do: Observability.mark_ok()

  defp mark_trace_result({:error, _reason}, error_message),
    do: Observability.mark_error(error_message)

  defp mark_trace_result(_other, _error_message), do: Observability.mark_ok()

  defp record_enqueue_event(:ok, item_count) do
    Observability.add_event("cadence.telemetry.ingress.accepted", %{
      "cadence.ingress.item.count" => item_count
    })
  end

  defp record_enqueue_event({:error, reason}, item_count) do
    error_class = Observability.error_class(reason)

    _ =
      Observability.add_event("cadence.telemetry.ingress.rejected", %{
        "cadence.error.class" => error_class,
        "cadence.ingress.item.count" => item_count
      })

    Observability.log(
      :warning,
      "cadence.telemetry.ingress.rejected",
      "Telemetry ingress enqueue was rejected",
      error_class: error_class
    )
  end

  defp record_enqueue_event(_result, _item_count), do: :ok

  defp ingress_log_metadata(%RawEvidence{} = raw_evidence) do
    [
      mission_id: raw_evidence.mission_id,
      spacecraft_id: raw_evidence.spacecraft_id,
      source_endpoint_id: raw_evidence.source_endpoint_ref
    ]
  end
end
