defmodule Cadence.Dashboards.Sources.OperationalObservables.LinkRf do
  @moduledoc """
  Resolves RF lock, frame-synchronization, and numeric RF metric products.
  """

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest, RuntimeCacheKey}

  alias Cadence.Dashboards.Sources.OperationalObservables.{
    LatestFreshness,
    LinkRfMetricRows,
    LinkRfStateFrames,
    LinkRfStateRows,
    OperationalMetricFrames
  }

  alias Cadence.Reads.OperationalState
  alias Cadence.Reads.OperationalState.Snapshots, as: OperationalEventSnapshots

  @spec resolve_lock_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_lock_latest(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {transports, snapshots} =
      sources(
        organization_id,
        mission_id,
        adapter_opts,
        opts,
        :link_rf_lock_snapshots_fun,
        &OperationalEventSnapshots.link_rf_lock/3
      )

    transports
    |> LinkRfStateRows.lock_latest(snapshots, request)
    |> LatestFreshness.annotate(request, opts)
    |> then(&LinkRfStateFrames.lock_latest(request, &1, source_context))
  end

  @spec resolve_lock_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_lock_history(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {transports, snapshots} =
      sources(
        organization_id,
        mission_id,
        adapter_opts,
        opts,
        :link_rf_lock_snapshots_fun,
        &OperationalEventSnapshots.link_rf_lock/3
      )

    transports
    |> LinkRfStateRows.lock_history(snapshots, request)
    |> then(&LinkRfStateFrames.lock_history(request, &1, source_context))
  end

  @spec resolve_frame_sync_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_frame_sync_latest(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {transports, snapshots} =
      sources(
        organization_id,
        mission_id,
        adapter_opts,
        opts,
        :link_rf_frame_sync_snapshots_fun,
        &OperationalEventSnapshots.link_rf_frame_sync/3
      )

    transports
    |> LinkRfStateRows.frame_sync_latest(snapshots, request)
    |> LatestFreshness.annotate(request, opts)
    |> then(&LinkRfStateFrames.frame_sync_latest(request, &1, source_context))
  end

  @spec resolve_frame_sync_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_frame_sync_history(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {transports, snapshots} =
      sources(
        organization_id,
        mission_id,
        adapter_opts,
        opts,
        :link_rf_frame_sync_snapshots_fun,
        &OperationalEventSnapshots.link_rf_frame_sync/3
      )

    transports
    |> LinkRfStateRows.frame_sync_history(snapshots, request)
    |> then(&LinkRfStateFrames.frame_sync_history(request, &1, source_context))
  end

  @spec resolve_metric_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_metric_latest(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {transports, snapshots} = metric_sources(organization_id, mission_id, adapter_opts, opts)

    request.observables
    |> LinkRfMetricRows.latest(transports, snapshots, request)
    |> LatestFreshness.annotate(request, opts)
    |> then(&OperationalMetricFrames.link_rf_latest(request, &1, source_context))
  end

  @spec resolve_metric_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: [Frame.t()]
  def resolve_metric_history(
        request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {transports, snapshots} = metric_sources(organization_id, mission_id, adapter_opts, opts)

    request.observables
    |> LinkRfMetricRows.history(transports, snapshots, request)
    |> then(
      &OperationalMetricFrames.history(
        request,
        &1,
        :link_rf_metric_history,
        source_context
      )
    )
  end

  @spec default_lock_revision(binary(), binary(), keyword()) :: binary()
  def default_lock_revision(organization_id, mission_id, opts) do
    revision(
      "link_rf_lock_state",
      organization_id,
      mission_id,
      opts,
      &OperationalEventSnapshots.link_rf_lock/3,
      &lock_revision_entry/1
    )
  end

  @spec default_frame_sync_revision(binary(), binary(), keyword()) :: binary()
  def default_frame_sync_revision(organization_id, mission_id, opts) do
    revision(
      "link_rf_frame_sync_state",
      organization_id,
      mission_id,
      opts,
      &OperationalEventSnapshots.link_rf_frame_sync/3,
      &frame_sync_revision_entry/1
    )
  end

  @spec default_metric_revision(binary(), binary(), keyword()) :: binary()
  def default_metric_revision(organization_id, mission_id, opts) do
    "link_rf_metric:" <>
      RuntimeCacheKey.fingerprint(%{
        transports: revision_transports(organization_id, mission_id, opts),
        snapshots:
          organization_id
          |> OperationalEventSnapshots.link_rf_metric(mission_id, opts)
          |> Enum.map(&metric_revision_entry/1)
          |> Enum.sort_by(
            &{&1.observable_id || "", &1.transport_id || &1.resource_id || "",
             &1.observed_at || ""}
          )
      })
  end

  defp sources(
         organization_id,
         mission_id,
         adapter_opts,
         opts,
         snapshots_option,
         default_snapshots_fun
       ) do
    transports_fun = Keyword.get(opts, :transports_fun, &default_transports/3)
    snapshots_fun = Keyword.get(opts, snapshots_option, default_snapshots_fun)

    {
      transports_fun.(organization_id, mission_id, adapter_opts),
      snapshots_fun.(organization_id, mission_id, adapter_opts)
    }
  end

  defp metric_sources(organization_id, mission_id, adapter_opts, opts) do
    sources(
      organization_id,
      mission_id,
      adapter_opts,
      opts,
      :link_rf_metric_snapshots_fun,
      &OperationalEventSnapshots.link_rf_metric/3
    )
  end

  defp revision(prefix, organization_id, mission_id, opts, snapshots_fun, entry_fun) do
    prefix <>
      ":" <>
      RuntimeCacheKey.fingerprint(%{
        transports: revision_transports(organization_id, mission_id, opts),
        snapshots:
          organization_id
          |> snapshots_fun.(mission_id, opts)
          |> Enum.map(entry_fun)
          |> Enum.sort_by(&{&1.transport_id || &1.resource_id || "", &1.observed_at || ""})
      })
  end

  defp revision_transports(organization_id, mission_id, opts) do
    organization_id
    |> default_transports(mission_id, opts)
    |> Enum.map(&transport_revision_entry/1)
    |> Enum.sort_by(&(&1.transport_id || ""))
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

  defp lock_revision_entry(snapshot) do
    state_revision_entry(snapshot, LinkRfStateRows.lock_state(snapshot))
  end

  defp frame_sync_revision_entry(snapshot) do
    state_revision_entry(snapshot, LinkRfStateRows.frame_sync_state(snapshot))
  end

  defp state_revision_entry(snapshot, state) do
    snapshot
    |> base_revision_entry()
    |> Map.put(:state, state)
  end

  defp metric_revision_entry(snapshot) do
    observable_id = LinkRfMetricRows.observable_id(snapshot)

    snapshot
    |> base_revision_entry()
    |> Map.merge(%{
      observable_id: observable_id,
      value: LinkRfMetricRows.value(snapshot, observable_id),
      unit: LinkRfMetricRows.unit(snapshot, observable_id)
    })
  end

  defp base_revision_entry(snapshot) do
    %{
      observable_id: attr(snapshot, :observable_id),
      resource_id: attr(snapshot, :resource_id),
      transport_id: attr(snapshot, :transport_id),
      source_endpoint_id:
        attr(snapshot, :source_endpoint_id) || attr(snapshot, :source_endpoint_ref),
      ground_station_id: attr(snapshot, :ground_station_id) || attr(snapshot, :antenna_id),
      link_id: link_id(snapshot),
      adapter_key: attr(snapshot, :adapter_key),
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
