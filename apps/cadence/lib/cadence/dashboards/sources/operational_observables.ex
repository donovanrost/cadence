defmodule Cadence.Dashboards.Sources.OperationalObservables do
  @moduledoc """
  Dashboard adapter for operational rollups that are already projected inside
  Cadence.

  v0 exposes constellation health as a spacecraft-by-worst-limit-state matrix.
  """

  alias Cadence.Dashboards.{
    DataContext,
    Frame,
    OperationalObservable,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    SourceCapabilities,
    SourceFacts,
    SourceResult
  }

  alias Cadence.Comms.TransportStore
  alias Cadence.SourceEndpoints
  alias Cadence.Telemetry.RuntimeHealth

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    AntennaPointingFrames,
    AntennaPointingRows,
    CommandQueueDepth,
    ConnectionFrames,
    ConnectionRows,
    ConstellationHealth,
    ContactPhase,
    IngressProcessingLatencyRows,
    LatestFreshness,
    LinkRfMetricRows,
    LinkRfStateFrames,
    LinkRfStateRows,
    OperationalEventSnapshots,
    OperationalMetricFrames,
    ProductPolicy,
    RevisionPolicy,
    RuntimeActivity,
    TransportBitrateRows,
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
  @connection_states [:connected, :connecting, :degraded, :disconnected, :unknown]
  @type connection_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @type transport_metric_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @type runtime_metric_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @spec backed_observable_ids() :: [binary()]
  defdelegate backed_observable_ids(), to: ProductPolicy

  @spec backed_observable?(term()) :: boolean()
  defdelegate backed_observable?(observable_id), to: ProductPolicy

  @spec source_backing_contracts() :: [map()]
  defdelegate source_backing_contracts(), to: ProductPolicy

  @spec capabilities() :: SourceCapabilities.t()
  def capabilities do
    registry_metadata =
      OperationalObservable.metadata()
      |> Map.put(:source_backed_observable_ids, backed_observable_ids())
      |> Map.put(:metric_history_contracts, ProductPolicy.metric_history_contracts())
      |> Map.put(:source_backing_contracts, source_backing_contracts())

    SourceCapabilities.new(%{
      logical_source: :operational_observables,
      supported_sampling: [:constellation_health, :latest, :event_history, :raw_series],
      supported_products: [
        :constellation_health,
        :contacts_phase,
        :contacts_phase_history,
        :connection_state,
        :connection_state_history,
        :ground_station_antenna_pointing_state,
        :ground_station_antenna_pointing_state_history,
        :link_rf_lock_state,
        :link_rf_lock_state_history,
        :link_rf_frame_sync_state,
        :link_rf_frame_sync_state_history,
        :link_rf_metric,
        :link_rf_metric_history,
        :transport_bitrate,
        :transport_bitrate_history,
        :transport_execution_state_history,
        :managed_runtime_activity_history,
        :transport_runtime_activity_history,
        :ingress_processing_latency_history,
        :operational_metric_history,
        :operational_latest,
        :operational_state_history,
        :command_queue_depth,
        :ingress_processing_latency
      ],
      supported_time_axes: [:occurred_at],
      supported_value_types: [:raw, :engineering],
      supported_shapes: [:matrix, :events, :wide],
      supports_watermarks?: false,
      completeness: :known,
      metadata: registry_metadata
    })
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with {:ok, product} <- ProductPolicy.validate(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id) do
      {:ok,
       SourceFacts.new(%{
         source_binding: source_binding && source_binding.binding,
         data_source: source_binding && source_binding.data_source,
         data_revision:
           Keyword.get(opts, :data_revision) ||
             RevisionPolicy.data_revision(
               product,
               request.observables,
               organization_id,
               mission_id,
               adapter_opts(request, source_binding),
               opts,
               revision_defaults()
             ),
         correction_cursor: Keyword.get(opts, :correction_cursor),
         backfill_cursor: Keyword.get(opts, :backfill_cursor),
         source_health: Keyword.get(opts, :source_health, :healthy),
         meta: %{
           logical_source: :operational_observables,
           source_binding_id: source_binding_id(source_binding),
           data_source_id: data_source_id(request, source_binding)
         }
       })}
    else
      {:warning, warning} -> {:error, warning}
    end
  end

  defp revision_defaults do
    [
      contacts_phase: &ContactPhase.default_revision/3,
      connection_state: &default_connection_state_revision/3,
      ground_station_antenna_pointing_state: &default_antenna_pointing_state_revision/3,
      link_rf_lock_state: &default_link_rf_lock_state_revision/3,
      link_rf_frame_sync_state: &default_link_rf_frame_sync_state_revision/3,
      link_rf_metric: &default_link_rf_metric_revision/3,
      transport_bitrate: &default_transport_bitrate_revision/3,
      transport_execution_state: &TransportExecutionState.default_revision/3,
      managed_runtime_activity: &RuntimeActivity.default_managed_revision/3,
      transport_runtime_activity: &RuntimeActivity.default_transport_revision/3,
      ingress_processing_latency: &default_ingress_processing_latency_revision/3,
      command_queue_depth: &CommandQueueDepth.default_revision/3
    ]
  end

  @spec resolve(PlannedSourceRequest.t(), keyword()) :: SourceResult.t()
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with {:ok, product} <- ProductPolicy.validate(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id) do
      resolve_supported_product(
        request,
        source_binding,
        product,
        organization_id,
        mission_id,
        opts
      )
    else
      {:warning, warning} ->
        SourceResult.new(%{
          request_id: request.request_id,
          warnings: [warning],
          meta: %{
            logical_source: request.logical_source,
            source_binding_id: source_binding_id(source_binding),
            data_source_id: data_source_id(request, source_binding),
            supported_capability: nil,
            returned_frame_count: 0,
            degraded?: true
          }
        })
    end
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :constellation_health,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      ConstellationHealth.resolve(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :constellation_health, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :contacts_phase,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      ContactPhase.resolve_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :contacts_phase, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :contacts_phase_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      ContactPhase.resolve_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :contacts_phase_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :connection_state,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      connection_state_frame(
        request,
        source_binding,
        connection_latest_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :connection_state, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :connection_state_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      connection_state_history_frame(
        request,
        source_binding,
        connection_history_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :connection_state_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :ground_station_antenna_pointing_state,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      antenna_pointing_state_frame(
        request,
        source_binding,
        antenna_pointing_latest_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :ground_station_antenna_pointing_state, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :ground_station_antenna_pointing_state_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      antenna_pointing_state_history_frame(
        request,
        source_binding,
        antenna_pointing_history_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(
      request,
      source_binding,
      :ground_station_antenna_pointing_state_history,
      [frame]
    )
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :link_rf_lock_state,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      link_rf_lock_state_frame(
        request,
        source_binding,
        link_rf_lock_latest_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :link_rf_lock_state, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :link_rf_lock_state_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      link_rf_lock_state_history_frame(
        request,
        source_binding,
        link_rf_lock_history_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :link_rf_lock_state_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :link_rf_frame_sync_state,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      link_rf_frame_sync_state_frame(
        request,
        source_binding,
        link_rf_frame_sync_latest_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :link_rf_frame_sync_state, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :link_rf_frame_sync_state_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      link_rf_frame_sync_state_history_frame(
        request,
        source_binding,
        link_rf_frame_sync_history_rows(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )
      )

    source_result(request, source_binding, :link_rf_frame_sync_state_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :transport_execution_state_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      TransportExecutionState.resolve(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :transport_execution_state_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :managed_runtime_activity_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      RuntimeActivity.resolve_managed(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :managed_runtime_activity_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :transport_runtime_activity_history,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      RuntimeActivity.resolve_transport(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :transport_runtime_activity_history, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :link_rf_metric,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      link_rf_metric_frame(
        request,
        source_binding,
        link_rf_metric_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :link_rf_metric, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :link_rf_metric_history,
         organization_id,
         mission_id,
         opts
       ) do
    frames =
      request
      |> link_rf_metric_history_rows(source_binding, organization_id, mission_id, opts)
      |> operational_metric_history_frames(request, source_binding, :link_rf_metric_history)

    source_result(request, source_binding, :link_rf_metric_history, frames)
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :operational_state_history,
         organization_id,
         mission_id,
         opts
       ) do
    frames =
      []
      |> maybe_add_contact_phase_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_connection_state_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_antenna_pointing_state_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_link_rf_lock_state_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_link_rf_frame_sync_state_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_transport_execution_state_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_managed_runtime_activity_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_transport_runtime_activity_history_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )

    source_result(request, source_binding, :operational_state_history, frames)
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :operational_latest,
         organization_id,
         mission_id,
         opts
       ) do
    frames =
      []
      |> maybe_add_contact_phase_frame(request, source_binding, organization_id, mission_id, opts)
      |> maybe_add_connection_state_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_antenna_pointing_state_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_link_rf_lock_state_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_link_rf_frame_sync_state_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_link_rf_metric_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_transport_bitrate_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_command_queue_depth_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_ingress_processing_latency_frame(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )

    source_result(request, source_binding, :operational_latest, frames)
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :operational_metric_history,
         organization_id,
         mission_id,
         opts
       ) do
    frames =
      []
      |> maybe_add_link_rf_metric_history_frames(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_transport_bitrate_history_frames(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> maybe_add_ingress_processing_latency_history_frames(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )

    source_result(request, source_binding, :operational_metric_history, frames)
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :transport_bitrate,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      transport_bitrate_frame(
        request,
        source_binding,
        transport_bitrate_rows(request, source_binding, organization_id, mission_id, opts)
      )

    source_result(request, source_binding, :transport_bitrate, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :transport_bitrate_history,
         organization_id,
         mission_id,
         opts
       ) do
    frames =
      request
      |> transport_bitrate_history_rows(source_binding, organization_id, mission_id, opts)
      |> operational_metric_history_frames(request, source_binding, :transport_bitrate_history)

    source_result(request, source_binding, :transport_bitrate_history, frames)
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :command_queue_depth,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      CommandQueueDepth.resolve(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

    source_result(request, source_binding, :command_queue_depth, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :ingress_processing_latency,
         organization_id,
         mission_id,
         opts
       ) do
    frame =
      ingress_processing_latency_frame(
        request,
        source_binding,
        ingress_processing_latency_rows(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )
      )

    source_result(request, source_binding, :ingress_processing_latency, [frame])
  end

  defp resolve_supported_product(
         request,
         source_binding,
         :ingress_processing_latency_history,
         organization_id,
         mission_id,
         opts
       ) do
    frames =
      request
      |> ingress_processing_latency_history_rows(
        source_binding,
        organization_id,
        mission_id,
        opts
      )
      |> operational_metric_history_frames(
        request,
        source_binding,
        :ingress_processing_latency_history
      )

    source_result(request, source_binding, :ingress_processing_latency_history, frames)
  end

  defp source_result(%PlannedSourceRequest{} = request, source_binding, capability, frames) do
    warnings = frame_warnings(request, source_binding, capability, frames)

    SourceResult.new(%{
      request_id: request.request_id,
      frames: frames,
      warnings: warnings,
      watermarks: [],
      meta: %{
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        data_source_id: data_source_id(request, source_binding),
        supported_capability: capability,
        returned_frame_count: length(frames),
        degraded?: warnings != []
      }
    })
  end

  defp frame_warnings(request, source_binding, capability, frames) do
    frames
    |> frame_warning_codes()
    |> Enum.map(fn code ->
      warning(
        request,
        code,
        frame_warning_severity(code),
        frame_warning_message(code),
        %{
          logical_source: :operational_observables,
          source_binding_id: source_binding_id(source_binding),
          data_source_id: data_source_id(request, source_binding),
          supported_capability: capability,
          frame_ids: frame_ids_for_warning_code(frames, code),
          observable_ids: observable_ids_for_warning_code(frames, code)
        }
      )
    end)
  end

  defp frame_warning_codes(frames) do
    frames
    |> Enum.flat_map(&warning_codes/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp warning_codes(%Frame{meta: meta}) when is_map(meta) do
    case attr(meta, :warning_codes) do
      codes when is_list(codes) -> codes
      code when is_atom(code) -> [code]
      _other -> []
    end
  end

  defp warning_codes(_frame), do: []

  defp frame_warning_severity(:watermark_unknown), do: :info
  defp frame_warning_severity(:stale_data), do: :warning
  defp frame_warning_severity(:missing_snapshot), do: :warning
  defp frame_warning_severity(_code), do: :warning

  defp frame_warning_message(:watermark_unknown),
    do: "Operational observable freshness is unknown"

  defp frame_warning_message(:missing_snapshot), do: "Operational observable snapshot is missing"
  defp frame_warning_message(:stale_data), do: "Operational observable data is stale"
  defp frame_warning_message(_code), do: "Operational observable frame is degraded"

  defp frame_ids_for_warning_code(frames, code) do
    frames
    |> Enum.filter(&(code in warning_codes(&1)))
    |> Enum.map(& &1.frame_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp observable_ids_for_warning_code(frames, code) do
    frames
    |> Enum.filter(&(code in warning_codes(&1)))
    |> Enum.flat_map(&frame_observable_ids/1)
    |> Enum.uniq()
  end

  defp frame_observable_ids(%Frame{meta: meta}) when is_map(meta) do
    cond do
      is_binary(attr(meta, :observable_id)) ->
        [attr(meta, :observable_id)]

      is_list(attr(meta, :observable_ids)) ->
        attr(meta, :observable_ids)

      true ->
        []
    end
  end

  defp frame_observable_ids(_frame), do: []

  defp maybe_add_contact_phase_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if "contacts.phase" in request.observables do
      frame =
        ContactPhase.resolve_latest(
          request,
          organization_id,
          mission_id,
          frame_source_context(request, source_binding),
          adapter_opts(request, source_binding),
          opts
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_connection_state_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @connection_observable_ids)) do
      frame =
        connection_state_frame(
          request,
          source_binding,
          connection_latest_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_antenna_pointing_state_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @antenna_pointing_observable_ids)) do
      frame =
        antenna_pointing_state_frame(
          request,
          source_binding,
          antenna_pointing_latest_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_transport_bitrate_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @bitrate_observable_ids)) do
      frame =
        transport_bitrate_frame(
          request,
          source_binding,
          transport_bitrate_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_transport_bitrate_history_frames(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @bitrate_observable_ids)) do
      history_frames =
        request
        |> transport_bitrate_history_rows(source_binding, organization_id, mission_id, opts)
        |> operational_metric_history_frames(request, source_binding, :transport_bitrate_history)

      frames ++ history_frames
    else
      frames
    end
  end

  defp maybe_add_ingress_processing_latency_history_frames(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @ingress_latency_observable_ids)) do
      history_frames =
        request
        |> ingress_processing_latency_history_rows(
          source_binding,
          organization_id,
          mission_id,
          opts
        )
        |> operational_metric_history_frames(
          request,
          source_binding,
          :ingress_processing_latency_history
        )

      frames ++ history_frames
    else
      frames
    end
  end

  defp maybe_add_link_rf_lock_state_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @link_rf_lock_observable_ids)) do
      frame =
        link_rf_lock_state_frame(
          request,
          source_binding,
          link_rf_lock_latest_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_antenna_pointing_state_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @antenna_pointing_observable_ids)) do
      frame =
        antenna_pointing_state_history_frame(
          request,
          source_binding,
          antenna_pointing_history_rows(
            request,
            source_binding,
            organization_id,
            mission_id,
            opts
          )
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_link_rf_metric_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @link_rf_metric_observable_ids)) do
      frame =
        link_rf_metric_frame(
          request,
          source_binding,
          link_rf_metric_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_link_rf_metric_history_frames(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @link_rf_metric_observable_ids)) do
      history_frames =
        request
        |> link_rf_metric_history_rows(source_binding, organization_id, mission_id, opts)
        |> operational_metric_history_frames(request, source_binding, :link_rf_metric_history)

      frames ++ history_frames
    else
      frames
    end
  end

  defp maybe_add_link_rf_frame_sync_state_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @link_rf_frame_sync_observable_ids)) do
      frame =
        link_rf_frame_sync_state_frame(
          request,
          source_binding,
          link_rf_frame_sync_latest_rows(
            request,
            source_binding,
            organization_id,
            mission_id,
            opts
          )
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_transport_execution_state_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @transport_execution_observable_ids)) do
      frame =
        TransportExecutionState.resolve(
          request,
          organization_id,
          mission_id,
          frame_source_context(request, source_binding),
          adapter_opts(request, source_binding),
          opts
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_managed_runtime_activity_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @managed_runtime_observable_ids)) do
      frame =
        RuntimeActivity.resolve_managed(
          request,
          organization_id,
          mission_id,
          frame_source_context(request, source_binding),
          adapter_opts(request, source_binding),
          opts
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_transport_runtime_activity_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @transport_runtime_observable_ids)) do
      frame =
        RuntimeActivity.resolve_transport(
          request,
          organization_id,
          mission_id,
          frame_source_context(request, source_binding),
          adapter_opts(request, source_binding),
          opts
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_command_queue_depth_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if "commanding.queue_depth" in request.observables do
      frame =
        CommandQueueDepth.resolve(
          request,
          organization_id,
          mission_id,
          frame_source_context(request, source_binding),
          adapter_opts(request, source_binding),
          opts
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_ingress_processing_latency_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if "ingress.processing_latency_ms" in request.observables do
      frame =
        ingress_processing_latency_frame(
          request,
          source_binding,
          ingress_processing_latency_rows(
            request,
            source_binding,
            organization_id,
            mission_id,
            opts
          )
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp connection_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    connection_snapshots_fun =
      Keyword.get(opts, :connection_snapshots_fun, &OperationalEventSnapshots.connection/3)

    adapter_opts = adapter_opts(request, source_binding)

    ConnectionRows.latest(
      request.observables,
      transports_fun.(organization_id, mission_id, adapter_opts),
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      connection_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> LatestFreshness.annotate(request, opts)
  end

  defp antenna_pointing_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    antenna_pointing_snapshots_fun =
      Keyword.get(
        opts,
        :antenna_pointing_snapshots_fun,
        &OperationalEventSnapshots.antenna_pointing/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    AntennaPointingRows.latest(
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      antenna_pointing_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> LatestFreshness.annotate(request, opts)
  end

  defp link_rf_lock_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_lock_snapshots_fun =
      Keyword.get(opts, :link_rf_lock_snapshots_fun, &OperationalEventSnapshots.link_rf_lock/3)

    adapter_opts = adapter_opts(request, source_binding)

    LinkRfStateRows.lock_latest(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_lock_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> LatestFreshness.annotate(request, opts)
  end

  defp link_rf_metric_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_metric_snapshots_fun =
      Keyword.get(
        opts,
        :link_rf_metric_snapshots_fun,
        &OperationalEventSnapshots.link_rf_metric/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    LinkRfMetricRows.latest(
      request.observables,
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_metric_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> LatestFreshness.annotate(request, opts)
  end

  defp link_rf_metric_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_metric_snapshots_fun =
      Keyword.get(
        opts,
        :link_rf_metric_snapshots_fun,
        &OperationalEventSnapshots.link_rf_metric/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    transports = transports_fun.(organization_id, mission_id, adapter_opts)
    snapshots = link_rf_metric_snapshots_fun.(organization_id, mission_id, adapter_opts)

    LinkRfMetricRows.history(request.observables, transports, snapshots, request)
  end

  defp antenna_pointing_history_rows(request, source_binding, organization_id, mission_id, opts) do
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    antenna_pointing_snapshots_fun =
      Keyword.get(
        opts,
        :antenna_pointing_snapshots_fun,
        &OperationalEventSnapshots.antenna_pointing/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    AntennaPointingRows.history(
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      antenna_pointing_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
  end

  defp link_rf_frame_sync_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_frame_sync_snapshots_fun =
      Keyword.get(
        opts,
        :link_rf_frame_sync_snapshots_fun,
        &OperationalEventSnapshots.link_rf_frame_sync/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    LinkRfStateRows.frame_sync_latest(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_frame_sync_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> LatestFreshness.annotate(request, opts)
  end

  defp transport_bitrate_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    metric_snapshots_fun =
      Keyword.get(
        opts,
        :transport_metric_snapshots_fun,
        &OperationalEventSnapshots.transport_bitrate/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    TransportBitrateRows.latest(
      transports_fun.(organization_id, mission_id, adapter_opts),
      metric_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> LatestFreshness.annotate(request, opts)
  end

  defp transport_bitrate_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    metric_snapshots_fun =
      Keyword.get(
        opts,
        :transport_metric_snapshots_fun,
        &OperationalEventSnapshots.transport_bitrate/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    transports = transports_fun.(organization_id, mission_id, adapter_opts)
    snapshots = metric_snapshots_fun.(organization_id, mission_id, adapter_opts)

    TransportBitrateRows.history(transports, snapshots, request)
  end

  defp ingress_processing_latency_rows(request, source_binding, organization_id, mission_id, opts) do
    metric_snapshots_fun =
      Keyword.get(
        opts,
        :ingress_processing_latency_snapshots_fun,
        Keyword.get(opts, :runtime_metric_snapshots_fun)
      )

    ingress_processing_latency_snapshots(
      metric_snapshots_fun,
      organization_id,
      mission_id,
      adapter_opts(request, source_binding),
      opts
    )
    |> IngressProcessingLatencyRows.latest(request, mission_id)
    |> LatestFreshness.annotate(request, opts)
  end

  defp ingress_processing_latency_history_rows(
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    metric_snapshots_fun =
      Keyword.get(
        opts,
        :ingress_processing_latency_history_snapshots_fun,
        Keyword.get(
          opts,
          :durable_ingress_processing_latency_snapshots_fun,
          &default_durable_ingress_processing_latency_snapshots/3
        )
      )

    organization_id
    |> metric_snapshots_fun.(mission_id, adapter_opts(request, source_binding))
    |> IngressProcessingLatencyRows.history(request, mission_id)
  end

  defp maybe_add_contact_phase_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if "contacts.phase" in request.observables do
      frame =
        ContactPhase.resolve_history(
          request,
          organization_id,
          mission_id,
          frame_source_context(request, source_binding),
          adapter_opts(request, source_binding),
          opts
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_connection_state_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @connection_observable_ids)) do
      frame =
        connection_state_history_frame(
          request,
          source_binding,
          connection_history_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_link_rf_lock_state_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @link_rf_lock_observable_ids)) do
      frame =
        link_rf_lock_state_history_frame(
          request,
          source_binding,
          link_rf_lock_history_rows(request, source_binding, organization_id, mission_id, opts)
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp maybe_add_link_rf_frame_sync_state_history_frame(
         frames,
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if Enum.any?(request.observables, &(&1 in @link_rf_frame_sync_observable_ids)) do
      frame =
        link_rf_frame_sync_state_history_frame(
          request,
          source_binding,
          link_rf_frame_sync_history_rows(
            request,
            source_binding,
            organization_id,
            mission_id,
            opts
          )
        )

      frames ++ [frame]
    else
      frames
    end
  end

  defp connection_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    connection_snapshots_fun =
      Keyword.get(opts, :connection_snapshots_fun, &OperationalEventSnapshots.connection/3)

    adapter_opts = adapter_opts(request, source_binding)

    ConnectionRows.history(
      request.observables,
      transports_fun.(organization_id, mission_id, adapter_opts),
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      connection_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
  end

  defp link_rf_lock_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_lock_snapshots_fun =
      Keyword.get(opts, :link_rf_lock_snapshots_fun, &OperationalEventSnapshots.link_rf_lock/3)

    adapter_opts = adapter_opts(request, source_binding)

    LinkRfStateRows.lock_history(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_lock_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
  end

  defp link_rf_frame_sync_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_frame_sync_snapshots_fun =
      Keyword.get(
        opts,
        :link_rf_frame_sync_snapshots_fun,
        &OperationalEventSnapshots.link_rf_frame_sync/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    LinkRfStateRows.frame_sync_history(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_frame_sync_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
  end

  defp frame_source_context(%PlannedSourceRequest{} = request, source_binding) do
    %{
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request)
    }
  end

  defp connection_state_frame(request, source_binding, connection_rows) do
    ConnectionFrames.latest(
      request,
      connection_rows,
      frame_source_context(request, source_binding)
    )
  end

  defp connection_state_history_frame(request, source_binding, connection_rows) do
    ConnectionFrames.history(
      request,
      connection_rows,
      frame_source_context(request, source_binding)
    )
  end

  defp antenna_pointing_state_frame(request, source_binding, pointing_rows) do
    AntennaPointingFrames.latest(
      request,
      pointing_rows,
      frame_source_context(request, source_binding)
    )
  end

  defp antenna_pointing_state_history_frame(request, source_binding, pointing_rows) do
    AntennaPointingFrames.history(
      request,
      pointing_rows,
      frame_source_context(request, source_binding)
    )
  end

  defp link_rf_lock_state_frame(request, source_binding, rows) do
    LinkRfStateFrames.lock_latest(request, rows, frame_source_context(request, source_binding))
  end

  defp link_rf_lock_state_history_frame(request, source_binding, rows) do
    LinkRfStateFrames.lock_history(request, rows, frame_source_context(request, source_binding))
  end

  defp link_rf_frame_sync_state_frame(request, source_binding, rows) do
    LinkRfStateFrames.frame_sync_latest(
      request,
      rows,
      frame_source_context(request, source_binding)
    )
  end

  defp link_rf_frame_sync_state_history_frame(request, source_binding, rows) do
    LinkRfStateFrames.frame_sync_history(
      request,
      rows,
      frame_source_context(request, source_binding)
    )
  end

  defp link_rf_metric_frame(request, source_binding, rows) do
    OperationalMetricFrames.link_rf_latest(
      request,
      rows,
      frame_source_context(request, source_binding)
    )
  end

  defp transport_bitrate_frame(request, source_binding, rows) do
    OperationalMetricFrames.transport_bitrate_latest(
      request,
      rows,
      frame_source_context(request, source_binding)
    )
  end

  defp operational_metric_history_frames(rows, request, source_binding, capability) do
    OperationalMetricFrames.history(
      request,
      rows,
      capability,
      frame_source_context(request, source_binding)
    )
  end

  defp ingress_processing_latency_frame(request, source_binding, rows) do
    OperationalMetricFrames.ingress_latency_latest(
      request,
      rows,
      frame_source_context(request, source_binding)
    )
  end

  defp connection_state(value) do
    value
    |> attr(:connection_state)
    |> normalize_connection_state()
  end

  defp normalize_connection_state(value) when value in @connection_states, do: value

  defp normalize_connection_state(value) when is_binary(value) do
    Enum.find(@connection_states, &(Atom.to_string(&1) == value))
  end

  defp normalize_connection_state(_value), do: nil

  defp ingress_processing_latency_snapshots(
         nil,
         organization_id,
         mission_id,
         adapter_opts,
         opts
       ) do
    default_ingress_processing_latency_snapshots(
      organization_id,
      mission_id,
      Keyword.merge(
        adapter_opts,
        Keyword.take(opts, [
          :durable_ingress_processing_latency_snapshots_fun,
          :runtime_health_ingress_processing_latency_snapshots_fun
        ])
      )
    )
  end

  defp ingress_processing_latency_snapshots(
         metric_snapshots_fun,
         organization_id,
         mission_id,
         adapter_opts,
         _opts
       )
       when is_function(metric_snapshots_fun, 3) do
    metric_snapshots_fun.(organization_id, mission_id, adapter_opts)
  end

  defp link_id_for(values) when is_list(values) do
    values
    |> Enum.find_value(&link_id/1)
  end

  defp link_id(value) do
    [
      attr(value, :link_id),
      attr(value, :link_assignment_id),
      attr(value, :link_assignment_ref),
      attr(value, :materialized_link_assignment_id),
      metadata_attr(value, :link_id),
      metadata_attr(value, :link_assignment_id),
      metadata_attr(value, :link_assignment_ref),
      metadata_attr(value, :materialized_link_assignment_id)
    ]
    |> Enum.find(&present_text?/1)
  end

  defp default_transports(organization_id, mission_id, _opts) do
    TransportStore.list_transports(organization_id, mission_id)
  end

  defp default_source_endpoints(organization_id, mission_id, _opts) do
    SourceEndpoints.list_source_endpoints(organization_id, mission_id)
  end

  defp default_connection_state_revision(organization_id, mission_id, opts) do
    "connection_state:" <>
      RuntimeCacheKey.fingerprint(%{
        transports:
          organization_id
          |> default_transports(mission_id, opts)
          |> Enum.map(&transport_revision_entry/1)
          |> Enum.sort_by(&(&1.transport_id || "")),
        source_endpoints:
          organization_id
          |> default_source_endpoints(mission_id, opts)
          |> Enum.map(&source_endpoint_revision_entry/1)
          |> Enum.sort_by(&(&1.source_endpoint_id || "")),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.connection(mission_id, opts)
          |> Enum.map(&connection_snapshot_revision_entry/1)
          |> Enum.sort_by(&{&1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp default_antenna_pointing_state_revision(organization_id, mission_id, opts) do
    "ground_station_antenna_pointing_state:" <>
      RuntimeCacheKey.fingerprint(%{
        source_endpoints:
          organization_id
          |> default_source_endpoints(mission_id, opts)
          |> Enum.map(&source_endpoint_revision_entry/1)
          |> Enum.sort_by(&(&1.source_endpoint_id || "")),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.antenna_pointing(mission_id, opts)
          |> Enum.map(&antenna_pointing_revision_entry/1)
          |> Enum.sort_by(&{&1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp default_transport_bitrate_revision(organization_id, mission_id, opts) do
    "transport_bitrate:" <>
      RuntimeCacheKey.fingerprint(%{
        transports:
          organization_id
          |> default_transports(mission_id, opts)
          |> Enum.map(&transport_revision_entry/1)
          |> Enum.sort_by(&(&1.transport_id || "")),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.transport_bitrate(mission_id, opts)
          |> Enum.map(&transport_metric_revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || &1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp default_link_rf_lock_state_revision(organization_id, mission_id, opts) do
    "link_rf_lock_state:" <>
      RuntimeCacheKey.fingerprint(%{
        transports:
          organization_id
          |> default_transports(mission_id, opts)
          |> Enum.map(&transport_revision_entry/1)
          |> Enum.sort_by(&(&1.transport_id || "")),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.link_rf_lock(mission_id, opts)
          |> Enum.map(&link_rf_lock_revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || &1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp default_link_rf_frame_sync_state_revision(organization_id, mission_id, opts) do
    "link_rf_frame_sync_state:" <>
      RuntimeCacheKey.fingerprint(%{
        transports:
          organization_id
          |> default_transports(mission_id, opts)
          |> Enum.map(&transport_revision_entry/1)
          |> Enum.sort_by(&(&1.transport_id || "")),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.link_rf_frame_sync(mission_id, opts)
          |> Enum.map(&link_rf_frame_sync_revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || &1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp default_link_rf_metric_revision(organization_id, mission_id, opts) do
    "link_rf_metric:" <>
      RuntimeCacheKey.fingerprint(%{
        transports:
          organization_id
          |> default_transports(mission_id, opts)
          |> Enum.map(&transport_revision_entry/1)
          |> Enum.sort_by(&(&1.transport_id || "")),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.link_rf_metric(mission_id, opts)
          |> Enum.map(&link_rf_metric_revision_entry/1)
          |> Enum.sort_by(
            &{&1.observable_id || "", &1.transport_id || &1.resource_id || "",
             &1.observed_at || ""}
          )
      })
  end

  defp default_runtime_metric_snapshots(_organization_id, _mission_id, _opts) do
    RuntimeHealth.snapshot()
    |> Map.get(:metrics, %{})
    |> Map.get(:ingress_processing_latency_ms, [])
  end

  defp overlay_ingress_processing_latency_snapshots(durable_snapshots, runtime_snapshots) do
    durable_snapshots
    |> Enum.map(&IngressProcessingLatencyRows.normalize_snapshot/1)
    |> Enum.map(&{&1, 0})
    |> Kernel.++(
      runtime_snapshots
      |> Enum.map(&IngressProcessingLatencyRows.normalize_snapshot/1)
      |> Enum.map(&{&1, 1})
    )
    |> Enum.reduce(%{}, fn {snapshot, source_rank}, acc ->
      key = ingress_processing_latency_snapshot_key(snapshot)
      current = Map.get(acc, key)

      if newer_ingress_processing_latency_snapshot?({snapshot, source_rank}, current) do
        Map.put(acc, key, {snapshot, source_rank})
      else
        acc
      end
    end)
    |> Map.values()
    |> Enum.map(fn {snapshot, _source_rank} -> snapshot end)
    |> Enum.sort_by(
      &{attr(&1, :source_endpoint_id) || "", attr(&1, :spacecraft_id) || "",
       attr(&1, :observed_at) || DateTime.from_unix!(0)},
      :desc
    )
  end

  defp newer_ingress_processing_latency_snapshot?({_snapshot, _source_rank}, nil), do: true

  defp newer_ingress_processing_latency_snapshot?(
         {snapshot, source_rank},
         {current_snapshot, current_source_rank}
       ) do
    case compare_ingress_processing_latency_observed_at(
           attr(snapshot, :observed_at),
           attr(current_snapshot, :observed_at)
         ) do
      :gt -> true
      :eq -> source_rank >= current_source_rank
      :lt -> false
    end
  end

  defp compare_ingress_processing_latency_observed_at(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_ingress_processing_latency_observed_at(%DateTime{}, _right), do: :gt
  defp compare_ingress_processing_latency_observed_at(_left, %DateTime{}), do: :lt
  defp compare_ingress_processing_latency_observed_at(_left, _right), do: :eq

  defp ingress_processing_latency_snapshot_key(snapshot) do
    cond do
      is_binary(attr(snapshot, :source_endpoint_id)) and attr(snapshot, :source_endpoint_id) != "" ->
        {:source_endpoint, attr(snapshot, :mission_id), attr(snapshot, :source_endpoint_id)}

      is_binary(attr(snapshot, :spacecraft_id)) and attr(snapshot, :spacecraft_id) != "" ->
        {:spacecraft, attr(snapshot, :mission_id), attr(snapshot, :spacecraft_id)}

      true ->
        {:mission, attr(snapshot, :mission_id)}
    end
  end

  defp default_ingress_processing_latency_snapshots(organization_id, mission_id, opts) do
    durable_metric_snapshots_fun =
      Keyword.get(
        opts,
        :durable_ingress_processing_latency_snapshots_fun,
        &default_durable_ingress_processing_latency_snapshots/3
      )

    durable_snapshots =
      durable_metric_snapshots_fun.(organization_id, mission_id, opts)

    if Keyword.get(opts, :replay_run_id) do
      durable_snapshots
    else
      runtime_metric_snapshots_fun =
        Keyword.get(
          opts,
          :runtime_health_ingress_processing_latency_snapshots_fun,
          &default_runtime_metric_snapshots/3
        )

      durable_snapshots
      |> overlay_ingress_processing_latency_snapshots(
        runtime_metric_snapshots_fun.(organization_id, mission_id, opts)
      )
    end
  end

  defp default_durable_ingress_processing_latency_snapshots(organization_id, mission_id, opts) do
    OperationalEventSnapshots.ingress_latency(organization_id, mission_id, opts)
  end

  defp default_ingress_processing_latency_revision(organization_id, mission_id, opts) do
    "ingress_processing_latency:" <>
      RuntimeCacheKey.fingerprint(%{
        snapshots:
          organization_id
          |> default_ingress_processing_latency_snapshots(mission_id, opts)
          |> Enum.map(&ingress_processing_latency_revision_entry/1)
          |> Enum.sort_by(
            &{&1.source_endpoint_id || "", &1.spacecraft_id || "", &1.observed_at || ""}
          )
      })
  end

  defp transport_revision_entry(transport) do
    %{
      transport_id: attr(transport, :transport_id),
      display_name: attr(transport, :display_name),
      adapter_key: attr(transport, :adapter_key),
      metadata: attr(transport, :metadata)
    }
  end

  defp source_endpoint_revision_entry(source_endpoint) do
    %{
      source_endpoint_id: attr(source_endpoint, :source_endpoint_id),
      display_name: attr(source_endpoint, :display_name),
      adapter_key: attr(source_endpoint, :adapter_key),
      metadata: attr(source_endpoint, :metadata)
    }
  end

  defp connection_snapshot_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      connection_state: connection_state(snapshot),
      observed_at: attr(snapshot, :observed_at)
    }
  end

  defp transport_metric_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: TransportBitrateRows.value(snapshot, attr(snapshot, :observable_id)),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
    }
  end

  defp link_rf_lock_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: LinkRfStateRows.lock_state(snapshot),
      observed_at: attr(snapshot, :observed_at)
    }
  end

  defp link_rf_frame_sync_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: LinkRfStateRows.frame_sync_state(snapshot),
      observed_at: attr(snapshot, :observed_at)
    }
  end

  defp antenna_pointing_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: AntennaPointingRows.state(snapshot),
      observed_at: attr(snapshot, :observed_at)
    }
  end

  defp link_rf_metric_revision_entry(snapshot) do
    observable_id = LinkRfMetricRows.observable_id(snapshot)

    %{
      observable_id: observable_id,
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: LinkRfMetricRows.value(snapshot, observable_id),
      unit: LinkRfMetricRows.unit(snapshot, observable_id),
      observed_at: attr(snapshot, :observed_at)
    }
  end

  defp ingress_processing_latency_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id) || "ingress.processing_latency_ms",
      mission_id: attr(snapshot, :mission_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) ||
          attr(snapshot, :source_endpoint_ref) ||
          attr(snapshot, :source_ref),
      spacecraft_id: attr(snapshot, :spacecraft_id),
      contact_id:
        attr(snapshot, :contact_id) ||
          attr(snapshot, :scheduled_contact_id) ||
          attr(snapshot, :realized_contact_id),
      transport_id: attr(snapshot, :transport_id),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: IngressProcessingLatencyRows.value(snapshot),
      unit: attr(snapshot, :unit) || "ms",
      observed_at: attr(snapshot, :observed_at),
      error?: attr(snapshot, :error?) || false,
      replay_run_id: attr(snapshot, :replay_run_id)
    }
  end

  defp adapter_opts(%PlannedSourceRequest{} = request, source_binding) do
    [
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      replay_run_id: replay_run_id(request),
      dataset: dataset(source_binding),
      from: request_time_bound(request, [:from, :start, :start_time]),
      to: request_time_bound(request, [:to, :end, :end_time])
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp required_request_context(%PlannedSourceRequest{} = request, key) do
    case Map.get(request, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _missing ->
        {:warning,
         warning(request, :"missing_#{key}", :error, "Missing request context", %{key: key})}
    end
  end

  defp realm(%PlannedSourceRequest{data_context: data_context}, source_binding) do
    context_value(data_context, :realm) || context_value(source_binding, :realm)
  end

  defp replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      context_value(request.time_context, :replay_run_id)
  end

  defp dataset(source_binding), do: context_value(source_binding, :dataset)

  defp source_binding_id(%{binding: %{binding_id: binding_id}}), do: binding_id
  defp source_binding_id(_source_binding), do: nil

  defp data_source_id(%PlannedSourceRequest{} = request, source_binding) do
    resolved_data_source_id(source_binding) ||
      DataContext.source_value(request.data_context, request.logical_source, :data_source_id)
  end

  defp resolved_data_source_id(%{data_source: %{data_source_id: data_source_id}}),
    do: data_source_id

  defp resolved_data_source_id(_source_binding), do: nil

  defp context_value(nil, _key), do: nil

  defp context_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil

  defp first_context_value(context, keys) do
    Enum.find_value(keys, &context_value(context, &1))
  end

  defp request_time_bound(%PlannedSourceRequest{} = request, keys) do
    request.time_context
    |> first_context_value(keys)
    |> normalize_time_bound()
  end

  defp normalize_time_bound(nil), do: nil
  defp normalize_time_bound(%DateTime{} = value), do: value

  defp normalize_time_bound(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp normalize_time_bound(_value), do: nil

  defp metadata_attr(value, key) when is_atom(key) do
    value
    |> attr(:metadata)
    |> attr(key)
  end

  defp present_text?(value), do: is_binary(value) and value != ""

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details: Map.put(details, :source_request_id, request.request_id)
    }
  end
end
