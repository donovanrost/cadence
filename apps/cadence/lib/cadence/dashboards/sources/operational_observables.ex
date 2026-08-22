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
    SourceFacts,
    SourceResult
  }

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    AggregateProducts,
    AntennaPointing,
    CommandQueueDepth,
    Connection,
    ConstellationHealth,
    ContactPhase,
    IngressProcessingLatency,
    LinkRf,
    ProductPolicy,
    RevisionPolicy,
    RuntimeActivity,
    TransportBitrate,
    TransportExecutionState
  }

  @type connection_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
  @type transport_metric_snapshots_fun :: (binary(), binary(), keyword() -> [map() | struct()])
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
      connection_state: &Connection.default_revision/3,
      ground_station_antenna_pointing_state: &AntennaPointing.default_revision/3,
      link_rf_lock_state: &LinkRf.default_lock_revision/3,
      link_rf_frame_sync_state: &LinkRf.default_frame_sync_revision/3,
      link_rf_metric: &LinkRf.default_metric_revision/3,
      transport_bitrate: &TransportBitrate.default_revision/3,
      transport_execution_state: &TransportExecutionState.default_revision/3,
      managed_runtime_activity: &RuntimeActivity.default_managed_revision/3,
      transport_runtime_activity: &RuntimeActivity.default_transport_revision/3,
      ingress_processing_latency: &IngressProcessingLatency.default_revision/3,
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
      Connection.resolve_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      Connection.resolve_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      AntennaPointing.resolve_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      AntennaPointing.resolve_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      LinkRf.resolve_lock_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      LinkRf.resolve_lock_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      LinkRf.resolve_frame_sync_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      LinkRf.resolve_frame_sync_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      LinkRf.resolve_metric_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      LinkRf.resolve_metric_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

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
      AggregateProducts.resolve(
        :operational_state_history,
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
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
      AggregateProducts.resolve(
        :operational_latest,
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
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
      AggregateProducts.resolve(
        :operational_metric_history,
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
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
      TransportBitrate.resolve_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      TransportBitrate.resolve_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
      )

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
      IngressProcessingLatency.resolve_latest(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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
      IngressProcessingLatency.resolve_history(
        request,
        organization_id,
        mission_id,
        frame_source_context(request, source_binding),
        adapter_opts(request, source_binding),
        opts
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

  defp frame_source_context(%PlannedSourceRequest{} = request, source_binding) do
    %{
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request)
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
