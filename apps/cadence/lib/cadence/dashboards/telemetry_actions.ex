defmodule Cadence.Dashboards.TelemetryActions do
  @moduledoc """
  Builds typed dashboard actions for telemetry exploration.

  These actions describe operator intent without embedding web routes. Web
  callers hydrate them into mission-local navigation.
  """

  alias Cadence.Dashboards.{DashboardAction, DataLink, DataLinks, PlannedSourceRequest}

  @spec explore_actions(PlannedSourceRequest.t(), binary() | nil, [map() | struct()], keyword()) ::
          [DashboardAction.t()]
  def explore_actions(%PlannedSourceRequest{} = request, observable_id, samples, opts \\ []) do
    sample = samples |> List.wrap() |> List.first()

    request
    |> DataLinks.request_context(observable_id, opts)
    |> explore_action(
      Keyword.merge(opts,
        point_id: observable_id,
        sample_id: attr(sample, :sample_id),
        selected_time: attr(sample, :receipt_time)
      )
    )
    |> List.wrap()
  end

  @spec explore_action_from_data_link(DataLink.t(), keyword()) :: DashboardAction.t() | nil
  def explore_action_from_data_link(link, opts \\ [])

  def explore_action_from_data_link(%DataLink{target: target} = link, opts)
      when target in [:telemetry_point, :telemetry_sample] do
    point_id =
      case link.target do
        :telemetry_point ->
          link.target_id

        :telemetry_sample ->
          Keyword.get(opts, :point_id) || context_value(link.context, :observable_id)
      end

    sample_id =
      case link.target do
        :telemetry_sample -> link.target_id
        :telemetry_point -> Keyword.get(opts, :sample_id)
      end

    explore_action(
      link.context,
      Keyword.merge(opts,
        point_id: point_id,
        sample_id: sample_id,
        selected_time: Keyword.get(opts, :selected_time),
        source: Keyword.get(opts, :source, :data_link_panel)
      )
    )
  end

  def explore_action_from_data_link(%DataLink{}, _opts), do: nil

  @spec explore_action(map(), keyword()) :: DashboardAction.t() | nil
  def explore_action(context, opts \\ [])

  def explore_action(context, opts) when is_map(context) do
    query =
      context
      |> explore_query(opts)
      |> compact_query()

    if map_size(query) > 0 do
      %DashboardAction{
        action_id: Keyword.get(opts, :action_id, "dashboard-telemetry-explore-action"),
        label: Keyword.get(opts, :label, "Explore telemetry"),
        target: :telemetry_explore,
        kind: :invoke,
        query: query,
        context: context,
        source: Keyword.get(opts, :source, :frame)
      }
    end
  end

  def explore_action(_context, _opts), do: nil

  defp explore_query(context, opts) do
    time_context = context_value(context, :time) || %{}
    data_context = context_value(context, :data) || %{}
    replay_run_id = replay_run_id(context, time_context, data_context)

    %{
      "point_id" => Keyword.get(opts, :point_id) || context_value(context, :observable_id),
      "sample_id" => Keyword.get(opts, :sample_id),
      "selected_time" => Keyword.get(opts, :selected_time),
      "time_mode" => context_value(time_context, :mode),
      "from" => context_value(time_context, :from) || context_value(time_context, :start),
      "to" => context_value(time_context, :to) || context_value(time_context, :end),
      "replay_run_id" => replay_run_id,
      "realm" => context_with_fallback(data_context, context, :realm),
      "data_view" => context_with_fallback(data_context, context, :view, :data_view),
      "logical_source" => context_value(context, :logical_source),
      "data_source_id" => context_with_fallback(data_context, context, :data_source_id),
      "source_binding_id" => context_with_fallback(data_context, context, :source_binding_id)
    }
  end

  defp context_with_fallback(primary, fallback, key),
    do: context_with_fallback(primary, fallback, key, key)

  defp context_with_fallback(primary, fallback, primary_key, fallback_key) do
    context_value(primary, primary_key) || context_value(fallback, fallback_key)
  end

  defp replay_run_id(context, time_context, data_context) do
    context_value(time_context, :replay_run_id) ||
      context_value(data_context, :replay_run_id) ||
      context_value(context, :replay_run_id)
  end

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {key, stringify(value)} end)
  end

  defp context_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp context_value(_map, _key), do: nil

  defp attr(nil, _key), do: nil
  defp attr(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp attr(_value, _key), do: nil

  defp stringify(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
