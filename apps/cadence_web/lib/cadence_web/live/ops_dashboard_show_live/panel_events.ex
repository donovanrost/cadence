defmodule CadenceWeb.OpsDashboardShowLive.PanelEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.Navigation

  def open_rename(socket) do
    socket
    |> assign(:panel, :rename)
    |> assign(:dashboard_activity_filter, nil)
    |> assign(:dashboard_activity_event_id, nil)
    |> assign(:dashboard_review_placement_id, nil)
  end

  def open_versions(socket, opts \\ []) do
    socket
    |> assign(:panel, :versions)
    |> assign(
      :dashboard_activity_filter,
      ActivityViewModel.normalize_filter(Keyword.get(opts, :activity_filter))
    )
    |> assign(:dashboard_activity_event_id, Keyword.get(opts, :activity_event_id))
    |> assign(:dashboard_review_placement_id, nil)
    |> assign_publish_validation(opts)
  end

  def open_activity_filter(socket, filter, opts \\ []) do
    activity_filter = ActivityViewModel.normalize_filter(filter)
    activity_event_id = socket.assigns[:dashboard_activity_event_id]

    socket
    |> open_versions(
      opts
      |> Keyword.put(:activity_filter, activity_filter)
      |> Keyword.put(:activity_event_id, activity_event_id)
    )
    |> Navigation.patch(ActivityNavigation.query(activity_filter, activity_event_id), opts)
  end

  def open_review_activity(socket, opts \\ []) do
    opts = Keyword.put(opts, :activity_filter, :open_comparison_reviews)
    open_versions(socket, opts)
  end

  def refresh_publish_readiness(socket, opts \\ []) do
    socket
    |> assign(:panel, :versions)
    |> refresh_publish_validation(opts)
  end

  def select_review_placement(socket, placement_id, opts \\ [])

  def select_review_placement(socket, placement_id, opts)
      when is_binary(placement_id) and placement_id != "" do
    socket
    |> assign(:panel, :versions)
    |> assign(:dashboard_activity_filter, :open_comparison_reviews)
    |> assign(:dashboard_activity_event_id, nil)
    |> assign(:dashboard_review_placement_id, placement_id)
    |> assign_publish_validation(opts)
    |> Navigation.patch(
      %{
        "panel" => "versions",
        "activity_filter" => "open_comparison_reviews",
        "activity_event" => nil,
        "selected_placement" => placement_id
      },
      opts
    )
  end

  def select_review_placement(socket, _placement_id, _opts), do: socket

  def select_activity_event(socket, event_id, opts \\ [])

  def select_activity_event(socket, event_id, opts) when is_binary(event_id) and event_id != "" do
    activity_filter = socket.assigns[:dashboard_activity_filter]

    socket
    |> assign(:panel, :versions)
    |> assign(:dashboard_activity_event_id, event_id)
    |> assign(:dashboard_review_placement_id, nil)
    |> assign_publish_validation(opts)
    |> Navigation.patch(ActivityNavigation.query(activity_filter, event_id), opts)
  end

  def select_activity_event(socket, _event_id, _opts), do: socket

  def open_diagnostics(socket) do
    socket
    |> assign(:panel, :diagnostics)
    |> assign(:dashboard_activity_filter, nil)
    |> assign(:dashboard_activity_event_id, nil)
    |> assign(:dashboard_review_placement_id, nil)
  end

  def close(socket, opts \\ []) do
    case socket.assigns.panel do
      {:evidence, _inspector} ->
        socket =
          socket
          |> assign(:panel, nil)
          |> assign(:dashboard_activity_filter, nil)
          |> assign(:dashboard_activity_event_id, nil)
          |> assign(:dashboard_review_placement_id, nil)
          |> assign(:dashboard_evidence_query, nil)

        patch(opts).(socket, DataLinkSelection.clear_panel_query(:evidence))

      _other ->
        socket
        |> assign(:panel, nil)
        |> assign(:dashboard_activity_filter, nil)
        |> assign(:dashboard_activity_event_id, nil)
        |> assign(:dashboard_review_placement_id, nil)
        |> assign(:data_link_action_outcome, nil)
        |> assign(:data_link_action_outcome_query, nil)
    end
  end

  defp assign_publish_validation(socket, opts) do
    Keyword.get(opts, :assign_publish_validation, &DocumentLifecycle.assign_publish_validation/1).(
      socket
    )
  end

  defp refresh_publish_validation(socket, opts) do
    Keyword.get(
      opts,
      :refresh_publish_validation,
      &DocumentLifecycle.refresh_publish_validation/2
    ).(
      socket,
      opts
    )
  end

  defp patch(opts) do
    Keyword.get(opts, :patch, &Navigation.patch/2)
  end
end
