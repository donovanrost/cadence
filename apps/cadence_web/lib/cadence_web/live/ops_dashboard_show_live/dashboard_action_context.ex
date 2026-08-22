defmodule CadenceWeb.OpsDashboardShowLive.DashboardActionContext do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Cadence.Dashboards
  alias Cadence.Dashboards.ComparisonReviewQueue
  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.Navigation

  @spec scoped_ids(Phoenix.LiveView.Socket.t()) :: {binary(), binary(), binary()}
  def scoped_ids(socket) do
    %{
      current_scope: %{organization_id: organization_id},
      current_mission: %{mission_id: mission_id},
      dashboard_document: %Document{dashboard_id: dashboard_id}
    } = socket.assigns

    {organization_id, mission_id, dashboard_id}
  end

  @spec actor_opts(Phoenix.LiveView.Socket.t()) :: keyword()
  def actor_opts(socket) do
    case socket.assigns.current_scope do
      %{user: %{user_id: user_id}} when is_binary(user_id) -> [actor_id: user_id]
      _scope -> []
    end
  end

  @spec refresh_lifecycle_events(Phoenix.LiveView.Socket.t(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def refresh_lifecycle_events(socket, opts \\ []) do
    {organization_id, mission_id, dashboard_id} = scoped_ids(socket)

    assign(
      socket,
      :dashboard_lifecycle_events,
      list_lifecycle_events_fn(opts).(organization_id, mission_id, dashboard_id)
    )
  end

  @spec refresh_lifecycle_events_and_review_queue(Phoenix.LiveView.Socket.t(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def refresh_lifecycle_events_and_review_queue(socket, opts \\ []) do
    {organization_id, mission_id, dashboard_id} = scoped_ids(socket)
    lifecycle_events = list_lifecycle_events_fn(opts).(organization_id, mission_id, dashboard_id)

    socket
    |> assign(:dashboard_lifecycle_events, lifecycle_events)
    |> assign(
      :dashboard_comparison_review_queue,
      comparison_review_queue_fn(opts).(
        organization_id,
        mission_id,
        dashboard_id,
        lifecycle_events
      )
    )
  end

  @spec target_activity(Phoenix.LiveView.Socket.t(), atom(), map(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def target_activity(socket, filter, %{dashboard_lifecycle_event_id: event_id}, opts)
      when is_atom(filter) and is_binary(event_id) and event_id != "" do
    socket
    |> assign(:panel, :versions)
    |> assign(:dashboard_activity_filter, filter)
    |> assign(:dashboard_activity_event_id, event_id)
    |> assign(:dashboard_review_placement_id, nil)
    |> Navigation.patch(ActivityNavigation.query(filter, event_id), opts)
  end

  def target_activity(socket, _filter, _event, _opts), do: socket

  @spec flash(Phoenix.LiveView.Socket.t(), :error | :info, binary(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def flash(socket, kind, message, opts \\ []) do
    put_flash_fn(opts).(socket, kind, message)
  end

  defp list_lifecycle_events_fn(opts) do
    Keyword.get(opts, :list_dashboard_lifecycle_events, &Dashboards.list_lifecycle_events/3)
  end

  defp comparison_review_queue_fn(opts) do
    Keyword.get(opts, :dashboard_comparison_review_queue, fn _organization_id,
                                                             _mission_id,
                                                             _dashboard_id,
                                                             lifecycle_events ->
      ComparisonReviewQueue.open_summary(lifecycle_events)
    end)
  end

  defp put_flash_fn(opts), do: Keyword.get(opts, :put_flash, &put_flash/3)
end
