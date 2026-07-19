defmodule Cadence.Dashboards.Sources.OperationalObservables do
  @moduledoc """
  Dashboard adapter for operational rollups that are already projected inside
  Cadence.

  v0 exposes constellation health as a spacecraft-by-worst-limit-state matrix.
  """

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    Field,
    Frame,
    OperationalObservable,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    ScopeContext,
    SourceCapabilities,
    SourceFacts,
    SourceFreshness,
    SourceResult
  }

  alias Cadence.Commanding
  alias Cadence.Comms.TransportStore
  alias Cadence.Contacts
  alias Cadence.Limits.Event
  alias Cadence.OperationalEvents
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.SourceEndpoints
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.RuntimeHealth

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    ConnectionFrames,
    ConnectionRows,
    ProductPolicy,
    RevisionPolicy
  }

  @state_severity %{red: 3, yellow: 2, blue: 1, green: 0}
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
  @antenna_pointing_states [:idle, :slewing, :acquiring, :tracking, :stowed, :degraded, :unknown]
  @rf_lock_states [:locked, :acquiring, :degraded, :unlocked, :unknown]
  @frame_sync_states [:synchronized, :acquiring, :degraded, :lost, :unknown]
  @managed_runtime_event_kinds [
    :managed_capability_initialized,
    :managed_capability_record_handled,
    :managed_capability_timer_handled,
    :managed_action_requested,
    :managed_timer_scheduled,
    :managed_timer_fired,
    :managed_timer_canceled
  ]
  @managed_runtime_source_record_kinds [
    :managed_capability_record,
    :managed_action_request,
    :managed_timer_event
  ]
  @transport_runtime_event_kinds [
    :transport_initialized,
    :transport_event_handled,
    :transport_control_input_handled,
    :transport_timer_handled,
    :transport_action_requested,
    :transport_timer_scheduled,
    :transport_timer_fired,
    :transport_timer_canceled
  ]
  @transport_runtime_source_record_kinds [
    :transport_capability_record,
    :transport_action_request,
    :transport_timer_event
  ]

  @type contact_fun :: (binary(), binary(), keyword() -> [struct()])
  @type connection_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @type latest_states_fun :: (binary() | nil, binary(), keyword() -> [Event.t()])
  @type transport_metric_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @type transport_execution_intervals_fun :: (binary(), binary(), keyword() ->
                                                [
                                                  map() | struct()
                                                ])
  @type runtime_metric_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @type spacecraft_fun :: (binary() | nil, binary(), keyword() -> [Spacecraft.t()])

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
      contacts_phase: &default_contact_phase_revision/3,
      connection_state: &default_connection_state_revision/3,
      ground_station_antenna_pointing_state: &default_antenna_pointing_state_revision/3,
      link_rf_lock_state: &default_link_rf_lock_state_revision/3,
      link_rf_frame_sync_state: &default_link_rf_frame_sync_state_revision/3,
      link_rf_metric: &default_link_rf_metric_revision/3,
      transport_bitrate: &default_transport_bitrate_revision/3,
      transport_execution_state: &default_transport_execution_state_revision/3,
      managed_runtime_activity: &default_managed_runtime_activity_revision/3,
      transport_runtime_activity: &default_transport_runtime_activity_revision/3,
      ingress_processing_latency: &default_ingress_processing_latency_revision/3,
      command_queue_depth: &default_command_queue_revision/3
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
    latest_states_fun = Keyword.get(opts, :latest_states_fun, &default_latest_states/3)
    spacecraft_fun = Keyword.get(opts, :spacecraft_fun, &default_spacecraft/3)

    spacecraft =
      spacecraft_fun.(organization_id, mission_id, adapter_opts(request, source_binding))

    point_states =
      latest_states_fun.(organization_id, mission_id, adapter_opts(request, source_binding))

    frame = constellation_health_frame(request, source_binding, spacecraft, point_states)

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
      contacts_phase_frame(
        request,
        source_binding,
        contact_phase_latest_rows(request, source_binding, organization_id, mission_id, opts)
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
      contacts_phase_history_frame(
        request,
        source_binding,
        contact_phase_history_rows(request, source_binding, organization_id, mission_id, opts)
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
      transport_execution_state_history_frame(
        request,
        source_binding,
        transport_execution_history_rows(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )
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
      managed_runtime_activity_history_frame(
        request,
        source_binding,
        managed_runtime_activity_history_rows(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )
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
      transport_runtime_activity_history_frame(
        request,
        source_binding,
        transport_runtime_activity_history_rows(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts
        )
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
      command_queue_depth_frame(
        request,
        source_binding,
        command_queue_depth_rows(request, source_binding, organization_id, mission_id, opts)
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
        contacts_phase_frame(
          request,
          source_binding,
          contact_phase_latest_rows(request, source_binding, organization_id, mission_id, opts)
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
        transport_execution_state_history_frame(
          request,
          source_binding,
          transport_execution_history_rows(
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
        managed_runtime_activity_history_frame(
          request,
          source_binding,
          managed_runtime_activity_history_rows(
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
        transport_runtime_activity_history_frame(
          request,
          source_binding,
          transport_runtime_activity_history_rows(
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
        command_queue_depth_frame(
          request,
          source_binding,
          command_queue_depth_rows(request, source_binding, organization_id, mission_id, opts)
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

  defp contact_phase_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    scheduled_contacts_fun =
      Keyword.get(opts, :scheduled_contacts_fun, &default_scheduled_contacts/3)

    realized_contacts_fun =
      Keyword.get(opts, :realized_contacts_fun, &default_realized_contacts/3)

    adapter_opts = adapter_opts(request, source_binding)

    contact_phase_rows(
      scheduled_contacts_fun.(
        organization_id,
        mission_id,
        adapter_opts
      ),
      realized_contacts_fun.(
        organization_id,
        mission_id,
        adapter_opts
      ),
      contact_phase_scope(request, organization_id, mission_id, opts, adapter_opts)
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp connection_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    connection_snapshots_fun =
      Keyword.get(opts, :connection_snapshots_fun, &default_connection_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    ConnectionRows.latest(
      request.observables,
      transports_fun.(organization_id, mission_id, adapter_opts),
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      connection_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp antenna_pointing_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    antenna_pointing_snapshots_fun =
      Keyword.get(
        opts,
        :antenna_pointing_snapshots_fun,
        &default_antenna_pointing_snapshots/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    antenna_pointing_rows(
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      antenna_pointing_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp link_rf_lock_latest_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_lock_snapshots_fun =
      Keyword.get(opts, :link_rf_lock_snapshots_fun, &default_link_rf_lock_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    link_rf_lock_rows(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_lock_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp link_rf_metric_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_metric_snapshots_fun =
      Keyword.get(opts, :link_rf_metric_snapshots_fun, &default_link_rf_metric_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    link_rf_metric_rows(
      request.observables,
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_metric_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp link_rf_metric_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    link_rf_metric_snapshots_fun =
      Keyword.get(opts, :link_rf_metric_snapshots_fun, &default_link_rf_metric_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    transports = transports_fun.(organization_id, mission_id, adapter_opts)
    snapshots = link_rf_metric_snapshots_fun.(organization_id, mission_id, adapter_opts)

    link_rf_metric_history_rows(request.observables, transports, snapshots, request)
  end

  defp antenna_pointing_history_rows(request, source_binding, organization_id, mission_id, opts) do
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    antenna_pointing_snapshots_fun =
      Keyword.get(
        opts,
        :antenna_pointing_snapshots_fun,
        &default_antenna_pointing_snapshots/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    antenna_pointing_history_rows(
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
        &default_link_rf_frame_sync_snapshots/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    link_rf_frame_sync_rows(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_frame_sync_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp transport_bitrate_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    metric_snapshots_fun =
      Keyword.get(opts, :transport_metric_snapshots_fun, &default_transport_metric_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    bitrate_rows(
      transports_fun.(organization_id, mission_id, adapter_opts),
      metric_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
    |> annotate_latest_freshness(request, opts)
  end

  defp transport_bitrate_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    metric_snapshots_fun =
      Keyword.get(opts, :transport_metric_snapshots_fun, &default_transport_metric_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    transports = transports_fun.(organization_id, mission_id, adapter_opts)
    snapshots = metric_snapshots_fun.(organization_id, mission_id, adapter_opts)

    transport_bitrate_history_rows(transports, snapshots, request)
  end

  defp command_queue_depth_rows(request, source_binding, organization_id, mission_id, opts) do
    command_queue_entries_fun =
      Keyword.get(opts, :command_queue_entries_fun, &default_command_queue_entries/3)

    entries =
      command_queue_entries_fun.(
        organization_id,
        mission_id,
        adapter_opts(request, source_binding)
      )
      |> Enum.filter(
        &(pending_command_queue_entry?(&1) and matches_command_queue_scope?(&1, request))
      )

    {scope_kind, resource_id, scope_ids} = command_queue_depth_scope(request, mission_id)

    [
      %{
        observable_id: "commanding.queue_depth",
        resource_id: resource_id,
        label: command_queue_depth_label(scope_kind, resource_id),
        scope_kind: scope_kind,
        source_endpoint_id: command_queue_depth_source_endpoint_id(scope_kind, scope_ids),
        value: length(entries),
        unit: "commands",
        observed_at: Keyword.get(opts, :read_time, DateTime.utc_now()),
        source: %{entries: entries}
      }
    ]
    |> annotate_latest_freshness(request, opts)
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
    |> Enum.map(&normalize_ingress_processing_latency_snapshot/1)
    |> Enum.filter(
      &(attr(&1, :mission_id) == mission_id and
          matches_request_replay_context?(&1, request) and
          matches_ingress_processing_latency_scope?(&1, request))
    )
    |> Enum.map(&ingress_processing_latency_row(&1, request, opts))
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

    rows =
      metric_snapshots_fun.(organization_id, mission_id, adapter_opts(request, source_binding))
      |> Enum.map(&normalize_ingress_processing_latency_snapshot/1)
      |> Enum.filter(
        &(attr(&1, :mission_id) == mission_id and
            matches_request_replay_context?(&1, request) and
            matches_ingress_processing_latency_scope?(&1, request))
      )
      |> Enum.map(&ingress_processing_latency_history_row/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&metric_history_row_in_request?(&1, request))
      |> Enum.sort_by(&metric_history_sort_key/1)
      |> apply_request_limit(request)

    rows ++ empty_ingress_processing_latency_history_rows(rows, request, mission_id)
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
        contacts_phase_history_frame(
          request,
          source_binding,
          contact_phase_history_rows(request, source_binding, organization_id, mission_id, opts)
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

  defp contact_phase_history_rows(request, source_binding, organization_id, mission_id, opts) do
    scheduled_contacts_fun =
      Keyword.get(opts, :scheduled_contacts_fun, &default_scheduled_contacts/3)

    realized_contacts_fun =
      Keyword.get(opts, :realized_contacts_fun, &default_realized_contacts/3)

    adapter_opts = adapter_opts(request, source_binding)

    contact_phase_rows(
      scheduled_contacts_fun.(
        organization_id,
        mission_id,
        adapter_opts
      ),
      realized_contacts_fun.(
        organization_id,
        mission_id,
        adapter_opts
      ),
      contact_phase_scope(request, organization_id, mission_id, opts, adapter_opts)
    )
    |> Enum.filter(&time_in_request_window?(Map.get(&1, :time), request))
    |> Enum.sort_by(&datetime_sort_key(Map.get(&1, :time)))
    |> apply_request_limit(request)
  end

  defp connection_history_rows(request, source_binding, organization_id, mission_id, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    connection_snapshots_fun =
      Keyword.get(opts, :connection_snapshots_fun, &default_connection_snapshots/3)

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
      Keyword.get(opts, :link_rf_lock_snapshots_fun, &default_link_rf_lock_snapshots/3)

    adapter_opts = adapter_opts(request, source_binding)

    link_rf_lock_history_rows(
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
        &default_link_rf_frame_sync_snapshots/3
      )

    adapter_opts = adapter_opts(request, source_binding)

    link_rf_frame_sync_history_rows(
      transports_fun.(organization_id, mission_id, adapter_opts),
      link_rf_frame_sync_snapshots_fun.(organization_id, mission_id, adapter_opts),
      request
    )
  end

  defp constellation_health_frame(request, source_binding, spacecraft, point_states) do
    rollup = rollup(spacecraft, point_states)

    %Frame{
      frame_id: "#{request.request_id}:constellation_health",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "spacecraft_id",
          kind: :string,
          values: Enum.map(rollup.spacecraft, & &1.spacecraft_id)
        },
        %Field{
          name: "worst_state",
          kind: :enum,
          values: Enum.map(rollup.spacecraft, & &1.worst_state)
        }
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :constellation_health,
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        counts: rollup.counts,
        returned_points: length(rollup.spacecraft),
        warning_codes: []
      }
    }
  end

  defp contacts_phase_frame(request, source_binding, contact_rows) do
    %Frame{
      frame_id: "#{request.request_id}:contacts_phase",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(contact_rows, & &1.observable_id)
        },
        %Field{
          name: "contact_id",
          kind: :string,
          values: Enum.map(contact_rows, & &1.contact_id)
        },
        %Field{
          name: "contact_kind",
          kind: :enum,
          values: Enum.map(contact_rows, & &1.contact_kind)
        },
        %Field{
          name: "phase",
          kind: :enum,
          values: Enum.map(contact_rows, & &1.phase)
        },
        %Field{
          name: "observed_at",
          kind: :time,
          values: Enum.map(contact_rows, & &1.observed_at)
        },
        %Field{
          name: "freshness_state",
          kind: :enum,
          values: Enum.map(contact_rows, & &1.freshness_state)
        },
        %Field{
          name: "age_ms",
          kind: :number,
          values: Enum.map(contact_rows, & &1.age_ms)
        }
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :contacts_phase,
        observable_id: "contacts.phase",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(contact_rows),
        freshness_policy: latest_freshness_policy(contact_rows),
        freshness_checked_at: latest_freshness_checked_at(contact_rows),
        warning_codes: latest_freshness_warning_codes(contact_rows),
        links:
          DataLinks.contact_links(request, Enum.map(contact_rows, & &1.source), source: :frame)
      }
    }
  end

  defp contacts_phase_history_frame(request, source_binding, contact_rows) do
    %Frame{
      frame_id: "#{request.request_id}:contacts_phase_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: Enum.map(contact_rows, & &1.time),
          metadata: %{axis: :occurred_at}
        },
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(contact_rows, & &1.observable_id)
        },
        %Field{
          name: "resource_id",
          kind: :string,
          values: Enum.map(contact_rows, & &1.contact_id)
        },
        %Field{
          name: "lane_id",
          kind: :string,
          values: Enum.map(contact_rows, &contact_phase_lane_id/1)
        },
        %Field{
          name: "label",
          kind: :string,
          values: Enum.map(contact_rows, &contact_phase_label/1)
        },
        %Field{
          name: "scope_kind",
          kind: :enum,
          values: Enum.map(contact_rows, fn _row -> :contact end)
        },
        %Field{
          name: "contact_id",
          kind: :string,
          values: Enum.map(contact_rows, & &1.contact_id)
        },
        %Field{
          name: "contact_kind",
          kind: :enum,
          values: Enum.map(contact_rows, & &1.contact_kind)
        },
        %Field{name: "phase", kind: :enum, values: Enum.map(contact_rows, & &1.phase)},
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(contact_rows, & &1.phase)
        }
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :contacts_phase_history,
        observable_id: "contacts.phase",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(contact_rows),
        warning_codes: [],
        links:
          DataLinks.contact_links(request, Enum.map(contact_rows, & &1.source), source: :frame)
      }
    }
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
    %Frame{
      frame_id: "#{request.request_id}:ground_station_antenna_pointing_state",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "observable_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.observable_id)
          },
          %Field{
            name: "resource_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.resource_id)
          },
          %Field{name: "label", kind: :string, values: Enum.map(pointing_rows, & &1.label)},
          %Field{
            name: "scope_kind",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.scope_kind)
          },
          %Field{
            name: "transport_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.transport_id)
          },
          %Field{
            name: "source_endpoint_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.source_endpoint_id)
          },
          %Field{
            name: "ground_station_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.ground_station_id)
          },
          %Field{
            name: "link_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.link_id)
          },
          %Field{
            name: "adapter_key",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.adapter_key)
          },
          %Field{name: "state", kind: :enum, values: Enum.map(pointing_rows, & &1.state)},
          %Field{
            name: "normalized_state",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.normalized_state)
          },
          %Field{
            name: "observed_at",
            kind: :time,
            values: Enum.map(pointing_rows, & &1.observed_at)
          },
          %Field{
            name: "freshness_state",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.freshness_state)
          },
          %Field{name: "age_ms", kind: :number, values: Enum.map(pointing_rows, & &1.age_ms)}
        ] ++ maybe_interval_identity_fields(pointing_rows),
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :ground_station_antenna_pointing_state,
        product_family: :ground_station,
        state_color_policy: :antenna_pointing_state,
        observable_ids: observable_ids(pointing_rows),
        observable_id: "ground.station.antenna_pointing_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(pointing_rows),
        freshness_policy: latest_freshness_policy(pointing_rows),
        freshness_checked_at: latest_freshness_checked_at(pointing_rows),
        warning_codes: latest_freshness_warning_codes(pointing_rows),
        links: operational_state_links(request, pointing_rows),
        evidence_refs: operational_interval_evidence_refs_from_rows(pointing_rows)
      }
    }
  end

  defp antenna_pointing_state_history_frame(request, source_binding, pointing_rows) do
    %Frame{
      frame_id: "#{request.request_id}:ground_station_antenna_pointing_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "time",
            kind: :time,
            values: Enum.map(pointing_rows, & &1.observed_at),
            metadata: %{axis: :occurred_at}
          },
          %Field{
            name: "observable_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.observable_id)
          },
          %Field{
            name: "resource_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.resource_id)
          },
          %Field{
            name: "lane_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.ground_station_id)
          },
          %Field{name: "label", kind: :string, values: Enum.map(pointing_rows, & &1.label)},
          %Field{
            name: "scope_kind",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.scope_kind)
          },
          %Field{
            name: "transport_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.transport_id)
          },
          %Field{
            name: "source_endpoint_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.source_endpoint_id)
          },
          %Field{
            name: "ground_station_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.ground_station_id)
          },
          %Field{
            name: "link_id",
            kind: :string,
            values: Enum.map(pointing_rows, & &1.link_id)
          },
          %Field{
            name: "adapter_key",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.adapter_key)
          },
          %Field{name: "state", kind: :enum, values: Enum.map(pointing_rows, & &1.state)},
          %Field{
            name: "normalized_state",
            kind: :enum,
            values: Enum.map(pointing_rows, & &1.normalized_state)
          }
        ] ++ maybe_interval_identity_fields(pointing_rows),
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :ground_station_antenna_pointing_state_history,
        product_family: :ground_station,
        state_color_policy: :antenna_pointing_state,
        observable_ids: observable_ids(pointing_rows),
        observable_id: "ground.station.antenna_pointing_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(pointing_rows),
        warning_codes: [],
        links: operational_history_links(request, pointing_rows),
        evidence_refs: operational_interval_evidence_refs_from_rows(pointing_rows)
      }
    }
  end

  defp transport_execution_state_history_frame(request, source_binding, rows) do
    %Frame{
      frame_id: "#{request.request_id}:transport_execution_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: Enum.map(rows, & &1.starts_at),
          metadata: %{axis: :occurred_at}
        },
        %Field{name: "ends_at", kind: :time, values: Enum.map(rows, & &1.ends_at)},
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(rows, & &1.observable_id)
        },
        %Field{name: "resource_id", kind: :string, values: Enum.map(rows, & &1.resource_id)},
        %Field{name: "lane_id", kind: :string, values: Enum.map(rows, & &1.lane_id)},
        %Field{name: "label", kind: :string, values: Enum.map(rows, & &1.label)},
        %Field{name: "scope_kind", kind: :enum, values: Enum.map(rows, & &1.scope_kind)},
        %Field{name: "transport_id", kind: :string, values: Enum.map(rows, & &1.transport_id)},
        %Field{
          name: "source_endpoint_id",
          kind: :string,
          values: Enum.map(rows, & &1.source_endpoint_id)
        },
        %Field{
          name: "ground_station_id",
          kind: :string,
          values: Enum.map(rows, & &1.ground_station_id)
        },
        %Field{name: "link_id", kind: :string, values: Enum.map(rows, & &1.link_id)},
        %Field{name: "contact_id", kind: :string, values: Enum.map(rows, & &1.contact_id)},
        %Field{name: "path_id", kind: :string, values: Enum.map(rows, & &1.path_id)},
        %Field{
          name: "transport_record_id",
          kind: :string,
          values: Enum.map(rows, & &1.transport_record_id)
        },
        %Field{name: "interval_id", kind: :string, values: Enum.map(rows, & &1.interval_id)},
        %Field{
          name: "source_event_id",
          kind: :string,
          values: Enum.map(rows, & &1.source_event_id)
        },
        %Field{name: "state", kind: :enum, values: Enum.map(rows, & &1.state)},
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(rows, & &1.normalized_state)
        }
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :transport_execution_state_history,
        product_family: :comms_transport,
        state_color_policy: :transport_execution_state,
        observable_ids: observable_ids(rows),
        observable_id: "comms.transport.execution_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(rows),
        warning_codes: [],
        links: operational_history_links(request, rows),
        evidence_refs: DataLinks.operational_interval_evidence_refs(Enum.map(rows, & &1.interval))
      }
    }
  end

  defp managed_runtime_activity_history_frame(request, source_binding, rows) do
    %Frame{
      frame_id: "#{request.request_id}:managed_runtime_activity_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: Enum.map(rows, & &1.starts_at),
          metadata: %{axis: :occurred_at}
        },
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(rows, & &1.observable_id)
        },
        %Field{name: "resource_id", kind: :string, values: Enum.map(rows, & &1.resource_id)},
        %Field{name: "lane_id", kind: :string, values: Enum.map(rows, & &1.lane_id)},
        %Field{name: "label", kind: :string, values: Enum.map(rows, & &1.label)},
        %Field{name: "scope_kind", kind: :enum, values: Enum.map(rows, & &1.scope_kind)},
        %Field{
          name: "capability_instance_id",
          kind: :string,
          values: Enum.map(rows, & &1.capability_instance_id)
        },
        %Field{name: "family_key", kind: :enum, values: Enum.map(rows, & &1.family_key)},
        %Field{name: "activation_id", kind: :string, values: Enum.map(rows, & &1.activation_id)},
        %Field{
          name: "binding_set_id",
          kind: :string,
          values: Enum.map(rows, & &1.binding_set_id)
        },
        %Field{name: "packet_id", kind: :string, values: Enum.map(rows, & &1.packet_id)},
        %Field{name: "evidence_id", kind: :string, values: Enum.map(rows, & &1.evidence_id)},
        %Field{name: "timer_key", kind: :string, values: Enum.map(rows, & &1.timer_key)},
        %Field{name: "action_kind", kind: :enum, values: Enum.map(rows, & &1.action_kind)},
        %Field{
          name: "action_request_document_json",
          kind: :string,
          values: Enum.map(rows, & &1.action_request_document_json)
        },
        %Field{
          name: "record_event_kind",
          kind: :enum,
          values: Enum.map(rows, & &1.record_event_kind)
        },
        %Field{
          name: "emitted_record_kinds",
          kind: :string,
          values: Enum.map(rows, & &1.emitted_record_kinds)
        },
        %Field{
          name: "emitted_record_count",
          kind: :number,
          values: Enum.map(rows, & &1.emitted_record_count)
        },
        %Field{
          name: "action_request_count",
          kind: :number,
          values: Enum.map(rows, & &1.action_request_count)
        },
        %Field{
          name: "state_snapshot_json",
          kind: :string,
          values: Enum.map(rows, & &1.state_snapshot_json)
        },
        %Field{
          name: "record_metadata_json",
          kind: :string,
          values: Enum.map(rows, & &1.record_metadata_json)
        },
        %Field{
          name: "runtime_fact_kind",
          kind: :enum,
          values: Enum.map(rows, & &1.runtime_fact_kind)
        },
        %Field{
          name: "runtime_fact_id",
          kind: :string,
          values: Enum.map(rows, & &1.runtime_fact_id)
        },
        %Field{
          name: "source_event_id",
          kind: :string,
          values: Enum.map(rows, & &1.source_event_id)
        },
        %Field{name: "state", kind: :enum, values: Enum.map(rows, & &1.state)},
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(rows, & &1.normalized_state)
        }
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :managed_runtime_activity_history,
        product_family: :runtime_managed,
        state_color_policy: :managed_runtime_activity,
        observable_ids: observable_ids(rows),
        observable_id: "runtime.managed_activity",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        runtime_fact_ids: managed_runtime_fact_ids(rows),
        returned_points: length(rows),
        warning_codes: [],
        links: operational_history_links(request, rows),
        evidence_refs:
          DataLinks.operational_event_evidence_refs(rows, source: :operational_observables)
      }
    }
  end

  defp link_rf_lock_state_frame(request, source_binding, lock_rows) do
    %Frame{
      frame_id: "#{request.request_id}:link_rf_lock_state",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "observable_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.observable_id)
          },
          %Field{
            name: "resource_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.resource_id)
          },
          %Field{name: "label", kind: :string, values: Enum.map(lock_rows, & &1.label)},
          %Field{
            name: "scope_kind",
            kind: :enum,
            values: Enum.map(lock_rows, & &1.scope_kind)
          },
          %Field{
            name: "transport_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.transport_id)
          },
          %Field{
            name: "source_endpoint_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.source_endpoint_id)
          },
          %Field{
            name: "ground_station_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.ground_station_id)
          },
          %Field{
            name: "link_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.link_id)
          },
          %Field{name: "adapter_key", kind: :enum, values: Enum.map(lock_rows, & &1.adapter_key)},
          %Field{name: "state", kind: :enum, values: Enum.map(lock_rows, & &1.state)},
          %Field{
            name: "normalized_state",
            kind: :enum,
            values: Enum.map(lock_rows, & &1.normalized_state)
          },
          %Field{
            name: "observed_at",
            kind: :time,
            values: Enum.map(lock_rows, & &1.observed_at)
          },
          %Field{
            name: "freshness_state",
            kind: :enum,
            values: Enum.map(lock_rows, & &1.freshness_state)
          },
          %Field{name: "age_ms", kind: :number, values: Enum.map(lock_rows, & &1.age_ms)}
        ] ++ maybe_interval_identity_fields(lock_rows),
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :link_rf_lock_state,
        product_family: :link_rf,
        state_color_policy: :lock_state,
        observable_ids: observable_ids(lock_rows),
        observable_id: "link.rf_lock_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(lock_rows),
        freshness_policy: latest_freshness_policy(lock_rows),
        freshness_checked_at: latest_freshness_checked_at(lock_rows),
        warning_codes: latest_freshness_warning_codes(lock_rows),
        links: operational_state_links(request, lock_rows),
        evidence_refs: operational_interval_evidence_refs_from_rows(lock_rows)
      }
    }
  end

  defp link_rf_lock_state_history_frame(request, source_binding, lock_rows) do
    %Frame{
      frame_id: "#{request.request_id}:link_rf_lock_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "time",
            kind: :time,
            values: Enum.map(lock_rows, & &1.observed_at),
            metadata: %{axis: :occurred_at}
          },
          %Field{
            name: "observable_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.observable_id)
          },
          %Field{
            name: "resource_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.resource_id)
          },
          %Field{name: "lane_id", kind: :string, values: Enum.map(lock_rows, & &1.link_id)},
          %Field{name: "label", kind: :string, values: Enum.map(lock_rows, & &1.label)},
          %Field{
            name: "scope_kind",
            kind: :enum,
            values: Enum.map(lock_rows, & &1.scope_kind)
          },
          %Field{
            name: "transport_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.transport_id)
          },
          %Field{
            name: "source_endpoint_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.source_endpoint_id)
          },
          %Field{
            name: "ground_station_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.ground_station_id)
          },
          %Field{
            name: "link_id",
            kind: :string,
            values: Enum.map(lock_rows, & &1.link_id)
          },
          %Field{name: "adapter_key", kind: :enum, values: Enum.map(lock_rows, & &1.adapter_key)},
          %Field{name: "state", kind: :enum, values: Enum.map(lock_rows, & &1.state)},
          %Field{
            name: "normalized_state",
            kind: :enum,
            values: Enum.map(lock_rows, & &1.normalized_state)
          }
        ] ++ maybe_interval_identity_fields(lock_rows),
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :link_rf_lock_state_history,
        product_family: :link_rf,
        state_color_policy: :lock_state,
        observable_ids: observable_ids(lock_rows),
        observable_id: "link.rf_lock_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(lock_rows),
        warning_codes: [],
        links: operational_history_links(request, lock_rows),
        evidence_refs: operational_interval_evidence_refs_from_rows(lock_rows)
      }
    }
  end

  defp link_rf_frame_sync_state_frame(request, source_binding, sync_rows) do
    %Frame{
      frame_id: "#{request.request_id}:link_rf_frame_sync_state",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "observable_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.observable_id)
          },
          %Field{
            name: "resource_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.resource_id)
          },
          %Field{name: "label", kind: :string, values: Enum.map(sync_rows, & &1.label)},
          %Field{name: "scope_kind", kind: :enum, values: Enum.map(sync_rows, & &1.scope_kind)},
          %Field{
            name: "transport_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.transport_id)
          },
          %Field{
            name: "source_endpoint_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.source_endpoint_id)
          },
          %Field{
            name: "ground_station_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.ground_station_id)
          },
          %Field{name: "link_id", kind: :string, values: Enum.map(sync_rows, & &1.link_id)},
          %Field{name: "adapter_key", kind: :enum, values: Enum.map(sync_rows, & &1.adapter_key)},
          %Field{name: "state", kind: :enum, values: Enum.map(sync_rows, & &1.state)},
          %Field{
            name: "normalized_state",
            kind: :enum,
            values: Enum.map(sync_rows, & &1.normalized_state)
          },
          %Field{name: "observed_at", kind: :time, values: Enum.map(sync_rows, & &1.observed_at)},
          %Field{
            name: "freshness_state",
            kind: :enum,
            values: Enum.map(sync_rows, & &1.freshness_state)
          },
          %Field{name: "age_ms", kind: :number, values: Enum.map(sync_rows, & &1.age_ms)}
        ] ++ maybe_interval_identity_fields(sync_rows),
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :link_rf_frame_sync_state,
        product_family: :link_rf,
        state_color_policy: :frame_sync_state,
        observable_ids: observable_ids(sync_rows),
        observable_id: "link.frame_sync_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(sync_rows),
        freshness_policy: latest_freshness_policy(sync_rows),
        freshness_checked_at: latest_freshness_checked_at(sync_rows),
        warning_codes: latest_freshness_warning_codes(sync_rows),
        links: operational_state_links(request, sync_rows),
        evidence_refs: operational_interval_evidence_refs_from_rows(sync_rows)
      }
    }
  end

  defp link_rf_frame_sync_state_history_frame(request, source_binding, sync_rows) do
    %Frame{
      frame_id: "#{request.request_id}:link_rf_frame_sync_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields:
        [
          %Field{
            name: "time",
            kind: :time,
            values: Enum.map(sync_rows, & &1.observed_at),
            metadata: %{axis: :occurred_at}
          },
          %Field{
            name: "observable_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.observable_id)
          },
          %Field{
            name: "resource_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.resource_id)
          },
          %Field{name: "lane_id", kind: :string, values: Enum.map(sync_rows, & &1.link_id)},
          %Field{name: "label", kind: :string, values: Enum.map(sync_rows, & &1.label)},
          %Field{name: "scope_kind", kind: :enum, values: Enum.map(sync_rows, & &1.scope_kind)},
          %Field{
            name: "transport_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.transport_id)
          },
          %Field{
            name: "source_endpoint_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.source_endpoint_id)
          },
          %Field{
            name: "ground_station_id",
            kind: :string,
            values: Enum.map(sync_rows, & &1.ground_station_id)
          },
          %Field{name: "link_id", kind: :string, values: Enum.map(sync_rows, & &1.link_id)},
          %Field{name: "adapter_key", kind: :enum, values: Enum.map(sync_rows, & &1.adapter_key)},
          %Field{name: "state", kind: :enum, values: Enum.map(sync_rows, & &1.state)},
          %Field{
            name: "normalized_state",
            kind: :enum,
            values: Enum.map(sync_rows, & &1.normalized_state)
          }
        ] ++ maybe_interval_identity_fields(sync_rows),
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :link_rf_frame_sync_state_history,
        product_family: :link_rf,
        state_color_policy: :frame_sync_state,
        observable_ids: observable_ids(sync_rows),
        observable_id: "link.frame_sync_state",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(sync_rows),
        warning_codes: [],
        links: operational_history_links(request, sync_rows),
        evidence_refs: operational_interval_evidence_refs_from_rows(sync_rows)
      }
    }
  end

  defp operational_history_links(request, rows) do
    DataLinks.operational_resource_links(request, rows, source: :frame) ++
      DataLinks.operational_event_links(request, rows, source: :frame)
  end

  defp operational_state_links(request, rows), do: operational_history_links(request, rows)

  defp maybe_interval_identity_fields(rows) do
    if Enum.any?(rows, &(attr(&1, :interval_id) || attr(&1, :source_event_id))) do
      [
        %Field{
          name: "interval_id",
          kind: :string,
          values: Enum.map(rows, &attr(&1, :interval_id))
        },
        %Field{
          name: "source_event_id",
          kind: :string,
          values: Enum.map(rows, &attr(&1, :source_event_id))
        }
      ]
    else
      []
    end
  end

  defp operational_interval_evidence_refs_from_rows(rows) do
    rows
    |> Enum.map(&attr(&1, :interval))
    |> DataLinks.operational_interval_evidence_refs(source: :operational_observables)
  end

  defp link_rf_metric_frame(request, source_binding, metric_rows) do
    %Frame{
      frame_id: "#{request.request_id}:link_rf_metric",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(metric_rows, & &1.observable_id)
        },
        %Field{
          name: "resource_id",
          kind: :string,
          values: Enum.map(metric_rows, & &1.resource_id)
        },
        %Field{name: "label", kind: :string, values: Enum.map(metric_rows, & &1.label)},
        %Field{
          name: "scope_kind",
          kind: :enum,
          values: Enum.map(metric_rows, & &1.scope_kind)
        },
        %Field{
          name: "transport_id",
          kind: :string,
          values: Enum.map(metric_rows, & &1.transport_id)
        },
        %Field{
          name: "source_endpoint_id",
          kind: :string,
          values: Enum.map(metric_rows, & &1.source_endpoint_id)
        },
        %Field{
          name: "ground_station_id",
          kind: :string,
          values: Enum.map(metric_rows, & &1.ground_station_id)
        },
        %Field{
          name: "link_id",
          kind: :string,
          values: Enum.map(metric_rows, & &1.link_id)
        },
        %Field{
          name: "adapter_key",
          kind: :enum,
          values: Enum.map(metric_rows, & &1.adapter_key)
        },
        %Field{name: "value", kind: :number, values: Enum.map(metric_rows, & &1.value)},
        %Field{name: "unit", kind: :string, values: Enum.map(metric_rows, & &1.unit)},
        %Field{
          name: "observed_at",
          kind: :time,
          values: Enum.map(metric_rows, & &1.observed_at)
        },
        %Field{
          name: "freshness_state",
          kind: :enum,
          values: Enum.map(metric_rows, & &1.freshness_state)
        },
        %Field{name: "age_ms", kind: :number, values: Enum.map(metric_rows, & &1.age_ms)}
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :link_rf_metric,
        product_family: :link_rf,
        observable_ids: observable_ids(metric_rows),
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(metric_rows),
        freshness_policy: latest_freshness_policy(metric_rows),
        freshness_checked_at: latest_freshness_checked_at(metric_rows),
        warning_codes: latest_freshness_warning_codes(metric_rows),
        links: operational_metric_links(request, metric_rows),
        evidence_refs: operational_metric_evidence_refs(metric_rows)
      }
    }
  end

  defp transport_bitrate_frame(request, source_binding, bitrate_rows) do
    %Frame{
      frame_id: "#{request.request_id}:transport_bitrate",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(bitrate_rows, & &1.observable_id)
        },
        %Field{
          name: "resource_id",
          kind: :string,
          values: Enum.map(bitrate_rows, & &1.resource_id)
        },
        %Field{name: "label", kind: :string, values: Enum.map(bitrate_rows, & &1.label)},
        %Field{
          name: "scope_kind",
          kind: :enum,
          values: Enum.map(bitrate_rows, & &1.scope_kind)
        },
        %Field{
          name: "transport_id",
          kind: :string,
          values: Enum.map(bitrate_rows, & &1.transport_id)
        },
        %Field{
          name: "source_endpoint_id",
          kind: :string,
          values: Enum.map(bitrate_rows, & &1.source_endpoint_id)
        },
        %Field{
          name: "ground_station_id",
          kind: :string,
          values: Enum.map(bitrate_rows, & &1.ground_station_id)
        },
        %Field{
          name: "link_id",
          kind: :string,
          values: Enum.map(bitrate_rows, & &1.link_id)
        },
        %Field{
          name: "adapter_key",
          kind: :enum,
          values: Enum.map(bitrate_rows, & &1.adapter_key)
        },
        %Field{
          name: "value",
          kind: :number,
          values: Enum.map(bitrate_rows, & &1.value)
        },
        %Field{name: "unit", kind: :string, values: Enum.map(bitrate_rows, & &1.unit)},
        %Field{
          name: "observed_at",
          kind: :time,
          values: Enum.map(bitrate_rows, & &1.observed_at)
        },
        %Field{
          name: "freshness_state",
          kind: :enum,
          values: Enum.map(bitrate_rows, & &1.freshness_state)
        },
        %Field{name: "age_ms", kind: :number, values: Enum.map(bitrate_rows, & &1.age_ms)}
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :transport_bitrate,
        observable_ids: observable_ids(bitrate_rows),
        observable_id: single_observable_id(bitrate_rows),
        unit: "bit/s",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(bitrate_rows),
        freshness_policy: latest_freshness_policy(bitrate_rows),
        freshness_checked_at: latest_freshness_checked_at(bitrate_rows),
        warning_codes: latest_freshness_warning_codes(bitrate_rows),
        links: operational_metric_links(request, bitrate_rows),
        evidence_refs: operational_metric_evidence_refs(bitrate_rows)
      }
    }
  end

  defp operational_metric_history_frames(rows, request, source_binding, capability) do
    rows
    |> Enum.group_by(&metric_history_series_key/1)
    |> Enum.sort_by(fn {series_key, _rows} -> series_key end)
    |> Enum.map(fn {_series_key, series_rows} ->
      operational_metric_history_frame(request, source_binding, capability, series_rows)
    end)
    |> mark_partial_metric_history_frames()
  end

  defp mark_partial_metric_history_frames(frames) do
    returned? = Enum.any?(frames, &(frame_returned_points(&1) > 0))
    empty? = Enum.any?(frames, &(frame_returned_points(&1) == 0))

    if returned? and empty? do
      Enum.map(frames, &put_frame_warning_code(&1, :partial_data))
    else
      frames
    end
  end

  defp frame_returned_points(%Frame{meta: meta}) when is_map(meta) do
    case attr(meta, :returned_points) do
      count when is_integer(count) -> count
      _other -> 0
    end
  end

  defp frame_returned_points(_frame), do: 0

  defp put_frame_warning_code(%Frame{meta: meta} = frame, code) when is_atom(code) do
    warning_codes =
      meta
      |> attr(:warning_codes)
      |> List.wrap()
      |> Kernel.++([code])
      |> Enum.uniq()

    %Frame{frame | meta: Map.put(meta, :warning_codes, warning_codes)}
  end

  defp operational_metric_history_frame(request, source_binding, capability, rows) do
    [%{observable_id: observable_id} = first_row | _rest] = rows
    data_rows = Enum.reject(rows, &Map.get(&1, :empty_series?, false))
    resource_links = DataLinks.operational_resource_links(request, [first_row], source: :frame)
    resource_link_id = operational_resource_link_id(resource_links)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}:#{first_row.resource_id}",
      source: :operational_observables,
      shape: :wide,
      time_axis: :occurred_at,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: Enum.map(data_rows, & &1.observed_at),
          metadata: %{axis: :occurred_at}
        },
        %Field{
          name: observable_id,
          kind: :number,
          values: Enum.map(data_rows, & &1.value),
          metadata:
            %{
              observable_id: observable_id,
              label: first_row.label,
              unit: first_row.unit,
              resource_id: first_row.resource_id,
              scope_kind: first_row.scope_kind,
              transport_id: first_row.transport_id,
              source_endpoint_id: first_row.source_endpoint_id,
              ground_station_id: first_row.ground_station_id,
              link_id: first_row.link_id,
              contact_id: Map.get(first_row, :contact_id),
              adapter_key: first_row.adapter_key,
              resource_link_id: resource_link_id,
              links: resource_links
            }
            |> Map.reject(fn {_key, value} -> is_nil(value) end)
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          source_binding_id: source_binding_id(source_binding),
          dataset: dataset(source_binding),
          sampling: :raw_series,
          supported_capability: capability,
          product_family: metric_history_product_family(observable_id),
          observable_ids: [observable_id],
          observable_id: observable_id,
          resource_id: first_row.resource_id,
          scope_kind: first_row.scope_kind,
          transport_id: first_row.transport_id,
          source_endpoint_id: first_row.source_endpoint_id,
          ground_station_id: first_row.ground_station_id,
          link_id: first_row.link_id,
          adapter_key: first_row.adapter_key,
          unit: first_row.unit,
          realm: realm(request, source_binding),
          data_source_id: data_source_id(request, source_binding),
          replay_run_id: replay_run_id(request),
          returned_points: length(data_rows),
          warning_codes: [],
          resource_link_id: resource_link_id,
          links:
            resource_links ++
              DataLinks.operational_event_links(request, data_rows, source: :frame),
          evidence_refs: operational_metric_evidence_refs(data_rows)
        }
        |> maybe_put_contact_id(Map.get(first_row, :contact_id))
    }
  end

  defp maybe_put_contact_id(meta, contact_id) when contact_id in [nil, ""], do: meta
  defp maybe_put_contact_id(meta, contact_id), do: Map.put(meta, :contact_id, contact_id)

  defp operational_metric_links(request, rows) do
    DataLinks.operational_resource_links(request, rows, source: :frame) ++
      DataLinks.operational_event_links(request, rows, source: :frame)
  end

  defp operational_metric_evidence_refs(rows) do
    DataLinks.operational_event_evidence_refs(rows, source: :operational_observables)
  end

  defp operational_resource_link_id(links) do
    Enum.find_value(links, fn
      %{link_id: link_id} when is_binary(link_id) and link_id != "" -> link_id
      _link -> nil
    end)
  end

  defp command_queue_depth_frame(request, source_binding, depth_rows) do
    %Frame{
      frame_id: "#{request.request_id}:command_queue_depth",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(depth_rows, & &1.observable_id)
        },
        %Field{
          name: "resource_id",
          kind: :string,
          values: Enum.map(depth_rows, & &1.resource_id)
        },
        %Field{name: "label", kind: :string, values: Enum.map(depth_rows, & &1.label)},
        %Field{
          name: "scope_kind",
          kind: :enum,
          values: Enum.map(depth_rows, & &1.scope_kind)
        },
        %Field{
          name: "source_endpoint_id",
          kind: :string,
          values: Enum.map(depth_rows, & &1.source_endpoint_id)
        },
        %Field{name: "value", kind: :number, values: Enum.map(depth_rows, & &1.value)},
        %Field{name: "unit", kind: :string, values: Enum.map(depth_rows, & &1.unit)},
        %Field{
          name: "observed_at",
          kind: :time,
          values: Enum.map(depth_rows, & &1.observed_at)
        },
        %Field{
          name: "freshness_state",
          kind: :enum,
          values: Enum.map(depth_rows, & &1.freshness_state)
        },
        %Field{name: "age_ms", kind: :number, values: Enum.map(depth_rows, & &1.age_ms)}
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :command_queue_depth,
        product_family: :commanding,
        observable_ids: observable_ids(depth_rows),
        observable_id: "commanding.queue_depth",
        unit: "commands",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        command_queue_entry_ids: command_queue_entry_ids(depth_rows),
        returned_points: length(depth_rows),
        freshness_policy: latest_freshness_policy(depth_rows),
        freshness_checked_at: latest_freshness_checked_at(depth_rows),
        warning_codes: latest_freshness_warning_codes(depth_rows),
        links: DataLinks.operational_resource_links(request, depth_rows, source: :frame),
        evidence_refs: command_queue_entry_evidence_refs(depth_rows)
      }
    }
  end

  defp command_queue_entry_evidence_refs(depth_rows) do
    depth_rows
    |> command_queue_entries_from_rows()
    |> DataLinks.command_queue_entry_evidence_refs(source: :operational_observables)
  end

  defp command_queue_entry_ids(depth_rows) do
    depth_rows
    |> command_queue_entries_from_rows()
    |> Enum.map(&attr(&1, :command_queue_entry_id))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp command_queue_entries_from_rows(depth_rows) do
    depth_rows
    |> List.wrap()
    |> Enum.flat_map(fn row ->
      row
      |> attr(:source)
      |> case do
        %{entries: entries} when is_list(entries) -> entries
        %{"entries" => entries} when is_list(entries) -> entries
        _other -> []
      end
    end)
  end

  defp ingress_processing_latency_frame(request, source_binding, latency_rows) do
    %Frame{
      frame_id: "#{request.request_id}:ingress_processing_latency",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.observable_id)
        },
        %Field{
          name: "resource_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.resource_id)
        },
        %Field{name: "label", kind: :string, values: Enum.map(latency_rows, & &1.label)},
        %Field{
          name: "scope_kind",
          kind: :enum,
          values: Enum.map(latency_rows, & &1.scope_kind)
        },
        %Field{
          name: "source_endpoint_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.source_endpoint_id)
        },
        %Field{
          name: "transport_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.transport_id)
        },
        %Field{
          name: "ground_station_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.ground_station_id)
        },
        %Field{
          name: "link_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.link_id)
        },
        %Field{
          name: "contact_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.contact_id)
        },
        %Field{
          name: "adapter_key",
          kind: :enum,
          values: Enum.map(latency_rows, & &1.adapter_key)
        },
        %Field{
          name: "spacecraft_id",
          kind: :string,
          values: Enum.map(latency_rows, & &1.spacecraft_id)
        },
        %Field{name: "value", kind: :number, values: Enum.map(latency_rows, & &1.value)},
        %Field{name: "unit", kind: :string, values: Enum.map(latency_rows, & &1.unit)},
        %Field{
          name: "observed_at",
          kind: :time,
          values: Enum.map(latency_rows, & &1.observed_at)
        },
        %Field{
          name: "freshness_state",
          kind: :enum,
          values: Enum.map(latency_rows, & &1.freshness_state)
        },
        %Field{name: "age_ms", kind: :number, values: Enum.map(latency_rows, & &1.age_ms)},
        %Field{name: "error", kind: :boolean, values: Enum.map(latency_rows, & &1.error?)}
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :latest,
        supported_capability: :ingress_processing_latency,
        product_family: :runtime_ingress,
        observable_ids: observable_ids(latency_rows),
        observable_id: "ingress.processing_latency_ms",
        unit: "ms",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        returned_points: length(latency_rows),
        freshness_policy: latest_freshness_policy(latency_rows),
        freshness_checked_at: latest_freshness_checked_at(latency_rows),
        warning_codes: latest_freshness_warning_codes(latency_rows),
        links: operational_metric_links(request, latency_rows),
        evidence_refs: operational_metric_evidence_refs(latency_rows)
      }
    }
  end

  defp bitrate_rows(transports, snapshots, request) do
    snapshots = Enum.flat_map(snapshots, &normalize_transport_metric_snapshots/1)

    transports
    |> Enum.flat_map(&transport_bitrate_rows(&1, snapshots, request))
    |> Enum.filter(&matches_connection_scope?(&1, request))
  end

  defp transport_bitrate_history_rows(transports, snapshots, request) do
    rows =
      snapshots
      |> Enum.flat_map(&normalize_transport_metric_snapshots/1)
      |> Enum.map(&transport_bitrate_history_row(transports, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&metric_history_row_in_request?(&1, request))
      |> Enum.sort_by(&metric_history_sort_key/1)
      |> apply_request_limit(request)

    rows ++ empty_transport_bitrate_history_rows(transports, rows, request)
  end

  defp empty_transport_bitrate_history_rows(transports, rows, request) do
    present_series = MapSet.new(Enum.map(rows, &metric_history_series_key/1))

    transports
    |> Enum.flat_map(&transport_bitrate_rows(&1, [], request))
    |> Enum.filter(&matches_connection_scope?(&1, request))
    |> Enum.reject(&(metric_history_series_key(&1) in present_series))
    |> Enum.map(&Map.put(&1, :empty_series?, true))
  end

  defp observable_ids(rows) do
    rows
    |> Enum.map(& &1.observable_id)
    |> Enum.uniq()
  end

  defp single_observable_id(rows) do
    case observable_ids(rows) do
      [observable_id] -> observable_id
      _observable_ids -> nil
    end
  end

  defp transport_bitrate_rows(transport, snapshots, request) do
    request.observables
    |> Enum.filter(&(&1 in @bitrate_observable_ids))
    |> Enum.map(&transport_bitrate_row(transport, snapshots, &1))
  end

  defp transport_bitrate_row(transport, snapshots, observable_id) do
    transport_id = attr(transport, :transport_id)

    source_endpoint_id =
      metadata_attr(transport, :source_endpoint_id) ||
        metadata_attr(transport, :source_endpoint_ref)

    ground_station_id =
      metadata_attr(transport, :ground_station_id) || metadata_attr(transport, :antenna_id)

    snapshot = transport_metric_snapshot(snapshots, transport_id, observable_id)
    link_id = link_id_for([snapshot, transport])

    %{
      observable_id: observable_id,
      resource_id: transport_id,
      label: attr(transport, :display_name) || transport_id,
      scope_kind: :transport,
      transport_id: transport_id,
      source_endpoint_id: source_endpoint_id,
      ground_station_id: ground_station_id,
      link_id: link_id,
      adapter_key: attr(transport, :adapter_key),
      value: attr(snapshot, :value),
      unit: attr(snapshot, :unit) || "bit/s",
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id),
      source: transport
    }
  end

  defp transport_bitrate_history_row(transports, snapshot) do
    with transport when not is_nil(transport) <-
           find_transport_for_metric_snapshot(transports, snapshot),
         value when is_number(value) <- attr(snapshot, :value),
         %DateTime{} = observed_at <- attr(snapshot, :observed_at) do
      transport_id = attr(transport, :transport_id)
      link_id = link_id_for([snapshot, transport])

      %{
        observable_id: attr(snapshot, :observable_id),
        resource_id: transport_id,
        label: attr(transport, :display_name) || transport_id,
        scope_kind: :transport,
        transport_id: transport_id,
        source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
        ground_station_id: transport_ground_station_id(transport, snapshot),
        link_id: link_id,
        adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
        value: value,
        unit: attr(snapshot, :unit) || "bit/s",
        observed_at: observed_at,
        source_event_id: attr(snapshot, :source_event_id),
        source: transport
      }
    else
      _missing -> nil
    end
  end

  defp link_rf_lock_rows(transports, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_link_rf_lock_snapshot/1)

    transports
    |> Enum.map(&link_rf_lock_row(&1, snapshots))
    |> Enum.filter(&matches_connection_scope?(&1, request))
  end

  defp link_rf_lock_history_rows(transports, snapshots, request) do
    snapshots
    |> Enum.map(&normalize_link_rf_lock_snapshot/1)
    |> Enum.map(&link_rf_lock_history_row(transports, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(
      &(match?(%DateTime{}, &1.observed_at) and matches_connection_scope?(&1, request) and
          time_in_request_window?(&1.observed_at, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.observed_at))
    |> apply_request_limit(request)
  end

  defp link_rf_lock_row(transport, snapshots) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([transport])
    snapshot = link_rf_lock_snapshot(snapshots, transport_id, link_id)

    build_link_rf_lock_row(transport, snapshot)
  end

  defp link_rf_lock_history_row(transports, snapshot) do
    with transport <- find_transport_for_link_rf_snapshot(transports, snapshot),
         true <- not is_nil(transport) do
      build_link_rf_lock_row(transport, snapshot)
    else
      _missing -> nil
    end
  end

  defp build_link_rf_lock_row(transport, snapshot) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([snapshot, transport])
    state = rf_lock_state(snapshot) || rf_lock_state(attr(transport, :metadata)) || :unknown

    %{
      observable_id: "link.rf_lock_state",
      resource_id: link_id || transport_id,
      label: link_rf_lock_label(transport, link_id),
      scope_kind: :link,
      transport_id: transport_id,
      source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
      ground_station_id: transport_ground_station_id(transport, snapshot),
      link_id: link_id,
      adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
      state: state,
      normalized_state: rf_lock_normalized_state(state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: transport
    }
  end

  defp link_rf_lock_label(transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "RF lock / #{resource_label}"
  end

  defp normalize_link_rf_lock_snapshot(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: rf_lock_state(snapshot),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval)
    }
  end

  defp link_rf_lock_snapshot(snapshots, transport_id, link_id) do
    Enum.find(snapshots, fn snapshot ->
      (present_text?(transport_id) and
         (attr(snapshot, :transport_id) == transport_id or
            attr(snapshot, :resource_id) == transport_id)) or
        (present_text?(link_id) and
           (attr(snapshot, :link_id) == link_id or attr(snapshot, :resource_id) == link_id))
    end)
  end

  defp find_transport_for_link_rf_snapshot(transports, snapshot) do
    transport_id = attr(snapshot, :transport_id)
    link_id = attr(snapshot, :link_id) || attr(snapshot, :resource_id)

    Enum.find(transports, fn transport ->
      attr(transport, :transport_id) == transport_id or link_id_for([transport]) == link_id
    end)
  end

  defp rf_lock_state(value) do
    [
      attr(value, :rf_lock_state),
      attr(value, :lock_state),
      attr(value, :state),
      attr(value, :value)
    ]
    |> Enum.find_value(&normalize_rf_lock_state/1)
  end

  defp normalize_rf_lock_state(value) when value in @rf_lock_states, do: value

  defp normalize_rf_lock_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@rf_lock_states, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_rf_lock_state(_value), do: nil

  defp rf_lock_normalized_state(:locked), do: :green
  defp rf_lock_normalized_state(:acquiring), do: :blue
  defp rf_lock_normalized_state(:degraded), do: :yellow
  defp rf_lock_normalized_state(:unlocked), do: :red
  defp rf_lock_normalized_state(_state), do: :unknown

  defp link_rf_frame_sync_rows(transports, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_link_rf_frame_sync_snapshot/1)

    transports
    |> Enum.map(&link_rf_frame_sync_row(&1, snapshots))
    |> Enum.filter(&matches_connection_scope?(&1, request))
  end

  defp link_rf_frame_sync_history_rows(transports, snapshots, request) do
    snapshots
    |> Enum.map(&normalize_link_rf_frame_sync_snapshot/1)
    |> Enum.map(&link_rf_frame_sync_history_row(transports, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(
      &(match?(%DateTime{}, &1.observed_at) and matches_connection_scope?(&1, request) and
          time_in_request_window?(&1.observed_at, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.observed_at))
    |> apply_request_limit(request)
  end

  defp link_rf_frame_sync_row(transport, snapshots) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([transport])
    snapshot = link_rf_frame_sync_snapshot(snapshots, transport_id, link_id)

    build_link_rf_frame_sync_row(transport, snapshot)
  end

  defp link_rf_frame_sync_history_row(transports, snapshot) do
    with transport <- find_transport_for_link_rf_snapshot(transports, snapshot),
         true <- not is_nil(transport) do
      build_link_rf_frame_sync_row(transport, snapshot)
    else
      _missing -> nil
    end
  end

  defp build_link_rf_frame_sync_row(transport, snapshot) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([snapshot, transport])

    state =
      frame_sync_state(snapshot) || frame_sync_state(attr(transport, :metadata)) || :unknown

    %{
      observable_id: "link.frame_sync_state",
      resource_id: link_id || transport_id,
      label: link_rf_frame_sync_label(transport, link_id),
      scope_kind: :link,
      transport_id: transport_id,
      source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
      ground_station_id: transport_ground_station_id(transport, snapshot),
      link_id: link_id,
      adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
      state: state,
      normalized_state: frame_sync_normalized_state(state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: transport
    }
  end

  defp link_rf_frame_sync_label(transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "Frame sync / #{resource_label}"
  end

  defp normalize_link_rf_frame_sync_snapshot(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: frame_sync_state(snapshot),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval)
    }
  end

  defp link_rf_frame_sync_snapshot(snapshots, transport_id, link_id) do
    Enum.find(snapshots, fn snapshot ->
      (present_text?(transport_id) and
         (attr(snapshot, :transport_id) == transport_id or
            attr(snapshot, :resource_id) == transport_id)) or
        (present_text?(link_id) and
           (attr(snapshot, :link_id) == link_id or attr(snapshot, :resource_id) == link_id))
    end)
  end

  defp frame_sync_state(value) do
    [
      attr(value, :frame_sync_state),
      attr(value, :sync_state),
      attr(value, :state),
      attr(value, :value)
    ]
    |> Enum.find_value(&normalize_frame_sync_state/1)
  end

  defp normalize_frame_sync_state(value) when value in @frame_sync_states, do: value

  defp normalize_frame_sync_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@frame_sync_states, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_frame_sync_state(_value), do: nil

  defp frame_sync_normalized_state(:synchronized), do: :green
  defp frame_sync_normalized_state(:acquiring), do: :blue
  defp frame_sync_normalized_state(:degraded), do: :yellow
  defp frame_sync_normalized_state(:lost), do: :red
  defp frame_sync_normalized_state(_state), do: :unknown

  defp link_rf_metric_rows(observables, transports, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_link_rf_metric_snapshot/1)

    observables
    |> Enum.filter(&(&1 in @link_rf_metric_observable_ids))
    |> Enum.flat_map(fn observable_id ->
      Enum.map(transports, &link_rf_metric_row(observable_id, &1, snapshots))
    end)
    |> Enum.filter(&matches_connection_scope?(&1, request))
  end

  defp link_rf_metric_history_rows(observables, transports, snapshots, request) do
    observables = Enum.filter(observables, &(&1 in @link_rf_metric_observable_ids))

    rows =
      snapshots
      |> Enum.map(&normalize_link_rf_metric_snapshot/1)
      |> Enum.filter(&(attr(&1, :observable_id) in observables))
      |> Enum.map(&link_rf_metric_history_row(transports, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&metric_history_row_in_request?(&1, request))
      |> Enum.sort_by(&metric_history_sort_key/1)
      |> apply_request_limit(request)

    rows ++ empty_link_rf_metric_history_rows(observables, transports, rows, request)
  end

  defp empty_link_rf_metric_history_rows(observables, transports, rows, request) do
    present_series = MapSet.new(Enum.map(rows, &metric_history_series_key/1))

    for observable_id <- observables,
        transport <- transports,
        row = link_rf_metric_row(observable_id, transport, []),
        matches_connection_scope?(row, request),
        metric_history_series_key(row) not in present_series do
      Map.put(row, :empty_series?, true)
    end
  end

  defp link_rf_metric_row(observable_id, transport, snapshots) do
    transport_id = attr(transport, :transport_id)
    link_id = link_id_for([transport])
    snapshot = link_rf_metric_snapshot(snapshots, observable_id, transport_id, link_id)

    %{
      observable_id: observable_id,
      resource_id: link_id || transport_id,
      label: link_rf_metric_label(observable_id, transport, link_id),
      scope_kind: :link,
      transport_id: transport_id,
      source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
      ground_station_id: transport_ground_station_id(transport, snapshot),
      link_id: link_id_for([snapshot, transport]),
      adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
      value: link_rf_metric_value(snapshot, observable_id),
      unit: link_rf_metric_unit(snapshot, observable_id),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id),
      source: transport
    }
  end

  defp link_rf_metric_history_row(transports, snapshot) do
    observable_id = attr(snapshot, :observable_id)

    with transport when not is_nil(transport) <-
           find_transport_for_link_rf_snapshot(transports, snapshot),
         value when is_number(value) <- link_rf_metric_value(snapshot, observable_id),
         %DateTime{} = observed_at <- attr(snapshot, :observed_at) do
      transport_id = attr(transport, :transport_id)
      link_id = link_id_for([snapshot, transport])

      %{
        observable_id: observable_id,
        resource_id: link_id || transport_id,
        label: link_rf_metric_label(observable_id, transport, link_id),
        scope_kind: :link,
        transport_id: transport_id,
        source_endpoint_id: transport_source_endpoint_id(transport, snapshot),
        ground_station_id: transport_ground_station_id(transport, snapshot),
        link_id: link_id,
        adapter_key: attr(snapshot, :adapter_key) || attr(transport, :adapter_key),
        value: value,
        unit: link_rf_metric_unit(snapshot, observable_id),
        observed_at: observed_at,
        source_event_id: attr(snapshot, :source_event_id),
        source: transport
      }
    else
      _missing -> nil
    end
  end

  defp normalize_link_rf_metric_snapshot(snapshot) do
    %{
      observable_id: link_rf_metric_observable_id(snapshot),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: attr(snapshot, :value),
      snr_db: attr(snapshot, :snr_db),
      snr: attr(snapshot, :snr),
      signal_to_noise_ratio_db: attr(snapshot, :signal_to_noise_ratio_db),
      eb_n0_db: attr(snapshot, :eb_n0_db),
      ebn0_db: attr(snapshot, :ebn0_db),
      energy_per_bit_to_noise_density_db: attr(snapshot, :energy_per_bit_to_noise_density_db),
      symbol_rate_sps: attr(snapshot, :symbol_rate_sps),
      symbol_rate: attr(snapshot, :symbol_rate),
      symbols_per_second: attr(snapshot, :symbols_per_second),
      doppler_hz: attr(snapshot, :doppler_hz),
      doppler: attr(snapshot, :doppler),
      frequency_offset_hz: attr(snapshot, :frequency_offset_hz),
      carrier_frequency_offset_hz: attr(snapshot, :carrier_frequency_offset_hz),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
    }
  end

  defp link_rf_metric_observable_id(snapshot) do
    attr(snapshot, :observable_id) ||
      cond do
        Enum.any?(
          [:eb_n0_db, :ebn0_db, :energy_per_bit_to_noise_density_db],
          &present_metric?(snapshot, &1)
        ) ->
          "link.eb_n0_db"

        Enum.any?(
          [:symbol_rate_sps, :symbol_rate, :symbols_per_second],
          &present_metric?(snapshot, &1)
        ) ->
          "link.symbol_rate_sps"

        Enum.any?(
          [:doppler_hz, :doppler, :frequency_offset_hz, :carrier_frequency_offset_hz],
          &present_metric?(snapshot, &1)
        ) ->
          "link.doppler_hz"

        Enum.any?(
          [:snr_db, :snr, :signal_to_noise_ratio_db, :value],
          &present_metric?(snapshot, &1)
        ) ->
          "link.snr_db"

        true ->
          nil
      end
  end

  defp present_metric?(snapshot, key), do: not is_nil(attr(snapshot, key))

  defp link_rf_metric_snapshot(snapshots, observable_id, transport_id, link_id) do
    Enum.find(snapshots, fn snapshot ->
      attr(snapshot, :observable_id) == observable_id and
        ((present_text?(transport_id) and
            (attr(snapshot, :transport_id) == transport_id or
               attr(snapshot, :resource_id) == transport_id)) or
           (present_text?(link_id) and
              (attr(snapshot, :link_id) == link_id or attr(snapshot, :resource_id) == link_id)))
    end)
  end

  defp link_rf_metric_label("link.snr_db", transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "RF SNR / #{resource_label}"
  end

  defp link_rf_metric_label("link.eb_n0_db", transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "RF Eb/N0 / #{resource_label}"
  end

  defp link_rf_metric_label("link.symbol_rate_sps", transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "RF Symbol Rate / #{resource_label}"
  end

  defp link_rf_metric_label("link.doppler_hz", transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "RF Doppler / #{resource_label}"
  end

  defp link_rf_metric_label(observable_id, transport, link_id) do
    resource_label = link_id || attr(transport, :display_name) || attr(transport, :transport_id)
    "#{observable_id} / #{resource_label}"
  end

  defp link_rf_metric_value(snapshot, "link.snr_db") do
    [
      attr(snapshot, :snr_db),
      attr(snapshot, :signal_to_noise_ratio_db),
      attr(snapshot, :snr),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp link_rf_metric_value(snapshot, "link.eb_n0_db") do
    [
      attr(snapshot, :eb_n0_db),
      attr(snapshot, :ebn0_db),
      attr(snapshot, :energy_per_bit_to_noise_density_db),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp link_rf_metric_value(snapshot, "link.symbol_rate_sps") do
    [
      attr(snapshot, :symbol_rate_sps),
      attr(snapshot, :symbols_per_second),
      attr(snapshot, :symbol_rate),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp link_rf_metric_value(snapshot, "link.doppler_hz") do
    [
      attr(snapshot, :doppler_hz),
      attr(snapshot, :frequency_offset_hz),
      attr(snapshot, :carrier_frequency_offset_hz),
      attr(snapshot, :doppler),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp link_rf_metric_value(snapshot, _observable_id), do: attr(snapshot, :value)

  defp link_rf_metric_unit(snapshot, "link.snr_db"), do: attr(snapshot, :unit) || "dB"
  defp link_rf_metric_unit(snapshot, "link.eb_n0_db"), do: attr(snapshot, :unit) || "dB"
  defp link_rf_metric_unit(snapshot, "link.symbol_rate_sps"), do: attr(snapshot, :unit) || "sym/s"
  defp link_rf_metric_unit(snapshot, "link.doppler_hz"), do: attr(snapshot, :unit) || "Hz"
  defp link_rf_metric_unit(snapshot, _observable_id), do: attr(snapshot, :unit)

  defp normalize_ingress_processing_latency_snapshot(snapshot) do
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
      value: ingress_processing_latency_value(snapshot),
      unit: attr(snapshot, :unit) || "ms",
      observed_at: attr(snapshot, :observed_at),
      error?: attr(snapshot, :error?) || false,
      replay_run_id: attr(snapshot, :replay_run_id),
      source_event_id: attr(snapshot, :source_event_id),
      source: snapshot
    }
  end

  defp ingress_processing_latency_row(snapshot, request, opts) do
    source_endpoint_id = attr(snapshot, :source_endpoint_id)
    resource_id = source_endpoint_id || attr(snapshot, :mission_id)
    freshness = row_freshness(attr(snapshot, :observed_at), request, opts)

    %{
      observable_id: "ingress.processing_latency_ms",
      resource_id: resource_id,
      label: ingress_processing_latency_label(source_endpoint_id, attr(snapshot, :mission_id)),
      scope_kind: ingress_processing_latency_scope_kind(source_endpoint_id),
      source_endpoint_id: source_endpoint_id,
      transport_id: attr(snapshot, :transport_id),
      ground_station_id: attr(snapshot, :ground_station_id),
      link_id: attr(snapshot, :link_id),
      contact_id: attr(snapshot, :contact_id),
      adapter_key: attr(snapshot, :adapter_key),
      spacecraft_id: attr(snapshot, :spacecraft_id),
      value: attr(snapshot, :value),
      unit: attr(snapshot, :unit) || "ms",
      observed_at: attr(snapshot, :observed_at),
      freshness_state: freshness.state,
      age_ms: freshness.age_ms,
      freshness_policy: freshness.policy,
      freshness_checked_at: freshness.checked_at,
      error?: attr(snapshot, :error?) || false,
      source_event_id: attr(snapshot, :source_event_id),
      source: attr(snapshot, :source) || snapshot
    }
  end

  defp ingress_processing_latency_history_row(snapshot) do
    with value when is_number(value) <- attr(snapshot, :value),
         %DateTime{} = observed_at <- attr(snapshot, :observed_at) do
      source_endpoint_id = attr(snapshot, :source_endpoint_id)
      resource_id = source_endpoint_id || attr(snapshot, :mission_id)

      %{
        observable_id: "ingress.processing_latency_ms",
        resource_id: resource_id,
        label: ingress_processing_latency_label(source_endpoint_id, attr(snapshot, :mission_id)),
        scope_kind: ingress_processing_latency_scope_kind(source_endpoint_id),
        source_endpoint_id: source_endpoint_id,
        transport_id: attr(snapshot, :transport_id),
        ground_station_id: attr(snapshot, :ground_station_id),
        link_id: attr(snapshot, :link_id),
        contact_id: attr(snapshot, :contact_id),
        adapter_key: attr(snapshot, :adapter_key),
        spacecraft_id: attr(snapshot, :spacecraft_id),
        value: value,
        unit: attr(snapshot, :unit) || "ms",
        observed_at: observed_at,
        source_event_id: attr(snapshot, :source_event_id),
        source: attr(snapshot, :source) || snapshot
      }
    else
      _missing -> nil
    end
  end

  defp empty_ingress_processing_latency_history_rows(rows, request, mission_id) do
    present_series = MapSet.new(Enum.map(rows, &metric_history_series_key/1))

    request
    |> ingress_processing_latency_empty_series_candidates(mission_id)
    |> Enum.reject(&(metric_history_series_key(&1) in present_series))
    |> Enum.map(&Map.put(&1, :empty_series?, true))
  end

  defp ingress_processing_latency_empty_series_candidates(request, mission_id) do
    request
    |> scope_ids(:source_endpoint)
    |> Enum.map(fn source_endpoint_id ->
      %{
        observable_id: "ingress.processing_latency_ms",
        resource_id: source_endpoint_id,
        label: ingress_processing_latency_label(source_endpoint_id, mission_id),
        scope_kind: :source_endpoint,
        source_endpoint_id: source_endpoint_id,
        transport_id: nil,
        ground_station_id: nil,
        link_id: nil,
        contact_id: nil,
        adapter_key: nil,
        spacecraft_id: nil,
        value: nil,
        unit: "ms",
        observed_at: nil
      }
    end)
  end

  defp annotate_latest_freshness(rows, request, opts) do
    Enum.map(rows, &put_latest_freshness(&1, request, opts))
  end

  defp put_latest_freshness(row, request, opts) when is_map(row) do
    observed_at = row_observed_at(row)
    freshness = row_freshness(observed_at, request, opts)

    row
    |> Map.put(:observed_at, observed_at)
    |> Map.put(:freshness_state, freshness.state)
    |> Map.put(:age_ms, freshness.age_ms)
    |> Map.put(:freshness_policy, freshness.policy)
    |> Map.put(:freshness_checked_at, freshness.checked_at)
  end

  defp row_observed_at(row) do
    case attr(row, :observed_at) || attr(row, :time) do
      %DateTime{} = observed_at -> observed_at
      _other -> nil
    end
  end

  defp row_freshness(observed_at, request, opts) do
    policy =
      SourceFreshness.resolve_policy([
        Keyword.get(opts, :freshness_policy),
        context_value(request.sampling, :freshness_policy),
        context_value(request.data_context, :freshness_policy)
      ])

    checked_at = Keyword.get_lazy(opts, :freshness_now, &DateTime.utc_now/0)
    age_ms = metric_age_ms(observed_at, checked_at)

    %{
      state: metric_freshness_state(observed_at, age_ms, policy),
      age_ms: age_ms,
      policy: policy,
      checked_at: checked_at
    }
  end

  defp latest_freshness_warning_codes(rows) do
    rows
    |> Enum.map(& &1.freshness_state)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      :stale -> [:stale_data]
      :missing -> [:missing_snapshot]
      :unknown -> [:watermark_unknown]
      _state -> []
    end)
    |> Enum.uniq()
  end

  defp latest_freshness_policy([%{freshness_policy: policy} | _rows]), do: policy
  defp latest_freshness_policy(_rows), do: %{}

  defp latest_freshness_checked_at([%{freshness_checked_at: %DateTime{} = checked_at} | _rows]),
    do: checked_at

  defp latest_freshness_checked_at(_rows), do: nil

  defp metric_age_ms(%DateTime{} = observed_at, %DateTime{} = checked_at) do
    max(DateTime.diff(checked_at, observed_at, :millisecond), 0)
  end

  defp metric_age_ms(_observed_at, _checked_at), do: nil

  defp metric_freshness_state(nil, _age_ms, _policy), do: :missing

  defp metric_freshness_state(_observed_at, age_ms, %{stale_after_ms: stale_after_ms})
       when is_integer(age_ms) and is_integer(stale_after_ms) and stale_after_ms >= 0 and
              age_ms > stale_after_ms,
       do: :stale

  defp metric_freshness_state(_observed_at, _age_ms, _policy), do: :fresh

  defp ingress_processing_latency_value(snapshot) do
    [
      attr(snapshot, :value),
      attr(snapshot, :latency_ms),
      attr(snapshot, :processing_latency_ms),
      attr(snapshot, :end_to_end_ms)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp ingress_processing_latency_scope_kind(source_endpoint_id)
       when is_binary(source_endpoint_id) and source_endpoint_id != "",
       do: :source_endpoint

  defp ingress_processing_latency_scope_kind(_source_endpoint_id), do: :mission

  defp ingress_processing_latency_label(source_endpoint_id, _mission_id)
       when is_binary(source_endpoint_id) and source_endpoint_id != "" do
    "Ingress latency / #{source_endpoint_id}"
  end

  defp ingress_processing_latency_label(_source_endpoint_id, _mission_id), do: "Ingress latency"

  defp normalize_transport_metric_snapshots(snapshot) do
    base = %{
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
    }

    snapshot
    |> transport_metric_observable_ids()
    |> Enum.map(fn observable_id ->
      base
      |> Map.put(:observable_id, observable_id)
      |> Map.put(:value, transport_metric_value(snapshot, observable_id))
    end)
  end

  defp transport_metric_snapshot(snapshots, transport_id, observable_id)
       when is_binary(transport_id) and transport_id != "" do
    Enum.find(
      snapshots,
      &((attr(&1, :transport_id) == transport_id or attr(&1, :resource_id) == transport_id) and
          attr(&1, :observable_id) == observable_id)
    )
  end

  defp transport_metric_snapshot(_snapshots, _transport_id, _observable_id), do: nil

  defp transport_metric_observable_ids(snapshot) do
    case attr(snapshot, :observable_id) do
      observable_id when observable_id in @bitrate_observable_ids ->
        [observable_id]

      _observable_id ->
        inferred =
          [
            {"comms.transport.downlink_bitrate",
             transport_metric_value(snapshot, "comms.transport.downlink_bitrate")},
            {"comms.transport.uplink_bitrate",
             transport_metric_value(snapshot, "comms.transport.uplink_bitrate")}
          ]
          |> Enum.filter(fn {_observable_id, value} -> is_number(value) end)
          |> Enum.map(fn {observable_id, _value} -> observable_id end)

        case inferred do
          [] -> ["comms.transport.downlink_bitrate"]
          observable_ids -> observable_ids
        end
    end
  end

  defp transport_metric_value(snapshot, "comms.transport.uplink_bitrate") do
    [
      attr(snapshot, :uplink_bitrate),
      attr(snapshot, :uplink_bitrate_bps),
      attr(snapshot, :bitrate),
      attr(snapshot, :bit_rate),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp transport_metric_value(snapshot, _observable_id) do
    [
      attr(snapshot, :downlink_bitrate),
      attr(snapshot, :downlink_bitrate_bps),
      attr(snapshot, :bitrate),
      attr(snapshot, :bit_rate),
      attr(snapshot, :value)
    ]
    |> Enum.find_value(&normalize_number/1)
  end

  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value

  defp normalize_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp normalize_number(_value), do: nil

  defp transport_execution_history_rows(
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    intervals_fun =
      Keyword.get(
        opts,
        :transport_execution_intervals_fun,
        &default_transport_execution_intervals/3
      )

    intervals_fun.(organization_id, mission_id, adapter_opts(request, source_binding))
    |> Enum.map(&transport_execution_history_row/1)
    |> Enum.filter(
      &(matches_transport_execution_scope?(&1, request) and
          interval_overlaps_request?(&1, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.starts_at))
    |> apply_request_limit(request)
  end

  defp transport_execution_history_row(interval) do
    payload = attr(interval, :payload) || %{}
    transport_id = attr(interval, :subject_id) || attr(payload, :capability_instance_id)
    state = transport_execution_state(attr(payload, :event_kind))

    %{
      observable_id: "comms.transport.execution_state",
      resource_id: transport_id,
      lane_id: transport_id,
      label: "Transport execution / #{transport_id}",
      scope_kind: :transport,
      transport_id: transport_id,
      source_endpoint_id:
        attr(payload, :source_endpoint_id) || attr(payload, :source_endpoint_ref),
      ground_station_id: attr(payload, :ground_station_id) || attr(payload, :antenna_id),
      link_id: attr(payload, :link_id) || attr(payload, :link_assignment_id),
      contact_id: attr(payload, :contact_id) || attr(payload, :realized_contact_id),
      path_id: attr(payload, :path_id),
      transport_record_id: attr(payload, :transport_record_id),
      interval_id: attr(interval, :interval_id),
      source_event_id: attr(interval, :source_event_id),
      state: state,
      normalized_state: state,
      starts_at: attr(interval, :starts_at),
      ends_at: attr(interval, :ends_at),
      interval: interval
    }
  end

  defp transport_runtime_activity_history_frame(request, source_binding, rows) do
    %Frame{
      frame_id: "#{request.request_id}:transport_runtime_activity_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: Enum.map(rows, & &1.starts_at),
          metadata: %{axis: :occurred_at}
        },
        %Field{
          name: "observable_id",
          kind: :string,
          values: Enum.map(rows, & &1.observable_id)
        },
        %Field{name: "resource_id", kind: :string, values: Enum.map(rows, & &1.resource_id)},
        %Field{name: "lane_id", kind: :string, values: Enum.map(rows, & &1.lane_id)},
        %Field{name: "label", kind: :string, values: Enum.map(rows, & &1.label)},
        %Field{name: "scope_kind", kind: :enum, values: Enum.map(rows, & &1.scope_kind)},
        %Field{name: "transport_id", kind: :string, values: Enum.map(rows, & &1.transport_id)},
        %Field{name: "contact_id", kind: :string, values: Enum.map(rows, & &1.contact_id)},
        %Field{name: "path_id", kind: :string, values: Enum.map(rows, & &1.path_id)},
        %Field{
          name: "source_endpoint_ref",
          kind: :string,
          values: Enum.map(rows, & &1.source_endpoint_ref)
        },
        %Field{
          name: "capability_instance_id",
          kind: :string,
          values: Enum.map(rows, & &1.capability_instance_id)
        },
        %Field{name: "family_key", kind: :enum, values: Enum.map(rows, & &1.family_key)},
        %Field{name: "activation_id", kind: :string, values: Enum.map(rows, & &1.activation_id)},
        %Field{
          name: "binding_set_id",
          kind: :string,
          values: Enum.map(rows, & &1.binding_set_id)
        },
        %Field{name: "timer_key", kind: :string, values: Enum.map(rows, & &1.timer_key)},
        %Field{name: "action_kind", kind: :enum, values: Enum.map(rows, & &1.action_kind)},
        %Field{
          name: "command_release_attempt_id",
          kind: :string,
          values: Enum.map(rows, & &1.command_release_attempt_id)
        },
        %Field{
          name: "command_request_id",
          kind: :string,
          values: Enum.map(rows, & &1.command_request_id)
        },
        %Field{
          name: "command_verifier_instance_ids",
          kind: :string,
          values: Enum.map(rows, & &1.command_verifier_instance_ids)
        },
        %Field{
          name: "command_verification_state",
          kind: :enum,
          values: Enum.map(rows, & &1.command_verification_state)
        },
        %Field{
          name: "command_verifier_lifecycle_states",
          kind: :string,
          values: Enum.map(rows, & &1.command_verifier_lifecycle_states)
        },
        %Field{
          name: "command_verifier_matched_record_ids",
          kind: :string,
          values: Enum.map(rows, & &1.command_verifier_matched_record_ids)
        },
        %Field{
          name: "command_verifier_failure_reasons",
          kind: :string,
          values: Enum.map(rows, & &1.command_verifier_failure_reasons)
        },
        %Field{name: "command_name", kind: :string, values: Enum.map(rows, & &1.command_name)},
        %Field{name: "signal_phase", kind: :enum, values: Enum.map(rows, & &1.signal_phase)},
        %Field{
          name: "action_request_document_json",
          kind: :string,
          values: Enum.map(rows, & &1.action_request_document_json)
        },
        %Field{
          name: "record_event_kind",
          kind: :enum,
          values: Enum.map(rows, & &1.record_event_kind)
        },
        %Field{
          name: "emitted_record_kinds",
          kind: :string,
          values: Enum.map(rows, & &1.emitted_record_kinds)
        },
        %Field{
          name: "emitted_record_count",
          kind: :number,
          values: Enum.map(rows, & &1.emitted_record_count)
        },
        %Field{
          name: "action_request_count",
          kind: :number,
          values: Enum.map(rows, & &1.action_request_count)
        },
        %Field{
          name: "state_snapshot_json",
          kind: :string,
          values: Enum.map(rows, & &1.state_snapshot_json)
        },
        %Field{
          name: "record_metadata_json",
          kind: :string,
          values: Enum.map(rows, & &1.record_metadata_json)
        },
        %Field{
          name: "runtime_fact_kind",
          kind: :enum,
          values: Enum.map(rows, & &1.runtime_fact_kind)
        },
        %Field{
          name: "runtime_fact_id",
          kind: :string,
          values: Enum.map(rows, & &1.runtime_fact_id)
        },
        %Field{
          name: "source_event_id",
          kind: :string,
          values: Enum.map(rows, & &1.source_event_id)
        },
        %Field{name: "state", kind: :enum, values: Enum.map(rows, & &1.state)},
        %Field{
          name: "normalized_state",
          kind: :enum,
          values: Enum.map(rows, & &1.normalized_state)
        }
      ],
      meta: %{
        source_request_id: request.request_id,
        logical_source: :operational_observables,
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        sampling: :event_history,
        supported_capability: :transport_runtime_activity_history,
        product_family: :runtime_transport,
        state_color_policy: :transport_runtime_activity,
        observable_ids: observable_ids(rows),
        observable_id: "runtime.transport_activity",
        realm: realm(request, source_binding),
        data_source_id: data_source_id(request, source_binding),
        replay_run_id: replay_run_id(request),
        runtime_fact_ids: managed_runtime_fact_ids(rows),
        returned_points: length(rows),
        warning_codes: [],
        links: operational_history_links(request, rows),
        evidence_refs:
          rows
          |> DataLinks.operational_event_evidence_refs(source: :operational_observables)
          |> Kernel.++(
            DataLinks.command_release_attempt_evidence_refs(rows,
              source: :operational_observables
            )
          )
          |> Kernel.++(
            rows
            |> Enum.flat_map(& &1.command_verifier_instances)
            |> DataLinks.command_verifier_instance_evidence_refs(source: :operational_observables)
          )
          |> Kernel.++(
            rows
            |> Enum.flat_map(& &1.command_verifier_instances)
            |> DataLinks.command_verifier_matched_record_evidence_refs(
              source: :operational_observables
            )
          )
          |> Enum.uniq_by(&{&1.kind, &1.id})
      }
    }
  end

  defp managed_runtime_activity_history_rows(
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    managed_runtime_events_fun =
      Keyword.get(opts, :managed_runtime_events_fun, &default_managed_runtime_events/3)

    managed_runtime_events_fun.(
      organization_id,
      mission_id,
      adapter_opts(request, source_binding)
    )
    |> Enum.filter(&matches_managed_runtime_activity_scope?(&1, request))
    |> Enum.map(&managed_runtime_activity_history_row/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&time_in_request_window?(&1.starts_at, request))
    |> Enum.sort_by(&datetime_sort_key(&1.starts_at))
    |> apply_request_limit(request)
  end

  defp managed_runtime_activity_history_row(event) do
    payload = attr(event, :payload) || attr(event, :current) || %{}
    causality = attr(event, :causality) || %{}
    source_record_kind = attr(causality, :source_record_kind)
    source_record_id = attr(causality, :source_record_id)
    event_kind = attr(event, :kind)

    capability_instance_id =
      attr(payload, :capability_instance_id) || managed_event_subject_id(event)

    occurred_at = attr(event, :occurred_at)

    if is_nil(occurred_at) do
      nil
    else
      %{
        observable_id: "runtime.managed_activity",
        resource_id: capability_instance_id,
        lane_id: capability_instance_id,
        label: managed_runtime_activity_label(capability_instance_id),
        scope_kind: :mission,
        capability_instance_id: capability_instance_id,
        family_key: attr(payload, :family_key),
        activation_id: attr(payload, :activation_id),
        binding_set_id: attr(payload, :binding_set_id),
        packet_id: attr(payload, :packet_id),
        evidence_id: attr(payload, :evidence_id),
        timer_key: attr(payload, :timer_key),
        action_kind: attr(payload, :action_kind),
        action_request_document_json: deterministic_json(attr(payload, :request_document)),
        record_event_kind: attr(payload, :event_kind),
        emitted_record_kinds: emitted_record_kinds_text(attr(payload, :emitted_record_kinds)),
        emitted_record_count: attr(payload, :emitted_record_count),
        action_request_count: attr(payload, :action_request_count),
        state_snapshot_json: deterministic_json(attr(payload, :state_snapshot)),
        record_metadata_json: deterministic_json(attr(payload, :record_metadata)),
        runtime_fact_kind: source_record_kind,
        runtime_fact_id: source_record_id,
        source_event_id: attr(event, :event_id),
        state: event_kind,
        normalized_state: event_kind,
        starts_at: occurred_at,
        event: event
      }
    end
  end

  defp transport_runtime_activity_history_rows(
         request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    transport_runtime_events_fun =
      Keyword.get(opts, :transport_runtime_events_fun, &default_transport_runtime_events/3)

    adapter_opts = adapter_opts(request, source_binding)

    rows =
      transport_runtime_events_fun.(
        organization_id,
        mission_id,
        adapter_opts
      )
      |> Enum.filter(&matches_transport_runtime_activity_scope?(&1, request))
      |> Enum.map(&transport_runtime_activity_history_row/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&time_in_request_window?(&1.starts_at, request))
      |> Enum.sort_by(&datetime_sort_key(&1.starts_at))
      |> apply_request_limit(request)

    command_verifier_instances_fun =
      Keyword.get(
        opts,
        :command_verifier_instances_fun,
        &default_command_verifier_instances/3
      )

    command_verifier_instances =
      command_verifier_instances_fun.(
        organization_id,
        mission_id,
        Keyword.put(
          adapter_opts,
          :command_release_attempt_ids,
          command_release_attempt_ids(rows)
        )
      )

    attach_command_verifier_outcomes(rows, command_verifier_instances)
  end

  defp transport_runtime_activity_history_row(event) do
    payload = attr(event, :payload) || attr(event, :current) || %{}
    causality = attr(event, :causality) || %{}
    source_record_kind = attr(causality, :source_record_kind)
    source_record_id = attr(causality, :source_record_id)
    event_kind = attr(event, :kind)
    transport_id = attr(payload, :capability_instance_id) || managed_event_subject_id(event)
    occurred_at = attr(event, :occurred_at)

    if is_nil(occurred_at) do
      nil
    else
      %{
        observable_id: "runtime.transport_activity",
        resource_id: transport_id,
        lane_id: transport_id,
        label: transport_runtime_activity_label(transport_id),
        scope_kind: :transport,
        transport_id: transport_id,
        contact_id: attr(payload, :contact_id) || attr(payload, :realized_contact_id),
        path_id: attr(payload, :path_id),
        source_endpoint_ref: attr(payload, :source_endpoint_ref),
        capability_instance_id: transport_id,
        family_key: attr(payload, :family_key),
        activation_id: attr(payload, :activation_id),
        binding_set_id: attr(payload, :binding_set_id),
        timer_key: attr(payload, :timer_key),
        action_kind: attr(payload, :action_kind),
        command_release_attempt_id: attr(payload, :command_release_attempt_id),
        command_request_id: attr(payload, :command_request_id),
        command_verifier_instances: [],
        command_verifier_instance_ids: nil,
        command_verification_state: nil,
        command_verifier_lifecycle_states: nil,
        command_verifier_matched_record_ids: nil,
        command_verifier_failure_reasons: nil,
        command_name: attr(payload, :command_name),
        signal_phase: attr(payload, :signal_phase),
        action_request_document_json: deterministic_json(attr(payload, :request_document)),
        record_event_kind: attr(payload, :event_kind),
        emitted_record_kinds: emitted_record_kinds_text(attr(payload, :emitted_record_kinds)),
        emitted_record_count: attr(payload, :emitted_record_count),
        action_request_count: attr(payload, :action_request_count),
        state_snapshot_json: deterministic_json(attr(payload, :state_snapshot)),
        record_metadata_json:
          deterministic_json(
            attr(payload, :record_metadata) ||
              attr(payload, :action_metadata) ||
              attr(payload, :timer_metadata)
          ),
        runtime_fact_kind: source_record_kind,
        runtime_fact_id: source_record_id,
        source_event_id: attr(event, :event_id),
        state: event_kind,
        normalized_state: event_kind,
        starts_at: occurred_at,
        event: event
      }
    end
  end

  defp managed_runtime_activity_label(capability_instance_id)
       when is_binary(capability_instance_id) and capability_instance_id != "" do
    "Managed runtime / #{capability_instance_id}"
  end

  defp managed_runtime_activity_label(_capability_instance_id), do: "Managed runtime"

  defp transport_runtime_activity_label(transport_id)
       when is_binary(transport_id) and transport_id != "" do
    "Transport runtime / #{transport_id}"
  end

  defp transport_runtime_activity_label(_transport_id), do: "Transport runtime"

  defp managed_event_subject_id(event) do
    event
    |> attr(:subject)
    |> attr(:id)
  end

  defp emitted_record_kinds_text(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp emitted_record_kinds_text(_values), do: nil

  defp deterministic_json(value) when is_map(value) and map_size(value) > 0 do
    value
    |> JsonDocument.encode()
    |> Jason.encode!()
  end

  defp deterministic_json(_value), do: nil

  defp attach_command_verifier_outcomes(rows, command_verifier_instances)
       when is_list(rows) and is_list(command_verifier_instances) do
    verifier_instances_by_release_attempt_id =
      command_verifier_instances
      |> Enum.sort_by(&command_verifier_sort_key/1)
      |> Enum.group_by(&attr(&1, :command_release_attempt_id))

    Enum.map(rows, fn row ->
      verifier_instances =
        Map.get(
          verifier_instances_by_release_attempt_id,
          row.command_release_attempt_id,
          []
        )

      %{
        row
        | command_verifier_instances: verifier_instances,
          command_verifier_instance_ids:
            joined_attr_values(verifier_instances, :command_verifier_instance_id),
          command_verification_state: command_verification_state(verifier_instances),
          command_verifier_lifecycle_states:
            joined_attr_values(verifier_instances, :lifecycle_state),
          command_verifier_matched_record_ids:
            joined_attr_values(verifier_instances, :matched_record_id),
          command_verifier_failure_reasons:
            joined_attr_values(verifier_instances, :failure_reason)
      }
    end)
  end

  defp command_release_attempt_ids(rows) when is_list(rows) do
    rows
    |> Enum.map(& &1.command_release_attempt_id)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp command_release_attempt_ids_from_events(events) when is_list(events) do
    events
    |> Enum.map(fn event ->
      event
      |> then(&(attr(&1, :payload) || attr(&1, :current)))
      |> attr(:command_release_attempt_id)
    end)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp command_verifier_sort_key(verifier_instance) do
    {
      datetime_sort_key(attr(verifier_instance, :matched_at)),
      attr(verifier_instance, :command_verifier_instance_id) || ""
    }
  end

  defp joined_attr_values(items, key) when is_list(items) do
    items
    |> Enum.map(&attr(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> nil
      values -> Enum.join(values, ",")
    end
  end

  defp command_verification_state([]), do: nil

  defp command_verification_state(verifier_instances) when is_list(verifier_instances) do
    lifecycle_states = Enum.map(verifier_instances, &attr(&1, :lifecycle_state))

    cond do
      Enum.any?(lifecycle_states, &(&1 in [:failed, "failed"])) -> :failed
      Enum.any?(lifecycle_states, &(&1 in [:timed_out, "timed_out"])) -> :timed_out
      Enum.any?(lifecycle_states, &(&1 in [:pending, "pending"])) -> :pending
      Enum.all?(lifecycle_states, &(&1 in [:satisfied, "satisfied"])) -> :satisfied
      true -> nil
    end
  end

  defp managed_runtime_fact_ids(rows) do
    rows
    |> Enum.map(& &1.runtime_fact_id)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp transport_source_endpoint_id(transport, snapshot) do
    attr(snapshot, :source_endpoint_id) ||
      metadata_attr(transport, :source_endpoint_id) ||
      metadata_attr(transport, :source_endpoint_ref)
  end

  defp transport_ground_station_id(transport, snapshot) do
    attr(snapshot, :ground_station_id) ||
      metadata_attr(transport, :ground_station_id) ||
      metadata_attr(transport, :antenna_id)
  end

  defp find_transport_for_metric_snapshot(transports, snapshot) do
    transport_id = attr(snapshot, :transport_id)
    link_id = attr(snapshot, :link_id) || attr(snapshot, :resource_id)

    Enum.find(transports, fn transport ->
      attr(transport, :transport_id) == transport_id or
        (present_text?(link_id) and link_id_for([transport]) == link_id)
    end)
  end

  defp find_source_endpoint(source_endpoints, source_endpoint_id, ground_station_id) do
    Enum.find(source_endpoints, fn source_endpoint ->
      attr(source_endpoint, :source_endpoint_id) == source_endpoint_id or
        metadata_attr(source_endpoint, :ground_station_id) == ground_station_id or
        metadata_attr(source_endpoint, :antenna_id) == ground_station_id
    end)
  end

  defp antenna_pointing_rows(source_endpoints, snapshots, request) do
    snapshots = Enum.map(snapshots, &normalize_antenna_pointing_snapshot/1)

    source_endpoints
    |> Enum.map(&antenna_pointing_row(&1, snapshots))
    |> Enum.filter(&matches_connection_scope?(&1, request))
  end

  defp antenna_pointing_history_rows(source_endpoints, snapshots, request) do
    snapshots
    |> Enum.map(&normalize_antenna_pointing_snapshot/1)
    |> Enum.map(&antenna_pointing_history_row(source_endpoints, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(
      &(match?(%DateTime{}, &1.observed_at) and matches_connection_scope?(&1, request) and
          time_in_request_window?(&1.observed_at, request))
    )
    |> Enum.sort_by(&datetime_sort_key(&1.observed_at))
    |> apply_request_limit(request)
  end

  defp antenna_pointing_row(source_endpoint, snapshots) do
    source_endpoint_id = attr(source_endpoint, :source_endpoint_id)

    ground_station_id =
      metadata_attr(source_endpoint, :ground_station_id) ||
        metadata_attr(source_endpoint, :antenna_id)

    snapshot =
      antenna_pointing_snapshot(
        snapshots,
        source_endpoint_id,
        ground_station_id
      )

    build_antenna_pointing_row(source_endpoint, snapshot)
  end

  defp antenna_pointing_history_row(source_endpoints, snapshot) do
    source_endpoint =
      find_source_endpoint(
        source_endpoints,
        attr(snapshot, :source_endpoint_id),
        attr(snapshot, :ground_station_id) || attr(snapshot, :resource_id)
      )

    if source_endpoint do
      build_antenna_pointing_row(source_endpoint, snapshot)
    end
  end

  defp build_antenna_pointing_row(source_endpoint, snapshot) do
    source_endpoint_id = attr(source_endpoint, :source_endpoint_id)

    ground_station_id =
      attr(snapshot, :ground_station_id) ||
        metadata_attr(source_endpoint, :ground_station_id) ||
        metadata_attr(source_endpoint, :antenna_id)

    resource_id = ground_station_id || source_endpoint_id

    state =
      antenna_pointing_state(snapshot) || antenna_pointing_state(attr(source_endpoint, :metadata)) ||
        :unknown

    link_id = link_id_for([snapshot, source_endpoint])

    %{
      observable_id: "ground.station.antenna_pointing_state",
      resource_id: resource_id,
      label: "Antenna pointing / #{attr(source_endpoint, :display_name) || resource_id}",
      scope_kind: :ground_station,
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id: source_endpoint_id,
      ground_station_id: ground_station_id,
      link_id: link_id,
      adapter_key: attr(snapshot, :adapter_key) || attr(source_endpoint, :adapter_key),
      state: state,
      normalized_state: antenna_pointing_normalized_state(state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval),
      source: source_endpoint
    }
  end

  defp normalize_antenna_pointing_snapshot(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      state: antenna_pointing_state(snapshot),
      normalized_state: attr(snapshot, :normalized_state),
      observed_at: attr(snapshot, :observed_at),
      interval_id: attr(snapshot, :interval_id),
      source_event_id: attr(snapshot, :source_event_id),
      interval: attr(snapshot, :interval)
    }
  end

  defp antenna_pointing_snapshot(snapshots, source_endpoint_id, ground_station_id) do
    Enum.find(snapshots, fn snapshot ->
      attr(snapshot, :observable_id) in [nil, "ground.station.antenna_pointing_state"] and
        ((present_text?(source_endpoint_id) and
            (attr(snapshot, :source_endpoint_id) == source_endpoint_id or
               attr(snapshot, :resource_id) == source_endpoint_id)) or
           (present_text?(ground_station_id) and
              (attr(snapshot, :ground_station_id) == ground_station_id or
                 attr(snapshot, :resource_id) == ground_station_id)))
    end)
  end

  defp antenna_pointing_state(value) do
    [
      attr(value, :antenna_pointing_state),
      attr(value, :pointing_state),
      attr(value, :acquisition_state),
      attr(value, :state),
      attr(value, :value)
    ]
    |> Enum.find_value(&normalize_antenna_pointing_state/1)
  end

  defp normalize_antenna_pointing_state(value) when value in @antenna_pointing_states,
    do: value

  defp normalize_antenna_pointing_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@antenna_pointing_states, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_antenna_pointing_state(_value), do: nil

  defp antenna_pointing_normalized_state(:tracking), do: :green
  defp antenna_pointing_normalized_state(:acquiring), do: :blue
  defp antenna_pointing_normalized_state(:slewing), do: :blue
  defp antenna_pointing_normalized_state(:idle), do: :unknown
  defp antenna_pointing_normalized_state(:stowed), do: :unknown
  defp antenna_pointing_normalized_state(:degraded), do: :yellow
  defp antenna_pointing_normalized_state(_state), do: :unknown

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

  defp transport_execution_state(value)
       when value in [
              :initialized,
              :transport_event_handled,
              :control_input_handled,
              :timer_handled
            ],
       do: value

  defp transport_execution_state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")

    Enum.find(
      [:initialized, :transport_event_handled, :control_input_handled, :timer_handled],
      &(Atom.to_string(&1) == normalized)
    ) || :unknown
  end

  defp transport_execution_state(_value), do: :unknown

  defp matches_connection_scope?(row, request) do
    matches_scope?(row.transport_id, scope_ids(request, :transport)) and
      matches_scope?(row.source_endpoint_id, scope_ids(request, :source_endpoint)) and
      matches_scope?(row.ground_station_id, scope_ids(request, :ground_station)) and
      matches_scope?(row.link_id, scope_ids(request, :link))
  end

  defp matches_transport_execution_scope?(row, request) do
    matches_scope?(row.transport_id, scope_ids(request, :transport)) and
      matches_scope?(row.source_endpoint_id, scope_ids(request, :source_endpoint)) and
      matches_scope?(row.ground_station_id, scope_ids(request, :ground_station)) and
      matches_scope?(row.link_id, scope_ids(request, :link)) and
      matches_scope?(row.contact_id, scope_ids(request, :contact))
  end

  defp matches_managed_runtime_activity_scope?(event, request) do
    payload = attr(event, :payload) || attr(event, :current) || %{}

    attr(event, :kind) in @managed_runtime_event_kinds and
      matches_scope?(attr(payload, :partition_value), scope_ids(request, :spacecraft))
  end

  defp matches_transport_runtime_activity_scope?(event, request) do
    payload = attr(event, :payload) || attr(event, :current) || %{}

    attr(event, :kind) in @transport_runtime_event_kinds and
      matches_scope?(attr(payload, :capability_instance_id), scope_ids(request, :transport)) and
      matches_scope?(
        attr(payload, :contact_id) || attr(payload, :realized_contact_id),
        scope_ids(request, :contact)
      ) and
      matches_scope?(attr(payload, :source_endpoint_ref), scope_ids(request, :source_endpoint)) and
      matches_scope?(attr(payload, :path_id), scope_ids(request, :link))
  end

  defp interval_overlaps_request?(row, request) do
    from_time = request_time_bound(request, [:from, :start, :start_time])
    to_time = request_time_bound(request, [:to, :end, :end_time])

    starts_before_to? =
      is_nil(to_time) or
        (match?(%DateTime{}, row.starts_at) and DateTime.compare(row.starts_at, to_time) == :lt)

    ends_after_from? =
      is_nil(from_time) or is_nil(row.ends_at) or
        (match?(%DateTime{}, row.ends_at) and DateTime.compare(row.ends_at, from_time) == :gt)

    starts_before_to? and ends_after_from?
  end

  defp metric_history_row_in_request?(row, request) do
    match?(%DateTime{}, row.observed_at) and is_number(row.value) and
      row.observable_id in request.observables and
      matches_connection_scope?(row, request) and
      time_in_request_window?(row.observed_at, request)
  end

  defp metric_history_sort_key(row),
    do: {metric_history_series_key(row), datetime_sort_key(row.observed_at)}

  defp metric_history_series_key(row), do: {row.observable_id, row.resource_id}

  defp metric_history_product_family(observable_id) do
    ProductPolicy.metric_history_product_family(observable_id)
  end

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

  defp matches_command_queue_scope?(entry, request) do
    matches_scope?(command_queue_source_endpoint_id(entry), scope_ids(request, :source_endpoint)) and
      matches_scope?(metadata_attr(entry, :spacecraft_id), scope_ids(request, :spacecraft)) and
      matches_scope?(command_queue_contact_id(entry), scope_ids(request, :contact))
  end

  defp matches_ingress_processing_latency_scope?(sample, request) do
    matches_scope?(attr(sample, :source_endpoint_id), scope_ids(request, :source_endpoint)) and
      matches_scope?(attr(sample, :spacecraft_id), scope_ids(request, :spacecraft)) and
      matches_scope?(attr(sample, :contact_id), scope_ids(request, :contact)) and
      matches_scope?(attr(sample, :transport_id), scope_ids(request, :transport)) and
      matches_scope?(attr(sample, :ground_station_id), scope_ids(request, :ground_station)) and
      matches_scope?(attr(sample, :link_id), scope_ids(request, :link))
  end

  defp matches_request_replay_context?(sample, request) do
    case replay_run_id(request) do
      nil -> is_nil(attr(sample, :replay_run_id))
      replay_run_id -> attr(sample, :replay_run_id) == replay_run_id
    end
  end

  defp pending_command_queue_entry?(entry),
    do: attr(entry, :lifecycle_state) in [:pending, "pending"]

  defp command_queue_source_endpoint_id(entry) do
    attr(entry, :source_endpoint_ref) || attr(entry, :queue_lane_key)
  end

  defp command_queue_contact_id(entry) do
    metadata_attr(entry, :contact_id) ||
      metadata_attr(entry, :scheduled_contact_id) ||
      metadata_attr(entry, :realized_contact_id)
  end

  defp command_queue_depth_scope(request, mission_id) do
    [
      scoped_command_queue_depth_scope(request, :source_endpoint),
      scoped_command_queue_depth_scope(request, :spacecraft),
      scoped_command_queue_depth_scope(request, :contact)
    ]
    |> Enum.find_value(fn
      nil -> nil
      scope -> scope
    end)
    |> case do
      nil -> {:mission, mission_id, [mission_id]}
      scoped -> scoped
    end
  end

  defp scoped_command_queue_depth_scope(request, kind) do
    case scope_ids(request, kind) do
      [] -> nil
      [scope_id] -> {kind, scope_id, [scope_id]}
      scope_ids -> {kind, Enum.join(scope_ids, ","), scope_ids}
    end
  end

  defp command_queue_depth_label(:mission, _resource_id), do: "Pending commands"

  defp command_queue_depth_label(scope_kind, resource_id) do
    "#{humanize_atom(scope_kind)} / #{resource_id}"
  end

  defp command_queue_depth_source_endpoint_id(:source_endpoint, [resource_id]), do: resource_id
  defp command_queue_depth_source_endpoint_id(_scope_kind, _scope_ids), do: nil

  defp scope_ids(%PlannedSourceRequest{} = request, kind) do
    primary_ids =
      if ScopeContext.primary_kind(request.scope_context) in [kind, Atom.to_string(kind)] do
        ScopeContext.primary_ids(request.scope_context)
      else
        []
      end

    typed_id = ScopeContext.scope_id(request.scope_context, kind)

    [typed_id | primary_ids]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp matches_scope?(_value, []), do: true
  defp matches_scope?(value, ids), do: value in ids

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

  defp contact_phase_rows(scheduled_contacts, realized_contacts, contact_phase_scope) do
    (Enum.map(scheduled_contacts, &scheduled_contact_row/1) ++
       Enum.map(realized_contacts, &realized_contact_row/1))
    |> Enum.filter(&matches_contact_phase_scope?(&1, contact_phase_scope))
  end

  defp scheduled_contact_row(contact) do
    %{
      observable_id: "contacts.phase",
      contact_id: attr(contact, :scheduled_contact_id),
      related_contact_id: attr(contact, :realized_contact_id),
      contact_kind: :scheduled,
      phase: attr(contact, :lifecycle_state),
      time: attr(contact, :starts_at),
      source: contact
    }
  end

  defp realized_contact_row(contact) do
    %{
      observable_id: "contacts.phase",
      contact_id: attr(contact, :realized_contact_id),
      related_contact_id: attr(contact, :scheduled_contact_id),
      contact_kind: :realized,
      phase: attr(contact, :lifecycle_state),
      time: attr(contact, :realized_at) || attr(contact, :initial_time),
      source: contact
    }
  end

  defp contact_phase_label(row) do
    [Map.get(row, :contact_kind), Map.get(row, :contact_id)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" / ", &to_string/1)
  end

  defp contact_phase_lane_id(%{contact_kind: :realized, related_contact_id: related_contact_id})
       when is_binary(related_contact_id),
       do: related_contact_id

  defp contact_phase_lane_id(row), do: Map.get(row, :contact_id)

  defp matches_contact_phase_scope?(row, scope) do
    matches_contact_scope?(row, Map.get(scope, :contact_ids, [])) and
      matches_contact_source_endpoint_scope?(row, Map.get(scope, :source_endpoint_ids, [])) and
      matches_contact_spacecraft_scope?(
        row,
        Map.get(scope, :spacecraft_ids, []),
        Map.get(scope, :source_endpoints_by_id, %{})
      ) and
      matches_contact_ground_station_scope?(
        row,
        Map.get(scope, :ground_station_ids, []),
        Map.get(scope, :source_endpoints_by_id, %{})
      )
  end

  defp matches_contact_scope?(_row, []), do: true

  defp matches_contact_scope?(row, contact_scope_ids) do
    row.contact_id in contact_scope_ids or row.related_contact_id in contact_scope_ids
  end

  defp matches_contact_source_endpoint_scope?(_row, []), do: true

  defp matches_contact_source_endpoint_scope?(row, source_endpoint_ids) do
    row
    |> contact_phase_source_endpoint_refs()
    |> Enum.any?(&(&1 in source_endpoint_ids))
  end

  defp matches_contact_spacecraft_scope?(_row, [], _source_endpoints_by_id), do: true

  defp matches_contact_spacecraft_scope?(row, spacecraft_ids, source_endpoints_by_id) do
    row
    |> contact_phase_source_endpoints(source_endpoints_by_id)
    |> Enum.any?(&(attr(&1, :spacecraft_id) in spacecraft_ids))
  end

  defp matches_contact_ground_station_scope?(_row, [], _source_endpoints_by_id), do: true

  defp matches_contact_ground_station_scope?(row, ground_station_ids, source_endpoints_by_id) do
    row
    |> contact_phase_source_endpoints(source_endpoints_by_id)
    |> Enum.any?(&(source_endpoint_ground_station_id(&1) in ground_station_ids))
  end

  defp contact_phase_source_endpoints(row, source_endpoints_by_id) do
    row
    |> contact_phase_source_endpoint_refs()
    |> Enum.map(&Map.get(source_endpoints_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp contact_phase_source_endpoint_refs(row) do
    contact = Map.get(row, :source)

    [
      attr(contact, :source_endpoint_ref),
      attr(contact, :source_endpoint_refs),
      contact_phase_path_source_endpoint_refs(attr(contact, :paths))
    ]
    |> List.flatten()
    |> Enum.filter(&present_text?/1)
    |> Enum.uniq()
  end

  defp contact_phase_path_source_endpoint_refs(paths) when is_list(paths) do
    paths
    |> Enum.map(&attr(&1, :source_endpoint_ref))
    |> Enum.filter(&present_text?/1)
  end

  defp contact_phase_path_source_endpoint_refs(_paths), do: []

  defp source_endpoint_ground_station_id(source_endpoint) do
    metadata_attr(source_endpoint, :ground_station_id) ||
      metadata_attr(source_endpoint, :antenna_id)
  end

  defp rollup(spacecraft, point_states) do
    worst_by_spacecraft =
      point_states
      |> Enum.reject(&is_nil(&1.spacecraft_id))
      |> Enum.group_by(& &1.spacecraft_id, & &1.normalized_state)
      |> Map.new(fn {spacecraft_id, states} -> {spacecraft_id, worst_state(states)} end)

    spacecraft_entries =
      Enum.map(spacecraft, fn spacecraft ->
        %{
          spacecraft_id: spacecraft.spacecraft_id,
          worst_state: Map.get(worst_by_spacecraft, spacecraft.spacecraft_id)
        }
      end)

    counts =
      spacecraft_entries
      |> Enum.group_by(&(&1.worst_state || :no_data))
      |> Map.new(fn {state, entries} -> {state, length(entries)} end)

    %{counts: counts, spacecraft: spacecraft_entries}
  end

  defp worst_state(states) do
    Enum.max_by(states, &Map.get(@state_severity, &1, -1))
  end

  defp default_latest_states(organization_id, mission_id, _opts) do
    LimitReads.latest_states_for_mission(organization_id, mission_id, [])
  end

  defp default_spacecraft(organization_id, mission_id, _opts) do
    SpacecraftStore.list_spacecraft(organization_id, mission_id)
  end

  defp default_scheduled_contacts(organization_id, mission_id, _opts) do
    Contacts.list_scheduled_contacts(organization_id, mission_id)
  end

  defp default_realized_contacts(organization_id, mission_id, _opts) do
    Contacts.list_realized_contacts(organization_id, mission_id)
  end

  defp default_transports(organization_id, mission_id, _opts) do
    TransportStore.list_transports(organization_id, mission_id)
  end

  defp default_source_endpoints(organization_id, mission_id, _opts) do
    SourceEndpoints.list_source_endpoints(organization_id, mission_id)
  end

  defp default_connection_snapshots(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.connection_state_intervals(
      mission_id,
      operational_state_interval_opts(@connection_observable_ids, opts)
    )
    |> Enum.map(&connection_snapshot_from_interval/1)
  end

  defp default_antenna_pointing_snapshots(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.operational_observable_state_intervals(
      mission_id,
      operational_state_interval_opts(@antenna_pointing_observable_ids, opts)
    )
    |> Enum.map(&antenna_pointing_snapshot_from_interval/1)
  end

  defp default_transport_metric_snapshots(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.operational_observable_metric_samples(
      mission_id,
      operational_metric_sample_opts(@bitrate_observable_ids, opts)
    )
    |> Enum.map(&operational_metric_snapshot_from_sample/1)
  end

  defp default_link_rf_lock_snapshots(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.link_rf_state_intervals(
      mission_id,
      operational_state_interval_opts(@link_rf_lock_observable_ids, opts)
    )
    |> Enum.map(&rf_lock_snapshot_from_interval/1)
  end

  defp default_link_rf_frame_sync_snapshots(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.link_rf_state_intervals(
      mission_id,
      operational_state_interval_opts(@link_rf_frame_sync_observable_ids, opts)
    )
    |> Enum.map(&rf_frame_sync_snapshot_from_interval/1)
  end

  defp default_link_rf_metric_snapshots(organization_id, mission_id, opts) do
    organization_id
    |> OperationalEvents.operational_observable_metric_samples(
      mission_id,
      operational_metric_sample_opts(@link_rf_metric_observable_ids, opts)
    )
    |> Enum.map(&operational_metric_snapshot_from_sample/1)
  end

  defp operational_metric_sample_opts(observable_ids, opts) do
    [
      observable_id: observable_ids,
      from_time: Keyword.get(opts, :from),
      to_time: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      event_limit: Keyword.get(opts, :event_limit, 1_000),
      order: operational_metric_sample_order(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp operational_metric_sample_order(opts) do
    if Keyword.get(opts, :from) || Keyword.get(opts, :to), do: :asc, else: :desc
  end

  defp operational_state_interval_opts(observable_ids, opts) do
    [
      observable_id: observable_ids,
      from_time: Keyword.get(opts, :from),
      to_time: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      event_limit: Keyword.get(opts, :event_limit, 1_000),
      order: operational_state_interval_order(opts)
    ]
    |> maybe_add_latest_at(opts)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp operational_state_interval_order(opts) do
    if Keyword.get(opts, :from) || Keyword.get(opts, :to), do: :asc, else: :desc
  end

  defp maybe_add_latest_at(interval_opts, opts) do
    if Keyword.get(opts, :from) || Keyword.get(opts, :to) do
      interval_opts
    else
      [{:at, Keyword.get(opts, :at, DateTime.utc_now())} | interval_opts]
    end
  end

  defp connection_snapshot_from_interval(interval) do
    payload = attr(interval, :payload) || %{}

    %{
      observable_id: attr(payload, :observable_id),
      resource_id: attr(payload, :resource_id) || attr(interval, :subject_id),
      transport_id: attr(payload, :transport_id),
      source_endpoint_id: attr(payload, :source_endpoint_id),
      ground_station_id: attr(payload, :ground_station_id),
      link_id: attr(payload, :link_id),
      adapter_key: attr(payload, :adapter_key),
      connection_state: attr(payload, :connection_state),
      observed_at: attr(interval, :starts_at),
      interval_id: attr(interval, :interval_id),
      source_event_id: attr(interval, :source_event_id),
      replay_run_id: attr(payload, :replay_run_id),
      interval: interval
    }
  end

  defp operational_metric_snapshot_from_sample(sample) do
    %{
      observable_id: attr(sample, :observable_id),
      mission_id: attr(sample, :mission_id),
      organization_id: attr(sample, :organization_id),
      resource_id: attr(sample, :resource_id),
      transport_id: attr(sample, :transport_id),
      spacecraft_id: attr(sample, :spacecraft_id),
      contact_id:
        attr(sample, :contact_id) ||
          attr(sample, :scheduled_contact_id) ||
          attr(sample, :realized_contact_id),
      source_endpoint_id: attr(sample, :source_endpoint_id),
      ground_station_id: attr(sample, :ground_station_id),
      link_id: attr(sample, :link_id),
      link_assignment_id: attr(sample, :link_id),
      adapter_key: attr(sample, :adapter_key),
      value: attr(sample, :value),
      unit: attr(sample, :unit),
      downlink_bitrate: attr(sample, :downlink_bitrate),
      downlink_bitrate_bps: attr(sample, :downlink_bitrate_bps),
      uplink_bitrate: attr(sample, :uplink_bitrate),
      uplink_bitrate_bps: attr(sample, :uplink_bitrate_bps),
      bitrate: attr(sample, :bitrate),
      snr_db: attr(sample, :snr_db),
      snr: attr(sample, :snr),
      signal_to_noise_ratio_db: attr(sample, :signal_to_noise_ratio_db),
      eb_n0_db: attr(sample, :eb_n0_db),
      ebn0_db: attr(sample, :ebn0_db),
      energy_per_bit_to_noise_density_db: attr(sample, :energy_per_bit_to_noise_density_db),
      symbol_rate_sps: attr(sample, :symbol_rate_sps),
      symbol_rate: attr(sample, :symbol_rate),
      symbols_per_second: attr(sample, :symbols_per_second),
      doppler_hz: attr(sample, :doppler_hz),
      doppler: attr(sample, :doppler),
      frequency_offset_hz: attr(sample, :frequency_offset_hz),
      carrier_frequency_offset_hz: attr(sample, :carrier_frequency_offset_hz),
      observed_at: attr(sample, :observed_at),
      source_event_id: attr(sample, :source_event_id),
      replay_run_id: attr(sample, :replay_run_id)
    }
  end

  defp rf_lock_snapshot_from_interval(interval) do
    payload = attr(interval, :payload) || %{}
    state = attr(payload, :state)

    operational_state_snapshot_from_interval(interval, payload)
    |> Map.merge(%{lock_state: state, state: state})
  end

  defp rf_frame_sync_snapshot_from_interval(interval) do
    payload = attr(interval, :payload) || %{}
    state = attr(payload, :state)

    operational_state_snapshot_from_interval(interval, payload)
    |> Map.merge(%{frame_sync_state: state, state: state})
  end

  defp antenna_pointing_snapshot_from_interval(interval) do
    payload = attr(interval, :payload) || %{}
    state = attr(payload, :state) || attr(payload, :normalized_state)

    operational_state_snapshot_from_interval(interval, payload)
    |> Map.merge(%{antenna_pointing_state: state, state: state})
  end

  defp operational_state_snapshot_from_interval(interval, payload) do
    %{
      observable_id: attr(payload, :observable_id),
      resource_id: attr(payload, :resource_id) || attr(interval, :subject_id),
      transport_id: attr(payload, :transport_id),
      source_endpoint_id: attr(payload, :source_endpoint_id),
      ground_station_id: attr(payload, :ground_station_id),
      link_id: attr(payload, :link_id),
      link_assignment_id: attr(payload, :link_id),
      adapter_key: attr(payload, :adapter_key),
      normalized_state: attr(payload, :normalized_state),
      observed_at: attr(interval, :starts_at),
      interval_id: attr(interval, :interval_id),
      source_event_id: attr(interval, :source_event_id),
      replay_run_id: attr(payload, :replay_run_id),
      interval: interval
    }
  end

  defp default_transport_execution_intervals(organization_id, mission_id, opts) do
    OperationalEvents.transport_execution_intervals(
      organization_id,
      mission_id,
      transport_execution_interval_opts(opts)
    )
  end

  defp transport_execution_interval_opts(opts) do
    [
      from_time: Keyword.get(opts, :from),
      to_time: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      event_limit: Keyword.get(opts, :event_limit, 1_000)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp default_managed_runtime_events(organization_id, mission_id, opts) do
    OperationalEvents.list_events(
      organization_id,
      mission_id,
      managed_runtime_event_opts(opts)
    )
  end

  defp managed_runtime_event_opts(opts) do
    [
      category: :runtime,
      kind: @managed_runtime_event_kinds,
      source_record_kind: @managed_runtime_source_record_kinds,
      from_occurred_at: Keyword.get(opts, :from),
      to_occurred_at: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      order: :asc,
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp default_transport_runtime_events(organization_id, mission_id, opts) do
    OperationalEvents.list_events(
      organization_id,
      mission_id,
      transport_runtime_event_opts(opts)
    )
  end

  defp default_command_verifier_instances(organization_id, mission_id, opts) do
    case Keyword.get(opts, :command_release_attempt_ids, []) do
      [] ->
        []

      command_release_attempt_ids when is_list(command_release_attempt_ids) ->
        command_release_attempt_ids
        |> Enum.flat_map(fn command_release_attempt_id ->
          Commanding.list_command_verifier_instances(organization_id, mission_id,
            command_release_attempt_id: command_release_attempt_id
          )
        end)
    end
  end

  defp transport_runtime_event_opts(opts) do
    [
      category: :comms,
      kind: @transport_runtime_event_kinds,
      source_record_kind: @transport_runtime_source_record_kinds,
      from_occurred_at: Keyword.get(opts, :from),
      to_occurred_at: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      order: :asc,
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp default_contact_phase_revision(organization_id, mission_id, opts) do
    "contacts_phase:" <>
      RuntimeCacheKey.fingerprint(%{
        scheduled_contacts:
          organization_id
          |> default_scheduled_contacts(mission_id, opts)
          |> Enum.map(&scheduled_contact_revision_entry/1)
          |> Enum.sort_by(&(&1.scheduled_contact_id || "")),
        realized_contacts:
          organization_id
          |> default_realized_contacts(mission_id, opts)
          |> Enum.map(&realized_contact_revision_entry/1)
          |> Enum.sort_by(&(&1.realized_contact_id || ""))
      })
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
          |> default_connection_snapshots(mission_id, opts)
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
          |> default_antenna_pointing_snapshots(mission_id, opts)
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
          |> default_transport_metric_snapshots(mission_id, opts)
          |> Enum.map(&transport_metric_revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || &1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp default_transport_execution_state_revision(organization_id, mission_id, opts) do
    "transport_execution_state:" <>
      RuntimeCacheKey.fingerprint(%{
        intervals:
          organization_id
          |> default_transport_execution_intervals(mission_id, opts)
          |> Enum.map(&transport_execution_interval_revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || "", &1.starts_at || ""})
      })
  end

  defp default_managed_runtime_activity_revision(organization_id, mission_id, opts) do
    "managed_runtime_activity:" <>
      RuntimeCacheKey.fingerprint(%{
        events:
          organization_id
          |> default_managed_runtime_events(mission_id, opts)
          |> Enum.map(&managed_runtime_event_revision_entry/1)
          |> Enum.sort_by(&{&1.source_event_id || "", &1.occurred_at || ""})
      })
  end

  defp default_transport_runtime_activity_revision(organization_id, mission_id, opts) do
    events = default_transport_runtime_events(organization_id, mission_id, opts)

    "transport_runtime_activity:" <>
      RuntimeCacheKey.fingerprint(%{
        events:
          events
          |> Enum.map(&managed_runtime_event_revision_entry/1)
          |> Enum.sort_by(&{&1.source_event_id || "", &1.occurred_at || ""}),
        command_verifier_instances:
          organization_id
          |> default_command_verifier_instances(
            mission_id,
            Keyword.put(
              opts,
              :command_release_attempt_ids,
              command_release_attempt_ids_from_events(events)
            )
          )
          |> Enum.map(&command_verifier_instance_revision_entry/1)
          |> Enum.sort_by(&(&1.command_verifier_instance_id || ""))
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
          |> default_link_rf_lock_snapshots(mission_id, opts)
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
          |> default_link_rf_frame_sync_snapshots(mission_id, opts)
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
          |> default_link_rf_metric_snapshots(mission_id, opts)
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
    |> Enum.map(&normalize_ingress_processing_latency_snapshot/1)
    |> Enum.map(&{&1, 0})
    |> Kernel.++(
      runtime_snapshots
      |> Enum.map(&normalize_ingress_processing_latency_snapshot/1)
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
    organization_id
    |> OperationalEvents.operational_observable_metric_samples(
      mission_id,
      operational_metric_sample_opts(["ingress.processing_latency_ms"], opts)
    )
    |> Enum.map(&operational_metric_snapshot_from_sample/1)
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

  defp default_command_queue_entries(organization_id, mission_id, _opts) do
    Commanding.list_command_queue_entries(organization_id, mission_id, lifecycle_state: :pending)
  end

  defp default_command_queue_revision(organization_id, mission_id, opts) do
    organization_id
    |> default_command_queue_entries(mission_id, opts)
    |> Enum.filter(&pending_command_queue_entry?/1)
    |> command_queue_entries_revision()
  end

  defp command_queue_entries_revision(entries) do
    "command_queue_depth:" <>
      RuntimeCacheKey.fingerprint(%{
        entries:
          entries
          |> Enum.map(&command_queue_revision_entry/1)
          |> Enum.sort_by(&(&1.command_queue_entry_id || ""))
      })
  end

  defp command_queue_revision_entry(entry) do
    %{
      command_queue_entry_id: attr(entry, :command_queue_entry_id),
      source_endpoint_ref: attr(entry, :source_endpoint_ref),
      queue_lane_key: attr(entry, :queue_lane_key),
      queue_sequence: attr(entry, :queue_sequence),
      priority: attr(entry, :priority),
      lifecycle_state: attr(entry, :lifecycle_state),
      enqueued_at: attr(entry, :enqueued_at),
      not_before: attr(entry, :not_before),
      expires_at: attr(entry, :expires_at),
      metadata: attr(entry, :metadata)
    }
  end

  defp managed_runtime_event_revision_entry(event) do
    causality = attr(event, :causality) || %{}

    %{
      source_event_id: attr(event, :event_id),
      source_record_kind: attr(causality, :source_record_kind),
      source_record_id: attr(causality, :source_record_id),
      kind: attr(event, :kind),
      occurred_at: attr(event, :occurred_at),
      replay_run_id: attr(event, :replay_run_id)
    }
  end

  defp command_verifier_instance_revision_entry(verifier_instance) do
    %{
      command_verifier_instance_id: attr(verifier_instance, :command_verifier_instance_id),
      command_release_attempt_id: attr(verifier_instance, :command_release_attempt_id),
      command_request_id: attr(verifier_instance, :command_request_id),
      phase: attr(verifier_instance, :phase),
      severity: attr(verifier_instance, :severity),
      lifecycle_state: attr(verifier_instance, :lifecycle_state),
      matched_record_kind: attr(verifier_instance, :matched_record_kind),
      matched_record_id: attr(verifier_instance, :matched_record_id),
      matched_at: attr(verifier_instance, :matched_at),
      failure_reason: attr(verifier_instance, :failure_reason)
    }
  end

  defp scheduled_contact_revision_entry(contact) do
    %{
      scheduled_contact_id: attr(contact, :scheduled_contact_id),
      realized_contact_id: attr(contact, :realized_contact_id),
      ground_station_id: attr(contact, :ground_station_id),
      source_endpoint_id: attr(contact, :source_endpoint_id),
      spacecraft_id: attr(contact, :spacecraft_id),
      lifecycle_state: attr(contact, :lifecycle_state),
      starts_at: attr(contact, :starts_at),
      ends_at: attr(contact, :ends_at),
      metadata: attr(contact, :metadata)
    }
  end

  defp realized_contact_revision_entry(contact) do
    %{
      realized_contact_id: attr(contact, :realized_contact_id),
      scheduled_contact_id: attr(contact, :scheduled_contact_id),
      ground_station_id: attr(contact, :ground_station_id),
      source_endpoint_id: attr(contact, :source_endpoint_id),
      spacecraft_id: attr(contact, :spacecraft_id),
      lifecycle_state: attr(contact, :lifecycle_state),
      realized_at: attr(contact, :realized_at),
      initial_time: attr(contact, :initial_time),
      stopped_at: attr(contact, :stopped_at),
      metadata: attr(contact, :metadata)
    }
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
      value: transport_metric_value(snapshot, attr(snapshot, :observable_id)),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
    }
  end

  defp transport_execution_interval_revision_entry(interval) do
    payload = attr(interval, :payload) || %{}

    %{
      interval_id: attr(interval, :interval_id),
      transport_id: attr(interval, :subject_id) || attr(payload, :capability_instance_id),
      transport_record_id: attr(payload, :transport_record_id),
      contact_id: attr(payload, :contact_id) || attr(payload, :realized_contact_id),
      path_id: attr(payload, :path_id),
      event_kind: attr(payload, :event_kind),
      starts_at: attr(interval, :starts_at),
      ends_at: attr(interval, :ends_at),
      source_event_id: attr(interval, :source_event_id)
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
      state: rf_lock_state(snapshot),
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
      state: frame_sync_state(snapshot),
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
      state: antenna_pointing_state(snapshot),
      observed_at: attr(snapshot, :observed_at)
    }
  end

  defp link_rf_metric_revision_entry(snapshot) do
    %{
      observable_id: link_rf_metric_observable_id(snapshot),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id_for([snapshot]),
      adapter_key: attr(snapshot, :adapter_key),
      value: link_rf_metric_value(snapshot, link_rf_metric_observable_id(snapshot)),
      unit: link_rf_metric_unit(snapshot, link_rf_metric_observable_id(snapshot)),
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
      value: ingress_processing_latency_value(snapshot),
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

  defp contact_scope_ids(%PlannedSourceRequest{} = request) do
    scope_ids(request, :contact)
  end

  defp contact_phase_scope(
         %PlannedSourceRequest{} = request,
         organization_id,
         mission_id,
         opts,
         adapter_opts
       ) do
    scope = %{
      contact_ids: contact_scope_ids(request),
      source_endpoint_ids: scope_ids(request, :source_endpoint),
      spacecraft_ids: scope_ids(request, :spacecraft),
      ground_station_ids: scope_ids(request, :ground_station),
      source_endpoints_by_id: %{}
    }

    if contact_phase_source_endpoint_scope_required?(scope) do
      source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

      source_endpoints_by_id =
        source_endpoints_fun.(organization_id, mission_id, adapter_opts)
        |> Map.new(&{attr(&1, :source_endpoint_id), &1})

      %{scope | source_endpoints_by_id: source_endpoints_by_id}
    else
      scope
    end
  end

  defp contact_phase_source_endpoint_scope_required?(scope) do
    Map.get(scope, :source_endpoint_ids, []) != [] or
      Map.get(scope, :spacecraft_ids, []) != [] or
      Map.get(scope, :ground_station_ids, []) != []
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

  defp time_in_request_window?(%DateTime{} = time, %PlannedSourceRequest{} = request) do
    from_time = request_time_bound(request, [:from, :start, :start_time])
    to_time = request_time_bound(request, [:to, :end, :end_time])

    after_from? = is_nil(from_time) or DateTime.compare(time, from_time) != :lt
    before_to? = is_nil(to_time) or DateTime.compare(time, to_time) != :gt

    after_from? and before_to?
  end

  defp time_in_request_window?(_time, _request), do: false

  defp apply_request_limit(rows, %PlannedSourceRequest{} = request) do
    case context_value(request.sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(rows, limit)
      _other -> rows
    end
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_key(_datetime), do: 0

  defp metadata_attr(value, key) when is_atom(key) do
    value
    |> attr(:metadata)
    |> attr(key)
  end

  defp present_text?(value), do: is_binary(value) and value != ""

  defp humanize_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

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
