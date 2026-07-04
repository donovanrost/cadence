defmodule Cadence.Support.DashboardSourceContractAdapter do
  @moduledoc false

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    SourceCapabilities,
    SourceFacts,
    SourceProbe,
    SourceResult,
    SourceWatermark
  }

  def capabilities do
    SourceCapabilities.new(%{
      logical_source: :telemetry,
      supported_sampling: [
        :latest,
        :latest_state,
        :raw_series,
        :bounded_history,
        :bounded_raw_series,
        :decimated_envelope,
        :event_history,
        :analysis_buckets,
        :definition_intervals,
        :constellation_health
      ],
      supported_products: [
        :latest_value,
        :latest_state,
        :bounded_receipt_time_history,
        :event_history,
        :analysis_buckets,
        :definition_intervals,
        :contact_intervals,
        :mission_timeline,
        :source_health_transitions,
        :source_watermark_events,
        :source_capability_postures,
        :telemetry_backfill_lifecycle,
        :telemetry_revision_decisions,
        :contacts_phase,
        :connection_state,
        :link_rf_lock_state,
        :link_rf_frame_sync_state,
        :link_rf_metric,
        :link_rf_metric_history,
        :transport_bitrate,
        :transport_bitrate_history,
        :operational_metric_history,
        :command_queue_depth,
        :ingress_processing_latency
      ],
      supported_time_axes: [:generation_time, :receipt_time, :occurred_at],
      supported_value_types: [:raw, :engineering],
      supported_shapes: [:scalar, :wide, :events, :intervals, :matrix],
      supports_watermarks?: true,
      completeness: :known
    })
  end

  def probe(_data_source, _opts), do: SourceProbe.healthy(:source_probe_succeeded, %{})

  def facts(%PlannedSourceRequest{} = request, opts) do
    source_binding = Keyword.fetch!(opts, :source_binding)

    {:ok,
     SourceFacts.new(%{
       source_binding: source_binding.binding,
       data_source: source_binding.data_source,
       watermark: source_watermark(request, source_binding, opts),
       data_revision: data_revision(request, opts),
       source_health: Keyword.get(opts, :source_health, :healthy)
     })}
  end

  def resolve(%PlannedSourceRequest{} = request, opts) do
    notify(opts, {:dashboard_source_contract_adapter_resolve, request.logical_source})

    case Keyword.get(opts, :mode, :empty_result) do
      :raise ->
        raise "contract adapter failure for #{request.logical_source}"

      :exit ->
        exit(:contract_adapter_exit)

      :sleep ->
        Process.sleep(Keyword.get(opts, :sleep_ms, 100))

        empty_result(request, opts)

      :empty_result ->
        empty_result(request, opts)
    end
  end

  defp empty_result(%PlannedSourceRequest{} = request, opts) do
    source_binding = Keyword.fetch!(opts, :source_binding)

    SourceResult.new(%{
      request_id: request.request_id,
      watermarks: List.wrap(source_watermark(request, source_binding, opts)),
      meta: %{
        logical_source: request.logical_source,
        returned_frame_count: 0,
        degraded?: false
      }
    })
  end

  defp source_watermark(
         %PlannedSourceRequest{logical_source: logical_source},
         _source_binding,
         _opts
       )
       when logical_source not in [:telemetry, :limits],
       do: nil

  defp source_watermark(%PlannedSourceRequest{} = request, source_binding, opts) do
    case Keyword.get(opts, :watermark_complete_through) do
      %DateTime{} = complete_through ->
        SourceWatermark.new(%{
          request_id: request.request_id,
          logical_source: request.logical_source,
          source_binding_id: source_binding.binding.binding_id,
          data_source_id: source_binding.data_source.data_source_id,
          realm: source_binding.realm,
          dataset: source_binding.dataset,
          complete_through: complete_through,
          latest_receipt_time:
            Keyword.get(opts, :watermark_latest_receipt_time, complete_through),
          sample_count: Keyword.get(opts, :watermark_sample_count, 1),
          confidence: :best_effort
        })

      _other ->
        nil
    end
  end

  defp data_revision(%PlannedSourceRequest{logical_source: logical_source}, opts)
       when logical_source in [:events, :operational_observables] do
    Keyword.get(opts, :data_revision)
  end

  defp data_revision(%PlannedSourceRequest{}, _opts), do: nil

  defp notify(opts, message) do
    case Keyword.get(opts, :test_pid) do
      pid when is_pid(pid) -> send(pid, message)
      _other -> :ok
    end
  end
end
