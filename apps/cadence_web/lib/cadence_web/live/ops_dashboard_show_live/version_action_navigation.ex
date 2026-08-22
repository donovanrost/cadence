defmodule CadenceWeb.OpsDashboardShowLive.VersionActionNavigation do
  @moduledoc false
  use CadenceWeb, :html

  def selected_activity_action_href(
        %{target: "data_sources", params: params} = action,
        %{mission_id: mission_id} = document,
        summary
      )
      when is_binary(mission_id) and mission_id != "" do
    params =
      params
      |> source_action_params(document, summary)
      |> maybe_put_selected_publish_issue(activity_action_issue_id(action))

    ~p"/missions/#{mission_id}/ops/data-sources?#{params}"
  end

  def selected_activity_action_href(
        %{target: "dashboard_editor", params: params} = action,
        %{mission_id: mission_id, dashboard_id: dashboard_id},
        _summary
      )
      when is_binary(mission_id) and mission_id != "" and is_binary(dashboard_id) and
             dashboard_id != "" do
    params =
      params
      |> dashboard_editor_action_params()
      |> maybe_put_selected_publish_issue(activity_action_issue_id(action))

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{params}"
  end

  def selected_activity_action_href(_action, _document, _summary), do: nil

  def publish_validation_issue_href(current_path, issue_id) do
    merge_query(current_path, %{"panel" => "versions", "selected_publish_issue" => issue_id})
  end

  def publish_validation_action_href(
        %{target: "data_sources"} = action,
        %{mission_id: mission_id} = document,
        selected_publish_issue_id
      )
      when is_binary(mission_id) do
    if mission_id == "" do
      nil
    else
      params =
        action
        |> Map.get(:params, %{})
        |> source_action_params(document)
        |> maybe_put_selected_publish_issue(selected_publish_issue_id)

      ~p"/missions/#{mission_id}/ops/data-sources?#{params}"
    end
  end

  def publish_validation_action_href(
        %{target: "dashboard_editor"} = action,
        %{mission_id: mission_id, dashboard_id: dashboard_id},
        selected_publish_issue_id
      )
      when is_binary(mission_id) and is_binary(dashboard_id) do
    if mission_id == "" or dashboard_id == "" do
      nil
    else
      params =
        action
        |> Map.get(:params, %{})
        |> dashboard_editor_action_params()
        |> maybe_put_selected_publish_issue(selected_publish_issue_id)

      ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{params}"
    end
  end

  def publish_validation_action_href(_action, _document, _selected_publish_issue_id), do: nil

  defp activity_action_issue_id(%{issue_id: issue_id}) when is_binary(issue_id), do: issue_id

  defp activity_action_issue_id(%{params: params}) when is_map(params) do
    Map.get(params, "selected_publish_issue") || Map.get(params, :selected_publish_issue)
  end

  defp activity_action_issue_id(_action), do: nil

  defp dashboard_editor_action_params(params) do
    params = normalize_source_action_params(params)

    params
    |> Map.take([
      "source_empty_reason",
      "unsupported_observables",
      "requested_observables",
      "requested_sampling",
      "supported_sampling",
      "requested_products",
      "requested_source_products",
      "supported_products",
      "requested_product_families",
      "supported_product_families"
    ])
    |> Map.merge(%{
      "panel" => "dashboard_editor",
      "selected_placement" => Map.get(params, "placement_id")
    })
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp maybe_put_selected_publish_issue(params, selected_publish_issue_id)
       when is_binary(selected_publish_issue_id) and selected_publish_issue_id != "" do
    Map.put_new(params, "selected_publish_issue", selected_publish_issue_id)
  end

  defp maybe_put_selected_publish_issue(params, _selected_publish_issue_id), do: params

  defp source_action_params(params, document, summary \\ nil) do
    params
    |> normalize_source_action_params()
    |> put_dashboard_return_params(document, summary)
  end

  defp normalize_source_action_params(params) when is_map(params), do: params
  defp normalize_source_action_params(_params), do: %{}

  defp put_dashboard_return_params(params, %{dashboard_id: dashboard_id}, summary)
       when is_binary(dashboard_id) and dashboard_id != "" do
    params
    |> Map.put_new("source_dashboard_id", dashboard_id)
    |> Map.put_new("source_return_panel", "versions")
    |> Map.put_new("source_return_activity_filter", "publish_readiness")
    |> put_source_return_activity_event(summary)
  end

  defp put_dashboard_return_params(params, _document, _summary), do: params

  defp put_source_return_activity_event(params, %{event_id: event_id})
       when is_binary(event_id) and event_id != "" do
    Map.put_new(params, "source_return_activity_event", event_id)
  end

  defp put_source_return_activity_event(params, _summary), do: params

  defp merge_query(path, params) do
    uri = URI.parse(path || "")

    query =
      uri.query
      |> decode_query()
      |> Map.merge(params)
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()

    %{uri | query: URI.encode_query(query)}
    |> URI.to_string()
  end

  defp decode_query(nil), do: %{}
  defp decode_query(query), do: URI.decode_query(query)
end
