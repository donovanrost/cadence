defmodule CadenceWeb.OpsDashboardShowLive.RouteQuery do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQueryParams

  @runtime_query_keys [
    "spacecraft_id",
    "scope_kind",
    "scope_id",
    "scope_ids",
    "time_mode",
    "from",
    "to",
    "replay_run_id",
    "realm",
    "data_view",
    "compare_data_view",
    "data_source_id",
    "source_binding_id",
    "limit_mode"
  ]

  @spec current(Phoenix.LiveView.Socket.t() | map()) :: map()
  def current(%{assigns: assigns}), do: current(assigns)
  def current(assigns) when is_map(assigns), do: RuntimeQuery.current_query(assigns)
  def current(_assigns), do: %{}

  @spec merge(map(), map()) :: map()
  def merge(base_query, overrides) when is_map(base_query) and is_map(overrides) do
    base_query
    |> Map.merge(Map.new(overrides))
    |> RuntimeQueryParams.compact()
  end

  def merge(base_query, _overrides) when is_map(base_query),
    do: RuntimeQueryParams.compact(base_query)

  def merge(_base_query, overrides) when is_map(overrides),
    do: RuntimeQueryParams.compact(overrides)

  def merge(_base_query, _overrides), do: %{}

  @spec current_with(Phoenix.LiveView.Socket.t() | map(), map()) :: map()
  def current_with(socket_or_assigns, overrides \\ %{}) do
    socket_or_assigns
    |> current()
    |> merge(overrides)
  end

  @spec encode(map()) :: binary() | nil
  def encode(query) when is_map(query) do
    query =
      query
      |> RuntimeQueryParams.compact()

    if map_size(query) == 0, do: nil, else: URI.encode_query(query)
  end

  def encode(_query), do: nil

  @spec runtime_restore_overrides(map() | nil) :: map()
  def runtime_restore_overrides(runtime_query) when is_map(runtime_query) do
    cleared_runtime_query()
    |> Map.merge(Map.take(runtime_query, @runtime_query_keys))
  end

  def runtime_restore_overrides(_runtime_query), do: cleared_runtime_query()

  @spec runtime_query_keys() :: [binary()]
  def runtime_query_keys, do: @runtime_query_keys

  defp cleared_runtime_query do
    Map.new(@runtime_query_keys, &{&1, nil})
  end
end
