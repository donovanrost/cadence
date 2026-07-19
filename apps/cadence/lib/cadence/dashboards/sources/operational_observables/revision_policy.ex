defmodule Cadence.Dashboards.Sources.OperationalObservables.RevisionPolicy do
  @moduledoc """
  Selects and aggregates data revisions for operational observable products.

  Provider callbacks remain owned by the source adapter. This module owns the
  product-to-family routing and stable multi-family revision fingerprints used
  by source facts and runtime cache identity.
  """

  alias Cadence.Dashboards.RuntimeCacheKey

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
  @ingress_latency_observable_ids ["ingress.processing_latency_ms"]
  @managed_runtime_observable_ids ["runtime.managed_activity"]
  @transport_runtime_observable_ids ["runtime.transport_activity"]

  @revision_options %{
    contacts_phase: :contact_phase_revision_fun,
    connection_state: :connection_state_revision_fun,
    ground_station_antenna_pointing_state: :antenna_pointing_state_revision_fun,
    link_rf_lock_state: :link_rf_lock_state_revision_fun,
    link_rf_frame_sync_state: :link_rf_frame_sync_state_revision_fun,
    link_rf_metric: :link_rf_metric_revision_fun,
    transport_bitrate: :transport_bitrate_revision_fun,
    transport_execution_state: :transport_execution_state_revision_fun,
    managed_runtime_activity: :managed_runtime_activity_revision_fun,
    transport_runtime_activity: :transport_runtime_activity_revision_fun,
    ingress_processing_latency: :ingress_processing_latency_revision_fun,
    command_queue_depth: :command_queue_revision_fun
  }

  @type revision_fun :: (binary(), binary(), keyword() -> binary() | nil)

  @spec data_revision(
          atom(),
          [binary()],
          binary(),
          binary(),
          keyword(),
          keyword(),
          keyword(revision_fun())
        ) :: binary() | nil
  def data_revision(
        product,
        observables,
        organization_id,
        mission_id,
        adapter_opts,
        opts,
        default_funs
      ) do
    case product do
      :operational_latest ->
        aggregate_revision(
          "operational_latest",
          latest_families(observables),
          organization_id,
          mission_id,
          adapter_opts,
          opts,
          default_funs
        )

      :operational_state_history ->
        aggregate_revision(
          "operational_state_history",
          state_history_families(observables),
          organization_id,
          mission_id,
          adapter_opts,
          opts,
          default_funs
        )

      :operational_metric_history ->
        aggregate_revision(
          "operational_metric_history",
          metric_history_families(observables),
          organization_id,
          mission_id,
          adapter_opts,
          opts,
          default_funs
        )

      product ->
        product
        |> product_family()
        |> revision_for_family(
          organization_id,
          mission_id,
          adapter_opts,
          opts,
          default_funs
        )
    end
  end

  defp product_family(product) when product in [:contacts_phase, :contacts_phase_history],
    do: :contacts_phase

  defp product_family(product) when product in [:connection_state, :connection_state_history],
    do: :connection_state

  defp product_family(product)
       when product in [
              :ground_station_antenna_pointing_state,
              :ground_station_antenna_pointing_state_history
            ],
       do: :ground_station_antenna_pointing_state

  defp product_family(product)
       when product in [:link_rf_lock_state, :link_rf_lock_state_history],
       do: :link_rf_lock_state

  defp product_family(product)
       when product in [:link_rf_frame_sync_state, :link_rf_frame_sync_state_history],
       do: :link_rf_frame_sync_state

  defp product_family(product) when product in [:link_rf_metric, :link_rf_metric_history],
    do: :link_rf_metric

  defp product_family(product)
       when product in [:transport_bitrate, :transport_bitrate_history],
       do: :transport_bitrate

  defp product_family(:transport_execution_state_history), do: :transport_execution_state
  defp product_family(:managed_runtime_activity_history), do: :managed_runtime_activity
  defp product_family(:transport_runtime_activity_history), do: :transport_runtime_activity

  defp product_family(product)
       when product in [
              :ingress_processing_latency,
              :ingress_processing_latency_history
            ],
       do: :ingress_processing_latency

  defp product_family(:command_queue_depth), do: :command_queue_depth
  defp product_family(_product), do: nil

  defp latest_families(observables) do
    [
      {:contacts_phase, "contacts.phase" in observables},
      {:connection_state, any_observable?(observables, @connection_observable_ids)},
      {:ground_station_antenna_pointing_state,
       any_observable?(observables, @antenna_pointing_observable_ids)},
      {:link_rf_lock_state, any_observable?(observables, @link_rf_lock_observable_ids)},
      {:link_rf_frame_sync_state,
       any_observable?(observables, @link_rf_frame_sync_observable_ids)},
      {:link_rf_metric, any_observable?(observables, @link_rf_metric_observable_ids)},
      {:transport_bitrate, any_observable?(observables, @bitrate_observable_ids)},
      {:command_queue_depth, "commanding.queue_depth" in observables},
      {:ingress_processing_latency, "ingress.processing_latency_ms" in observables},
      {:managed_runtime_activity, any_observable?(observables, @managed_runtime_observable_ids)},
      {:transport_runtime_activity,
       any_observable?(observables, @transport_runtime_observable_ids)}
    ]
    |> enabled_families()
  end

  defp state_history_families(observables) do
    [
      {:contacts_phase, "contacts.phase" in observables},
      {:connection_state, any_observable?(observables, @connection_observable_ids)},
      {:ground_station_antenna_pointing_state,
       any_observable?(observables, @antenna_pointing_observable_ids)},
      {:link_rf, any_observable?(observables, @link_rf_lock_observable_ids)},
      {:link_rf_frame_sync_state,
       any_observable?(observables, @link_rf_frame_sync_observable_ids)}
    ]
    |> enabled_families()
  end

  defp metric_history_families(observables) do
    [
      {:link_rf_metric, any_observable?(observables, @link_rf_metric_observable_ids)},
      {:transport_bitrate, any_observable?(observables, @bitrate_observable_ids)},
      {:ingress_processing_latency, any_observable?(observables, @ingress_latency_observable_ids)}
    ]
    |> enabled_families()
  end

  defp enabled_families(families) do
    for {family, true} <- families, do: family
  end

  defp any_observable?(observables, family_observables) do
    Enum.any?(observables, &(&1 in family_observables))
  end

  defp aggregate_revision(
         prefix,
         families,
         organization_id,
         mission_id,
         adapter_opts,
         opts,
         default_funs
       ) do
    revisions =
      Enum.reduce(families, [], fn family, revisions ->
        case revision_for_family(
               family,
               organization_id,
               mission_id,
               adapter_opts,
               opts,
               default_funs
             ) do
          revision when is_binary(revision) and revision != "" ->
            [{family, revision} | revisions]

          _other ->
            revisions
        end
      end)

    combined_revision(revisions, prefix)
  end

  defp revision_for_family(
         nil,
         _organization_id,
         _mission_id,
         _adapter_opts,
         _opts,
         _default_funs
       ),
       do: nil

  defp revision_for_family(
         family,
         organization_id,
         mission_id,
         adapter_opts,
         opts,
         default_funs
       ) do
    provider_family = provider_family(family)

    revision_fun =
      Keyword.get(
        opts,
        Map.fetch!(@revision_options, provider_family),
        Keyword.fetch!(default_funs, provider_family)
      )

    revision_fun.(organization_id, mission_id, adapter_opts)
  end

  defp provider_family(:link_rf), do: :link_rf_lock_state
  defp provider_family(family), do: family

  defp combined_revision([], _prefix), do: nil

  defp combined_revision(revisions, prefix) do
    prefix <>
      ":" <>
      RuntimeCacheKey.fingerprint(%{
        family_revisions: Enum.sort_by(revisions, &elem(&1, 0))
      })
  end
end
