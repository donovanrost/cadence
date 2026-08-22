defmodule CadenceWeb.OpsDashboardShowLive.RuntimeResult do
  @moduledoc false

  alias Cadence.Dashboards.DashboardResolveResult

  @type result :: DashboardResolveResult.t() | map() | nil

  @spec resolve_mode(result()) :: atom() | nil
  def resolve_mode(nil), do: nil
  def resolve_mode(%DashboardResolveResult{resolve_mode: resolve_mode}), do: resolve_mode

  def resolve_mode(result) when is_map(result),
    do: Map.get(result, :resolve_mode, Map.get(result, "resolve_mode"))

  def resolve_mode(_result), do: nil

  @spec resolve_mode_text(result()) :: binary() | nil
  def resolve_mode_text(result) do
    case resolve_mode(result) do
      nil -> nil
      resolve_mode when is_atom(resolve_mode) -> Atom.to_string(resolve_mode)
      resolve_mode when is_binary(resolve_mode) -> resolve_mode
      resolve_mode -> inspect(resolve_mode)
    end
  end

  @spec frames_by_placement(result()) :: map()
  def frames_by_placement(nil), do: %{}

  def frames_by_placement(%DashboardResolveResult{frames_by_placement: frames_by_placement}),
    do: map_or_empty(frames_by_placement)

  def frames_by_placement(result) when is_map(result) do
    result
    |> Map.get(:frames_by_placement, Map.get(result, "frames_by_placement", %{}))
    |> map_or_empty()
  end

  def frames_by_placement(_result), do: %{}

  @spec placement_frames(result(), binary()) :: term() | nil
  def placement_frames(result, placement_id) when is_binary(placement_id) do
    result
    |> frames_by_placement()
    |> Map.get(placement_id)
  end

  def placement_frames(_result, _placement_id), do: nil

  @spec plan_metadata(result()) :: map()
  def plan_metadata(nil), do: %{}

  def plan_metadata(%DashboardResolveResult{plan_metadata: plan_metadata}),
    do: map_or_empty(plan_metadata)

  def plan_metadata(result) when is_map(result) do
    result
    |> Map.get(:plan_metadata, Map.get(result, "plan_metadata", %{}))
    |> map_or_empty()
  end

  def plan_metadata(_result), do: %{}

  @spec metadata(result(), atom() | binary()) :: term() | nil
  def metadata(result, key), do: map_value(plan_metadata(result), key)

  @spec metadata_path(result(), [atom() | binary()]) :: term() | nil
  def metadata_path(result, path) when is_list(path) do
    Enum.reduce_while(path, plan_metadata(result), fn key, acc ->
      case acc do
        map when is_map(map) -> {:cont, map_value(map, key)}
        _value -> {:halt, nil}
      end
    end)
  end

  @spec boolean_metadata?(result(), atom() | binary()) :: boolean()
  def boolean_metadata?(result, key), do: metadata(result, key) == true

  @spec planned_source_requests(result()) :: [term()]
  def planned_source_requests(nil), do: []

  def planned_source_requests(%DashboardResolveResult{planned_source_requests: requests}),
    do: list_or_empty(requests)

  def planned_source_requests(result) when is_map(result) do
    result
    |> Map.get(:planned_source_requests, Map.get(result, "planned_source_requests", []))
    |> list_or_empty()
  end

  def planned_source_requests(_result), do: []

  @spec first_planned_source_request(result()) :: term() | nil
  def first_planned_source_request(result) do
    result
    |> planned_source_requests()
    |> List.first()
  end

  @spec dashboard_warnings(result()) :: [term()]
  def dashboard_warnings(nil), do: []

  def dashboard_warnings(%DashboardResolveResult{dashboard_warnings: warnings}),
    do: list_or_empty(warnings)

  def dashboard_warnings(result) when is_map(result) do
    result
    |> Map.get(:dashboard_warnings, Map.get(result, "dashboard_warnings", []))
    |> list_or_empty()
  end

  def dashboard_warnings(_result), do: []

  @spec live_tick?(result()) :: boolean()
  def live_tick?(result), do: resolve_mode(result) == :live_tick

  defp map_or_empty(map) when is_map(map), do: map
  defp map_or_empty(_value), do: %{}

  defp list_or_empty(list) when is_list(list), do: list
  defp list_or_empty(_value), do: []

  defp map_value(map, key) when is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_value(map, key) when is_binary(key) do
    Map.get(map, key, Map.get(map, existing_atom(key)))
  end

  defp existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
