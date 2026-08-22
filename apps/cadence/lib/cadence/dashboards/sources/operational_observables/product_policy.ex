defmodule Cadence.Dashboards.Sources.OperationalObservables.ProductPolicy do
  @moduledoc """
  Defines source-backed operational observable products and sampling contracts.

  This module validates operational source requests, selects the concrete
  product for a sampling mode, and publishes the backing metadata consumed by
  capability planning.
  """

  alias Cadence.Dashboards.{OperationalObservable, PlannedSourceRequest, ResolveWarning}

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
  @command_queue_observable_ids ["commanding.queue_depth"]
  @managed_runtime_observable_ids ["runtime.managed_activity"]
  @transport_runtime_observable_ids ["runtime.transport_activity"]

  @latest_observable_ids @bitrate_observable_ids ++
                           @command_queue_observable_ids ++
                           @ingress_latency_observable_ids ++
                           @connection_observable_ids ++
                           @antenna_pointing_observable_ids ++
                           @link_rf_lock_observable_ids ++
                           @link_rf_frame_sync_observable_ids ++
                           @link_rf_metric_observable_ids ++ ["contacts.phase"]

  @metric_history_contracts [
    %{
      observables: @link_rf_metric_observable_ids,
      product: :link_rf_metric_history,
      product_family: :link_rf
    },
    %{
      observables: @bitrate_observable_ids,
      product: :transport_bitrate_history,
      product_family: :transport_bitrate
    },
    %{
      observables: @ingress_latency_observable_ids,
      product: :ingress_processing_latency_history,
      product_family: :runtime_ingress
    }
  ]

  @metric_history_observable_ids Enum.flat_map(@metric_history_contracts, & &1.observables)

  @state_history_observable_ids @connection_observable_ids ++
                                  @link_rf_lock_observable_ids ++
                                  @link_rf_frame_sync_observable_ids ++
                                  @antenna_pointing_observable_ids ++
                                  @transport_execution_observable_ids ++
                                  @managed_runtime_observable_ids ++
                                  @transport_runtime_observable_ids ++ ["contacts.phase"]

  @latest_contracts [
    %{
      observables: ["contacts.phase"],
      product: :contacts_phase,
      product_family: :contacts,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @bitrate_observable_ids,
      product: :transport_bitrate,
      product_family: :transport_bitrate,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @command_queue_observable_ids,
      product: :command_queue_depth,
      product_family: :commanding,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @ingress_latency_observable_ids,
      product: :ingress_processing_latency,
      product_family: :runtime_ingress,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @connection_observable_ids,
      product: :connection_state,
      product_family: :connection_state,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @antenna_pointing_observable_ids,
      product: :ground_station_antenna_pointing_state,
      product_family: :ground_station,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @link_rf_lock_observable_ids,
      product: :link_rf_lock_state,
      product_family: :link_rf,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @link_rf_frame_sync_observable_ids,
      product: :link_rf_frame_sync_state,
      product_family: :link_rf,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @link_rf_metric_observable_ids,
      product: :link_rf_metric,
      product_family: :link_rf,
      sampling: :latest,
      shape: :matrix
    },
    %{
      observables: @latest_observable_ids,
      product: :operational_latest,
      product_family: :operational_latest,
      sampling: :latest,
      shape: :matrix
    }
  ]

  @state_history_contracts [
    %{
      observables: ["contacts.phase"],
      product: :contacts_phase_history,
      product_family: :contacts,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @connection_observable_ids,
      product: :connection_state_history,
      product_family: :connection_state,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @antenna_pointing_observable_ids,
      product: :ground_station_antenna_pointing_state_history,
      product_family: :ground_station,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @link_rf_lock_observable_ids,
      product: :link_rf_lock_state_history,
      product_family: :link_rf,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @link_rf_frame_sync_observable_ids,
      product: :link_rf_frame_sync_state_history,
      product_family: :link_rf,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @transport_execution_observable_ids,
      product: :transport_execution_state_history,
      product_family: :comms_transport,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @managed_runtime_observable_ids,
      product: :managed_runtime_activity_history,
      product_family: :runtime_managed,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @transport_runtime_observable_ids,
      product: :transport_runtime_activity_history,
      product_family: :runtime_transport,
      sampling: :event_history,
      shape: :events
    },
    %{
      observables: @state_history_observable_ids,
      product: :operational_state_history,
      product_family: :operational_state,
      sampling: :event_history,
      shape: :events
    }
  ]

  @backed_observable_ids @bitrate_observable_ids ++
                           @transport_execution_observable_ids ++
                           @command_queue_observable_ids ++
                           @managed_runtime_observable_ids ++
                           @transport_runtime_observable_ids ++
                           @ingress_latency_observable_ids ++
                           @connection_observable_ids ++
                           @antenna_pointing_observable_ids ++
                           @link_rf_lock_observable_ids ++
                           @link_rf_frame_sync_observable_ids ++
                           @link_rf_metric_observable_ids ++ ["contacts.phase"]

  @spec backed_observable_ids() :: [binary()]
  def backed_observable_ids, do: @backed_observable_ids

  @spec backed_observable?(term()) :: boolean()
  def backed_observable?(observable_id) when is_binary(observable_id),
    do: observable_id in @backed_observable_ids

  def backed_observable?(_observable_id), do: false

  @spec source_backing_contracts() :: [map()]
  def source_backing_contracts do
    raw_series_contracts =
      Enum.map(@metric_history_contracts, fn contract ->
        Map.merge(contract, %{sampling: :raw_series, shape: :wide})
      end) ++
        [
          %{
            observables: @metric_history_observable_ids,
            product: :operational_metric_history,
            product_family: :operational_metric,
            sampling: :raw_series,
            shape: :wide
          }
        ]

    (@latest_contracts ++ @state_history_contracts ++ raw_series_contracts)
    |> Enum.map(fn contract ->
      %{
        observables: contract.observables,
        product: contract.product,
        product_family: contract.product_family,
        sampling: contract.sampling,
        shape: contract.shape
      }
    end)
  end

  @spec metric_history_contracts() :: [map()]
  def metric_history_contracts do
    Enum.map(@metric_history_contracts, fn contract ->
      %{
        observables: contract.observables,
        product: contract.product,
        product_family: contract.product_family
      }
    end)
  end

  @spec metric_history_product_family(term()) :: atom()
  def metric_history_product_family(observable_id) when is_binary(observable_id) do
    case metric_history_contract_for_observable(observable_id) do
      %{product_family: product_family} -> product_family
      nil -> :operational_metric
    end
  end

  def metric_history_product_family(_observable_id), do: :operational_metric

  @spec validate(PlannedSourceRequest.t()) ::
          {:ok, atom()} | {:warning, ResolveWarning.t()}
  def validate(%PlannedSourceRequest{} = request) do
    with :ok <- ensure_operational_source(request),
         :ok <- ensure_supported_observables(request) do
      supported_product(request)
    end
  end

  defp ensure_operational_source(%PlannedSourceRequest{logical_source: :operational_observables}),
    do: :ok

  defp ensure_operational_source(%PlannedSourceRequest{} = request) do
    {:warning,
     warning(
       request,
       :unsupported_logical_source,
       :error,
       "Operational observables adapter cannot resolve source",
       %{logical_source: request.logical_source}
     )}
  end

  defp ensure_supported_observables(%PlannedSourceRequest{observables: []}), do: :ok

  defp ensure_supported_observables(%PlannedSourceRequest{} = request) do
    unsupported_observables = Enum.reject(request.observables, &OperationalObservable.known?/1)

    case unsupported_observables do
      [] ->
        :ok

      observables ->
        {:warning,
         warning(
           request,
           :unsupported_operational_observable,
           :warning,
           "Operational observables source cannot resolve requested observable",
           %{observables: observables, supported_observables: OperationalObservable.ids()}
         )}
    end
  end

  defp supported_product(%PlannedSourceRequest{} = request) do
    case sampling_mode(request) do
      :constellation_health -> constellation_health_product(request)
      :latest -> latest_product(request)
      :event_history -> event_history_product(request)
      :raw_series -> metric_history_product(request)
      mode -> unsupported_sampling_warning(request, mode)
    end
  end

  defp constellation_health_product(%PlannedSourceRequest{observables: []}),
    do: {:ok, :constellation_health}

  defp constellation_health_product(%PlannedSourceRequest{} = request),
    do: unsupported_sampling_warning(request, :constellation_health)

  defp latest_product(%PlannedSourceRequest{observables: ["contacts.phase"]}),
    do: {:ok, :contacts_phase}

  defp latest_product(%PlannedSourceRequest{} = request) do
    observables = request.observables

    case latest_backed_product(observables) do
      {:ok, product} ->
        {:ok, product}

      :error ->
        if latest_observables?(observables) do
          {:ok, :operational_latest}
        else
          unsupported_backing_warning(request, observables)
        end
    end
  end

  defp latest_backed_product(observables) do
    [
      {&bitrate_observables?/1, :transport_bitrate},
      {&command_queue_observables?/1, :command_queue_depth},
      {&ingress_latency_observables?/1, :ingress_processing_latency},
      {&connection_observables?/1, :connection_state},
      {&antenna_pointing_observables?/1, :ground_station_antenna_pointing_state},
      {&link_rf_lock_observables?/1, :link_rf_lock_state},
      {&link_rf_frame_sync_observables?/1, :link_rf_frame_sync_state},
      {&link_rf_metric_observables?/1, :link_rf_metric}
    ]
    |> Enum.find_value(:error, fn {matches?, product} ->
      if matches?.(observables), do: {:ok, product}, else: false
    end)
  end

  defp event_history_product(%PlannedSourceRequest{observables: ["contacts.phase"]}),
    do: {:ok, :contacts_phase_history}

  defp event_history_product(%PlannedSourceRequest{} = request) do
    observables = request.observables

    event_history_product_for_observables(observables) ||
      {:warning,
       warning(
         request,
         :unsupported_operational_observable_history,
         :warning,
         "Operational observables source can only resolve state-valued event history",
         %{
           requested_mode: :event_history,
           observables: observables,
           supported_observables: @state_history_observable_ids
         }
       )}
  end

  defp event_history_product_for_observables(observables) do
    [
      {&connection_observables?/1, :connection_state_history},
      {&antenna_pointing_observables?/1, :ground_station_antenna_pointing_state_history},
      {&link_rf_lock_observables?/1, :link_rf_lock_state_history},
      {&link_rf_frame_sync_observables?/1, :link_rf_frame_sync_state_history},
      {&transport_execution_observables?/1, :transport_execution_state_history},
      {&managed_runtime_observables?/1, :managed_runtime_activity_history},
      {&transport_runtime_observables?/1, :transport_runtime_activity_history},
      {&state_history_observables?/1, :operational_state_history}
    ]
    |> Enum.find_value(fn {matches?, product} ->
      if matches?.(observables), do: {:ok, product}, else: false
    end)
  end

  defp metric_history_product(%PlannedSourceRequest{} = request) do
    observables = request.observables

    case metric_history_contract_for_observables(observables) do
      %{product: product} ->
        {:ok, product}

      nil ->
        if metric_history_observables?(observables) do
          {:ok, :operational_metric_history}
        else
          {:warning,
           warning(
             request,
             :unsupported_operational_observable_history,
             :warning,
             "Operational observables source can only resolve metric-valued raw series",
             %{
               requested_mode: :raw_series,
               observables: observables,
               supported_observables: @metric_history_observable_ids
             }
           )}
        end
    end
  end

  defp metric_history_contract_for_observables(observables)
       when is_list(observables) and observables != [] do
    Enum.find(@metric_history_contracts, fn contract ->
      Enum.all?(observables, &(&1 in contract.observables))
    end)
  end

  defp metric_history_contract_for_observables(_observables), do: nil

  defp metric_history_contract_for_observable(observable_id) do
    Enum.find(@metric_history_contracts, &(observable_id in &1.observables))
  end

  defp unsupported_sampling_warning(%PlannedSourceRequest{} = request, mode) do
    {:warning,
     warning(
       request,
       :unsupported_sampling,
       :warning,
       "Operational observables source cannot resolve requested sampling mode",
       %{
         requested_mode: mode,
         supported_modes: [:constellation_health, :latest, :event_history, :raw_series]
       }
     )}
  end

  defp metric_history_observables?(observables),
    do: backed_by?(observables, @metric_history_observable_ids)

  defp latest_observables?(observables), do: backed_by?(observables, @latest_observable_ids)

  defp state_history_observables?(observables),
    do: backed_by?(observables, @state_history_observable_ids)

  defp connection_observables?(observables),
    do: backed_by?(observables, @connection_observable_ids)

  defp antenna_pointing_observables?(observables),
    do: backed_by?(observables, @antenna_pointing_observable_ids)

  defp link_rf_lock_observables?(observables),
    do: backed_by?(observables, @link_rf_lock_observable_ids)

  defp link_rf_frame_sync_observables?(observables),
    do: backed_by?(observables, @link_rf_frame_sync_observable_ids)

  defp link_rf_metric_observables?(observables),
    do: backed_by?(observables, @link_rf_metric_observable_ids)

  defp bitrate_observables?(observables), do: backed_by?(observables, @bitrate_observable_ids)

  defp transport_execution_observables?(observables),
    do: backed_by?(observables, @transport_execution_observable_ids)

  defp managed_runtime_observables?(observables),
    do: backed_by?(observables, @managed_runtime_observable_ids)

  defp transport_runtime_observables?(observables),
    do: backed_by?(observables, @transport_runtime_observable_ids)

  defp command_queue_observables?(observables),
    do: backed_by?(observables, @command_queue_observable_ids)

  defp ingress_latency_observables?(observables),
    do: backed_by?(observables, @ingress_latency_observable_ids)

  defp backed_by?(observables, backed_observables)
       when is_list(observables) and observables != [] do
    Enum.all?(observables, &(&1 in backed_observables))
  end

  defp backed_by?(_observables, _backed_observables), do: false

  defp unsupported_backing_warning(%PlannedSourceRequest{} = request, observables) do
    {:warning,
     warning(
       request,
       :unsupported_operational_observable_backing,
       :warning,
       "Operational observables source has no backing adapter for requested observable",
       %{
         requested_mode: sampling_mode(request),
         observables: observables,
         supported_observables: backed_observable_ids()
       }
     )}
  end

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    with :error <- Map.fetch(context, key),
         :error <- Map.fetch(context, Atom.to_string(key)) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp context_value(_context, _key), do: nil

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp normalize_atom(_value), do: nil

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
