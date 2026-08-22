defmodule Cadence.Dashboards.SourceRegistry.SourceHealthLookup do
  @moduledoc """
  Resolves injected or persisted source-health status and its effective interval.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ResolvedSourceBinding}

  alias Cadence.DataSources.{SourceHealthEvent, SourceHealthStatus}

  alias Cadence.Dashboards.SourceRegistry.{OperationalIntervalProvenance, SourceIdentity}
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Reads.DataSources

  @spec fetch(PlannedSourceRequest.t(), ResolvedSourceBinding.t(), keyword()) ::
          {:ok, SourceHealthStatus.t()} | {:error, :source_health_status_not_found}
  def fetch(%PlannedSourceRequest{} = request, %ResolvedSourceBinding{} = resolved_binding, opts)
      when is_list(opts) do
    case injected_status(request, resolved_binding, opts) do
      %SourceHealthStatus{} = status ->
        {:ok, status}

      nil ->
        DataSources.fetch_source_health_for_identity(
          SourceIdentity.from(request, resolved_binding)
        )
    end
  end

  @spec interval(
          PlannedSourceRequest.t(),
          ResolvedSourceBinding.t(),
          SourceHealthStatus.t(),
          keyword()
        ) :: EffectiveInterval.t() | nil
  def interval(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        %SourceHealthStatus{} = status,
        opts
      )
      when is_list(opts) do
    identity = SourceIdentity.from(request, resolved_binding)

    if interval_lookup_enabled?(opts) do
      interval_opts =
        [
          at: status.last_seen_at || status.observed_at,
          logical_source: Map.get(identity, :logical_source),
          data_source_id: Map.get(identity, :data_source_id),
          source_binding_id: Map.get(identity, :source_binding_id),
          realm: Map.get(identity, :realm),
          dataset: Map.get(identity, :dataset),
          replay_run_id: Map.get(identity, :replay_run_id)
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      request.organization_id
      |> OperationalIntervalProvenance.list(
        :source_health,
        request.mission_id,
        interval_opts,
        opts
      )
      |> interval_for_status(status)
    end
  end

  defp injected_status(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding,
         opts
       ) do
    opts
    |> Keyword.get(:source_health_statuses, [])
    |> List.wrap()
    |> status_for(request, resolved_binding)
  end

  defp status_for([], %PlannedSourceRequest{}, %ResolvedSourceBinding{}), do: nil

  defp status_for(
         source_health_statuses,
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       ) do
    exact_key =
      request
      |> SourceIdentity.from(resolved_binding)
      |> SourceHealthEvent.source_health_key()

    source_key =
      request
      |> SourceIdentity.from(resolved_binding)
      |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
      |> SourceHealthEvent.source_health_key()

    Enum.find(
      source_health_statuses,
      &(status_value(&1, :source_health_key) == exact_key)
    ) ||
      Enum.find(
        source_health_statuses,
        &(status_value(&1, :source_health_key) == source_key)
      )
  end

  defp status_value(%SourceHealthStatus{} = status, key), do: Map.get(status, key)

  defp status_value(status, key) when is_map(status),
    do: Map.get(status, key, Map.get(status, Atom.to_string(key)))

  defp status_value(_status, _key), do: nil

  defp interval_lookup_enabled?(opts) do
    Keyword.get(opts, :persisted?, false) == true or
      OperationalIntervalProvenance.reader_configured?(:source_health, opts)
  end

  defp interval_for_status(intervals, %SourceHealthStatus{} = status) do
    Enum.find(List.wrap(intervals), fn interval ->
      interval_matches_status?(interval, status)
    end) || OperationalIntervalProvenance.unique(List.wrap(intervals))
  end

  defp interval_matches_status?(
         %EffectiveInterval{} = interval,
         %SourceHealthStatus{} = status
       ) do
    payload = interval.payload || %{}

    get_attr(payload, :source_health_event_id) == status.source_health_event_id or
      interval.source_event_id == source_health_operational_event_id(status)
  end

  defp interval_matches_status?(_interval, _status), do: false

  defp source_health_operational_event_id(%SourceHealthStatus{} = status) do
    replay_run_id = status_value(status, :replay_run_id)
    source_health_event_id = status_value(status, :source_health_event_id)

    cond do
      is_binary(replay_run_id) and replay_run_id != "" and is_binary(source_health_event_id) ->
        "operational_event:source_health_event:#{replay_run_id}:#{source_health_event_id}"

      is_binary(source_health_event_id) ->
        "operational_event:source_health_event:#{source_health_event_id}"

      true ->
        nil
    end
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
