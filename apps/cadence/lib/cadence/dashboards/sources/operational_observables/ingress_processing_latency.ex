defmodule Cadence.Dashboards.Sources.OperationalObservables.IngressProcessingLatency do
  @moduledoc """
  Resolves latest and historical ingress processing-latency products.

  The family owns durable/runtime source selection, replay isolation, overlay
  precedence, row materialization, freshness, frame production, and revisions.
  """

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest, RuntimeCacheKey}

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    IngressProcessingLatencyRows,
    LatestFreshness,
    OperationalEventSnapshots,
    OperationalMetricFrames
  }

  alias Cadence.Telemetry.RuntimeHealth

  @spec resolve_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_latest(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    snapshots_fun =
      Keyword.get(
        opts,
        :ingress_processing_latency_snapshots_fun,
        Keyword.get(opts, :runtime_metric_snapshots_fun)
      )

    snapshots_fun
    |> latest_snapshots(organization_id, mission_id, adapter_opts, opts)
    |> IngressProcessingLatencyRows.latest(request, mission_id)
    |> LatestFreshness.annotate(request, opts)
    |> then(&OperationalMetricFrames.ingress_latency_latest(request, &1, source_context))
  end

  @spec resolve_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: [Frame.t()]
  def resolve_history(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    snapshots_fun =
      Keyword.get(
        opts,
        :ingress_processing_latency_history_snapshots_fun,
        Keyword.get(
          opts,
          :durable_ingress_processing_latency_snapshots_fun,
          &default_durable_snapshots/3
        )
      )

    organization_id
    |> snapshots_fun.(mission_id, adapter_opts)
    |> IngressProcessingLatencyRows.history(request, mission_id)
    |> then(
      &OperationalMetricFrames.history(
        request,
        &1,
        :ingress_processing_latency_history,
        source_context
      )
    )
  end

  @spec default_revision(binary(), binary(), keyword()) :: binary()
  def default_revision(organization_id, mission_id, opts) do
    "ingress_processing_latency:" <>
      RuntimeCacheKey.fingerprint(%{
        snapshots:
          organization_id
          |> default_snapshots(mission_id, opts)
          |> Enum.map(&revision_entry/1)
          |> Enum.sort_by(
            &{&1.source_endpoint_id || "", &1.spacecraft_id || "", &1.observed_at || ""}
          )
      })
  end

  defp latest_snapshots(nil, organization_id, mission_id, adapter_opts, opts) do
    default_snapshots(
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

  defp latest_snapshots(
         snapshots_fun,
         organization_id,
         mission_id,
         adapter_opts,
         _opts
       )
       when is_function(snapshots_fun, 3) do
    snapshots_fun.(organization_id, mission_id, adapter_opts)
  end

  defp default_snapshots(organization_id, mission_id, opts) do
    durable_snapshots_fun =
      Keyword.get(
        opts,
        :durable_ingress_processing_latency_snapshots_fun,
        &default_durable_snapshots/3
      )

    durable_snapshots = durable_snapshots_fun.(organization_id, mission_id, opts)

    if Keyword.get(opts, :replay_run_id) do
      durable_snapshots
    else
      runtime_snapshots_fun =
        Keyword.get(
          opts,
          :runtime_health_ingress_processing_latency_snapshots_fun,
          &default_runtime_snapshots/3
        )

      overlay(
        durable_snapshots,
        runtime_snapshots_fun.(organization_id, mission_id, opts)
      )
    end
  end

  defp default_durable_snapshots(organization_id, mission_id, opts) do
    OperationalEventSnapshots.ingress_latency(organization_id, mission_id, opts)
  end

  defp default_runtime_snapshots(_organization_id, _mission_id, _opts) do
    RuntimeHealth.snapshot()
    |> Map.get(:metrics, %{})
    |> Map.get(:ingress_processing_latency_ms, [])
  end

  defp overlay(durable_snapshots, runtime_snapshots) do
    durable_snapshots
    |> ranked_snapshots(0)
    |> Kernel.++(ranked_snapshots(runtime_snapshots, 1))
    |> Enum.reduce(%{}, &put_newer_snapshot/2)
    |> Map.values()
    |> Enum.map(fn {snapshot, _source_rank} -> snapshot end)
    |> Enum.sort_by(
      &{attr(&1, :source_endpoint_id) || "", attr(&1, :spacecraft_id) || "",
       attr(&1, :observed_at) || DateTime.from_unix!(0)},
      :desc
    )
  end

  defp ranked_snapshots(snapshots, source_rank) do
    snapshots
    |> Enum.map(&IngressProcessingLatencyRows.normalize_snapshot/1)
    |> Enum.map(&{&1, source_rank})
  end

  defp put_newer_snapshot({snapshot, source_rank} = candidate, acc) do
    key = snapshot_key(snapshot)
    current = Map.get(acc, key)

    if newer_snapshot?(candidate, current) do
      Map.put(acc, key, {snapshot, source_rank})
    else
      acc
    end
  end

  defp newer_snapshot?({_snapshot, _source_rank}, nil), do: true

  defp newer_snapshot?({snapshot, source_rank}, {current_snapshot, current_source_rank}) do
    case compare_observed_at(attr(snapshot, :observed_at), attr(current_snapshot, :observed_at)) do
      :gt -> true
      :eq -> source_rank >= current_source_rank
      :lt -> false
    end
  end

  defp compare_observed_at(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right)

  defp compare_observed_at(%DateTime{}, _right), do: :gt
  defp compare_observed_at(_left, %DateTime{}), do: :lt
  defp compare_observed_at(_left, _right), do: :eq

  defp snapshot_key(snapshot) do
    cond do
      present_text?(attr(snapshot, :source_endpoint_id)) ->
        {:source_endpoint, attr(snapshot, :mission_id), attr(snapshot, :source_endpoint_id)}

      present_text?(attr(snapshot, :spacecraft_id)) ->
        {:spacecraft, attr(snapshot, :mission_id), attr(snapshot, :spacecraft_id)}

      true ->
        {:mission, attr(snapshot, :mission_id)}
    end
  end

  defp revision_entry(snapshot) do
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
      link_id: link_id(snapshot),
      adapter_key: attr(snapshot, :adapter_key),
      value: IngressProcessingLatencyRows.value(snapshot),
      unit: attr(snapshot, :unit) || "ms",
      observed_at: attr(snapshot, :observed_at),
      error?: attr(snapshot, :error?) || false,
      replay_run_id: attr(snapshot, :replay_run_id)
    }
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

  defp metadata_attr(value, key), do: value |> attr(:metadata) |> attr(key)

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""
end
