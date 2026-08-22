defmodule Cadence.Dashboards.LimitSelectedClockAudit do
  @moduledoc """
  Builds and persists selected-clock audit events for dashboard limit analysis.

  These events record which limit clock and definition policy a dashboard used
  for non-observed limit analysis. They are derived from source frames and use
  deterministic ids so repeated refreshes of the same dashboard/source context
  update the same canonical operational event instead of appending duplicates.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Frame,
    PlannedSourceRequest,
    SourceResult
  }

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  @spec persist_source_results(
          DashboardResolveRequest.t(),
          [
            {PlannedSourceRequest.t(), SourceResult.t()}
          ],
          keyword()
        ) :: %{event_ids: [binary()], errors: [term()]}
  def persist_source_results(
        %DashboardResolveRequest{} = resolve_request,
        source_results,
        opts \\ []
      )
      when is_list(source_results) and is_list(opts) do
    events =
      source_results
      |> Enum.flat_map(fn
        {%PlannedSourceRequest{} = source_request, %SourceResult{} = source_result} ->
          events(resolve_request, source_request, source_result, opts)

        _other ->
          []
      end)

    persist_events(events)
  end

  @spec events(DashboardResolveRequest.t(), PlannedSourceRequest.t(), SourceResult.t(), keyword()) ::
          [OperationalEvent.t()]
  def events(resolve_request, source_request, source_result, opts \\ [])

  def events(
        %DashboardResolveRequest{} = resolve_request,
        %PlannedSourceRequest{logical_source: :limits} = source_request,
        %SourceResult{} = source_result,
        opts
      )
      when is_list(opts) do
    observed_at = Keyword.get_lazy(opts, :observed_at, &DateTime.utc_now/0)

    source_result.frames
    |> Enum.flat_map(fn
      %Frame{} = frame ->
        event_for_frame(resolve_request, source_request, source_result, frame, observed_at)

      _frame ->
        []
    end)
  end

  def events(_resolve_request, _source_request, _source_result, _opts), do: []

  defp event_for_frame(resolve_request, source_request, source_result, frame, observed_at) do
    meta = frame.meta || %{}

    with selected_clock when is_map(selected_clock) <- value(meta, :selected_limit_clock),
         semantics_mode when semantics_mode not in [nil, :observed, "observed"] <-
           value(meta, :semantics_mode) do
      observable_id =
        text(
          value(meta, :observable_id) || value(meta, :point_id) ||
            first(source_request.observables)
        )

      warning_codes = warning_codes(meta, source_result)
      severity = if :incomplete_limit_evaluation in warning_codes, do: :warning, else: :info

      [
        OperationalEvent.new(%{
          event_id:
            event_id(resolve_request, source_request, frame, observable_id, semantics_mode),
          organization_id: resolve_request.organization_id || source_request.organization_id,
          mission_id: resolve_request.mission_id || source_request.mission_id,
          occurred_at: observed_at,
          recorded_at: observed_at,
          effective_at: analysis_effective_at(frame, resolve_request),
          category: :limits,
          kind: :dashboard_limit_selected_clock,
          severity: severity,
          actor: %{kind: :system},
          subject: subject(observable_id),
          scope: scope(resolve_request, source_request, source_result, meta, observable_id),
          causality: %{
            correlation_id: correlation_id(resolve_request, source_request, observable_id),
            replay_run_id: value(meta, :replay_run_id)
          },
          payload:
            payload(
              resolve_request,
              source_request,
              source_result,
              frame,
              meta,
              selected_clock,
              warning_codes
            ),
          current: %{
            selected_limit_clock: selected_clock,
            semantics_mode: semantics_mode,
            warning_codes: warning_codes
          },
          metadata: %{
            source: "dashboard_limit_selected_clock_audit",
            deterministic?: true
          }
        })
      ]
    else
      _other -> []
    end
  end

  defp persist_events(events) do
    Enum.reduce(events, %{event_ids: [], errors: []}, fn event, acc ->
      case OperationalEvents.persist_event(event) do
        {:ok, %OperationalEvent{} = persisted} ->
          Map.update!(acc, :event_ids, &[persisted.event_id | &1])

        {:error, reason} ->
          Map.update!(acc, :errors, &[reason | &1])
      end
    end)
    |> Map.update!(:event_ids, &Enum.reverse/1)
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  defp event_id(resolve_request, source_request, frame, observable_id, semantics_mode) do
    hash =
      %{
        dashboard_id: resolve_request.dashboard_id || resolve_request.document.dashboard_id,
        request_id: source_request.request_id,
        frame_id: frame.frame_id,
        observable_id: observable_id,
        semantics_mode: semantics_mode,
        time_context: source_request.time_context,
        data_context: source_request.data_context,
        scope_context: source_request.scope_context
      }
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 24)

    "operational_event:dashboard_limit_selected_clock:#{hash}"
  end

  defp payload(
         resolve_request,
         source_request,
         source_result,
         frame,
         meta,
         selected_clock,
         warning_codes
       ) do
    %{
      dashboard_id: resolve_request.dashboard_id || resolve_request.document.dashboard_id,
      source_request_id: source_request.request_id,
      source_result_request_id: source_result.request_id,
      frame_id: frame.frame_id,
      observable_id: value(meta, :observable_id) || value(meta, :point_id),
      sampling: value(meta, :sampling),
      semantics_mode: value(meta, :semantics_mode),
      analysis_basis: value(meta, :analysis_basis),
      selected_limit_clock: selected_clock,
      selected_limit_definition_intervals: value(meta, :selected_limit_definition_intervals, []),
      warning_codes: warning_codes,
      missing_sample_ids: missing_sample_ids(source_result),
      returned_events: value(meta, :returned_events),
      source_sample_count: value(meta, :source_sample_count),
      observed_event_count: value(meta, :observed_event_count),
      divergence_count: value(meta, :divergence_count)
    }
    |> compact()
  end

  defp scope(resolve_request, source_request, source_result, meta, observable_id) do
    %{
      logical_source: :limits,
      point_id: observable_id,
      data_realm: value(meta, :realm) || value(source_request.data_context, :realm),
      data_source_id: value(meta, :data_source_id) || value(source_result.meta, :data_source_id),
      source_binding_id:
        value(meta, :source_binding_id) || value(source_result.meta, :source_binding_id),
      dataset: value(meta, :dataset),
      replay_run_id:
        value(meta, :replay_run_id) || value(source_request.time_context, :replay_run_id),
      dashboard_id: resolve_request.dashboard_id || resolve_request.document.dashboard_id,
      source_request_id: source_request.request_id
    }
    |> compact()
  end

  defp subject(nil), do: nil
  defp subject(observable_id), do: %{kind: :telemetry_point, id: observable_id}

  defp warning_codes(meta, %SourceResult{} = source_result) do
    frame_codes =
      meta
      |> value(:warning_codes, [])
      |> List.wrap()
      |> Enum.map(&atom_value/1)

    source_codes =
      source_result.warnings
      |> Enum.map(&Map.get(&1, :code))
      |> Enum.map(&atom_value/1)

    (frame_codes ++ source_codes)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp missing_sample_ids(%SourceResult{} = source_result) do
    source_result.warnings
    |> Enum.flat_map(fn warning ->
      warning
      |> Map.get(:details, %{})
      |> value(:missing_sample_ids, [])
      |> List.wrap()
    end)
    |> Enum.map(&text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp analysis_effective_at(%Frame{} = frame, %DashboardResolveRequest{} = resolve_request) do
    frame.fields
    |> Enum.find(&(&1.name == "time"))
    |> case do
      %{values: [%DateTime{} = first_time | _rest]} ->
        first_time

      _field ->
        value(resolve_request.time_context, :to) || value(resolve_request.time_context, :end)
    end
  end

  defp correlation_id(resolve_request, source_request, observable_id) do
    [
      resolve_request.dashboard_id || resolve_request.document.dashboard_id,
      source_request.request_id,
      observable_id
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp first([value | _rest]), do: value
  defp first(_values), do: nil

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp value(_map, _key, default), do: default

  defp atom_value(value) when is_atom(value), do: value

  defp atom_value(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp atom_value(_value), do: nil

  defp text(nil), do: nil
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value), do: to_string(value)

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] or value == %{} end)
    |> Map.new()
  end
end
