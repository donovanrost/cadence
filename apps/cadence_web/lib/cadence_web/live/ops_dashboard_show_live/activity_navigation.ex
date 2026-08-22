defmodule CadenceWeb.OpsDashboardShowLive.ActivityNavigation do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel
  alias CadenceWeb.OpsDashboardShowLive.RouteQuery

  def query(activity_filter, event_or_id \\ nil, opts \\ []) do
    %{
      "panel" => "versions",
      "activity_filter" => ActivityViewModel.filter_value(activity_filter),
      "activity_event" => event_id(event_or_id),
      "selected_placement" => selected_placement(opts)
    }
  end

  def link(current_path, activity_filter, event_or_id, opts \\ []) when is_binary(current_path) do
    current_path
    |> URI.parse()
    |> put_query(activity_filter, event_or_id, opts)
    |> URI.to_string()
  end

  def open_comparison_review_link(current_path, event_or_id, opts \\ [])
      when is_binary(current_path) do
    link(current_path, :open_comparison_reviews, event_or_id, opts)
  end

  def event_id(event_id) when is_binary(event_id), do: event_id

  def event_id(%{dashboard_lifecycle_event_id: event_id}) when is_binary(event_id), do: event_id

  def event_id(%{"dashboard_lifecycle_event_id" => event_id}) when is_binary(event_id),
    do: event_id

  def event_id(_event), do: nil

  defp put_query(%URI{} = uri, activity_filter, event_or_id, opts) do
    query =
      (uri.query || "")
      |> URI.decode_query()
      |> RouteQuery.merge(query(activity_filter, event_or_id, opts))

    %{uri | query: RouteQuery.encode(query)}
  end

  defp selected_placement(opts) when is_list(opts) do
    case Keyword.get(opts, :selected_placement) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _value ->
        nil
    end
  end
end
