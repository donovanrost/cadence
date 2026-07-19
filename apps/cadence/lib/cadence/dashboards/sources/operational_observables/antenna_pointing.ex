defmodule Cadence.Dashboards.Sources.OperationalObservables.AntennaPointing do
  @moduledoc """
  Resolves latest and historical ground-station antenna-pointing products.
  """

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest, RuntimeCacheKey}

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    AntennaPointingFrames,
    AntennaPointingRows,
    LatestFreshness,
    OperationalEventSnapshots
  }

  alias Cadence.SourceEndpoints

  @spec resolve_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_latest(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {source_endpoints, snapshots} =
      sources(organization_id, mission_id, adapter_opts, opts)

    source_endpoints
    |> AntennaPointingRows.latest(snapshots, request)
    |> LatestFreshness.annotate(request, opts)
    |> then(&AntennaPointingFrames.latest(request, &1, source_context))
  end

  @spec resolve_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_history(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {source_endpoints, snapshots} =
      sources(organization_id, mission_id, adapter_opts, opts)

    source_endpoints
    |> AntennaPointingRows.history(snapshots, request)
    |> then(&AntennaPointingFrames.history(request, &1, source_context))
  end

  @spec default_revision(binary(), binary(), keyword()) :: binary()
  def default_revision(organization_id, mission_id, opts) do
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
          |> Enum.map(&snapshot_revision_entry/1)
          |> Enum.sort_by(&{&1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp sources(organization_id, mission_id, adapter_opts, opts) do
    source_endpoints_fun = Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

    snapshots_fun =
      Keyword.get(
        opts,
        :antenna_pointing_snapshots_fun,
        &OperationalEventSnapshots.antenna_pointing/3
      )

    {
      source_endpoints_fun.(organization_id, mission_id, adapter_opts),
      snapshots_fun.(organization_id, mission_id, adapter_opts)
    }
  end

  defp default_source_endpoints(organization_id, mission_id, _opts) do
    SourceEndpoints.list_source_endpoints(organization_id, mission_id)
  end

  defp source_endpoint_revision_entry(source_endpoint) do
    %{
      source_endpoint_id: attr(source_endpoint, :source_endpoint_id),
      display_name: attr(source_endpoint, :display_name),
      adapter_key: attr(source_endpoint, :adapter_key),
      metadata: attr(source_endpoint, :metadata)
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
      state: AntennaPointingRows.state(snapshot),
      observed_at: attr(snapshot, :observed_at)
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
