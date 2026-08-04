defmodule Cadence.Dashboards.Sources.OperationalObservables.TransportBitrate do
  @moduledoc """
  Resolves latest and historical operational transport-bitrate products.
  """

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest, RuntimeCacheKey}

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    LatestFreshness,
    OperationalMetricFrames,
    TransportBitrateRows
  }

  alias Cadence.Reads.OperationalState
  alias Cadence.Reads.OperationalState.Snapshots, as: OperationalEventSnapshots

  @spec resolve_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_latest(request, organization_id, mission_id, source_context, adapter_opts, opts) do
    {transports, snapshots} = sources(organization_id, mission_id, adapter_opts, opts)

    transports
    |> TransportBitrateRows.latest(snapshots, request)
    |> LatestFreshness.annotate(request, opts)
    |> then(&OperationalMetricFrames.transport_bitrate_latest(request, &1, source_context))
  end

  @spec resolve_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: [Frame.t()]
  def resolve_history(request, organization_id, mission_id, source_context, adapter_opts, opts) do
    {transports, snapshots} = sources(organization_id, mission_id, adapter_opts, opts)

    transports
    |> TransportBitrateRows.history(snapshots, request)
    |> then(
      &OperationalMetricFrames.history(
        request,
        &1,
        :transport_bitrate_history,
        source_context
      )
    )
  end

  @spec default_revision(binary(), binary(), keyword()) :: binary()
  def default_revision(organization_id, mission_id, opts) do
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
          |> Enum.map(&snapshot_revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || &1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp sources(organization_id, mission_id, adapter_opts, opts) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)

    snapshots_fun =
      Keyword.get(
        opts,
        :transport_metric_snapshots_fun,
        &OperationalEventSnapshots.transport_bitrate/3
      )

    {
      transports_fun.(organization_id, mission_id, adapter_opts),
      snapshots_fun.(organization_id, mission_id, adapter_opts)
    }
  end

  defp default_transports(organization_id, mission_id, _opts) do
    OperationalState.list_transports(organization_id, mission_id)
  end

  defp transport_revision_entry(transport) do
    %{
      transport_id: attr(transport, :transport_id),
      display_name: attr(transport, :display_name),
      adapter_key: attr(transport, :adapter_key),
      metadata: attr(transport, :metadata)
    }
  end

  defp snapshot_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id(snapshot),
      adapter_key: attr(snapshot, :adapter_key),
      value: TransportBitrateRows.value(snapshot, attr(snapshot, :observable_id)),
      unit: attr(snapshot, :unit) || attr(snapshot, :value_unit),
      observed_at: attr(snapshot, :observed_at),
      source_event_id: attr(snapshot, :source_event_id)
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
