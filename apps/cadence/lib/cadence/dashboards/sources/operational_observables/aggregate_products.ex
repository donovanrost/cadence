defmodule Cadence.Dashboards.Sources.OperationalObservables.AggregateProducts do
  @moduledoc """
  Composes source-family frames for aggregate operational products.

  Each family retains ownership of its reads and presentation. This module owns
  only observable selection and the stable ordering of the aggregate frames.
  """

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest}

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    AntennaPointing,
    CommandQueueDepth,
    Connection,
    ContactPhase,
    IngressProcessingLatency,
    LinkRf,
    RuntimeActivity,
    TransportBitrate,
    TransportExecutionState
  }

  @connection_observable_ids [
    "comms.transport.connection_state",
    "ground.station.connection_state"
  ]
  @antenna_pointing_observable_ids ["ground.station.antenna_pointing_state"]
  @link_rf_lock_observable_ids ["link.rf_lock_state"]
  @link_rf_frame_sync_observable_ids ["link.frame_sync_state"]
  @link_rf_metric_observable_ids [
    "link.snr_db",
    "link.eb_n0_db",
    "link.symbol_rate_sps",
    "link.doppler_hz"
  ]
  @bitrate_observable_ids [
    "comms.transport.downlink_bitrate",
    "comms.transport.uplink_bitrate"
  ]
  @transport_execution_observable_ids ["comms.transport.execution_state"]
  @ingress_latency_observable_ids ["ingress.processing_latency_ms"]
  @managed_runtime_observable_ids ["runtime.managed_activity"]
  @transport_runtime_observable_ids ["runtime.transport_activity"]

  @type product ::
          :operational_latest | :operational_metric_history | :operational_state_history

  @spec resolve(
          product(),
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: [Frame.t()]
  def resolve(
        product,
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    context = %{
      request: request,
      organization_id: organization_id,
      mission_id: mission_id,
      source_context: source_context,
      adapter_opts: adapter_opts,
      opts: opts
    }

    resolve_product(product, context)
  end

  defp resolve_product(:operational_state_history, context) do
    []
    |> maybe_add_frame(context, ["contacts.phase"], &ContactPhase.resolve_history/6)
    |> maybe_add_frame(
      context,
      @connection_observable_ids,
      &Connection.resolve_history/6
    )
    |> maybe_add_frame(
      context,
      @antenna_pointing_observable_ids,
      &AntennaPointing.resolve_history/6
    )
    |> maybe_add_frame(context, @link_rf_lock_observable_ids, &LinkRf.resolve_lock_history/6)
    |> maybe_add_frame(
      context,
      @link_rf_frame_sync_observable_ids,
      &LinkRf.resolve_frame_sync_history/6
    )
    |> maybe_add_frame(
      context,
      @transport_execution_observable_ids,
      &TransportExecutionState.resolve/6
    )
    |> maybe_add_frame(
      context,
      @managed_runtime_observable_ids,
      &RuntimeActivity.resolve_managed/6
    )
    |> maybe_add_frame(
      context,
      @transport_runtime_observable_ids,
      &RuntimeActivity.resolve_transport/6
    )
  end

  defp resolve_product(:operational_latest, context) do
    []
    |> maybe_add_frame(context, ["contacts.phase"], &ContactPhase.resolve_latest/6)
    |> maybe_add_frame(
      context,
      @connection_observable_ids,
      &Connection.resolve_latest/6
    )
    |> maybe_add_frame(
      context,
      @antenna_pointing_observable_ids,
      &AntennaPointing.resolve_latest/6
    )
    |> maybe_add_frame(context, @link_rf_lock_observable_ids, &LinkRf.resolve_lock_latest/6)
    |> maybe_add_frame(
      context,
      @link_rf_frame_sync_observable_ids,
      &LinkRf.resolve_frame_sync_latest/6
    )
    |> maybe_add_frame(context, @link_rf_metric_observable_ids, &LinkRf.resolve_metric_latest/6)
    |> maybe_add_frame(
      context,
      @bitrate_observable_ids,
      &TransportBitrate.resolve_latest/6
    )
    |> maybe_add_frame(context, ["commanding.queue_depth"], &CommandQueueDepth.resolve/6)
    |> maybe_add_frame(
      context,
      @ingress_latency_observable_ids,
      &IngressProcessingLatency.resolve_latest/6
    )
  end

  defp resolve_product(:operational_metric_history, context) do
    []
    |> maybe_add_frames(
      context,
      @link_rf_metric_observable_ids,
      &LinkRf.resolve_metric_history/6
    )
    |> maybe_add_frames(
      context,
      @bitrate_observable_ids,
      &TransportBitrate.resolve_history/6
    )
    |> maybe_add_frames(
      context,
      @ingress_latency_observable_ids,
      &IngressProcessingLatency.resolve_history/6
    )
  end

  defp maybe_add_frame(frames, context, observable_ids, resolver) do
    if requested?(context.request, observable_ids) do
      frames ++ [resolve_family(context, resolver)]
    else
      frames
    end
  end

  defp maybe_add_frames(frames, context, observable_ids, resolver) do
    if requested?(context.request, observable_ids) do
      frames ++ resolve_family(context, resolver)
    else
      frames
    end
  end

  defp resolve_family(context, resolver) do
    resolver.(
      context.request,
      context.organization_id,
      context.mission_id,
      context.source_context,
      context.adapter_opts,
      context.opts
    )
  end

  defp requested?(%PlannedSourceRequest{} = request, observable_ids) do
    Enum.any?(request.observables, &(&1 in observable_ids))
  end
end
