defmodule CadenceWeb.OpsDashboardShowLive.ActivityViewModel do
  @moduledoc false

  alias Cadence.Dashboards.ComparisonReviewQueue

  @version_change_event_types [:published, :reverted, :archived, :restored]
  @comparison_review_event_types [:comparison_review_requested, :comparison_review_resolved]
  @health_snapshot_event_types [:health_snapshot_captured]
  @publish_readiness_event_types [:publish_readiness_checked]

  def build(events, filter, opts \\ []) when is_list(events) do
    mode = activity_mode(filter)
    open_summary = open_summary(events, opts)
    selected_placement_id = Keyword.get(opts, :selected_placement_id)
    queue_state = queue_state(mode, open_summary, selected_placement_id)

    %{
      mode: mode,
      title: activity_title(mode),
      filter_value: activity_filter_value(mode),
      filter_label: activity_filter_label(mode),
      visible_events: visible_events(events, mode, open_summary),
      total_count: length(events),
      open_summary: open_summary,
      open_review_queue: open_review_queue(open_summary, mode),
      queue_state: queue_state,
      queue_state_value: queue_state_value(queue_state),
      queue_message: queue_message(queue_state)
    }
  end

  def normalize_filter(:open_comparison_reviews), do: :open_comparison_reviews
  def normalize_filter(:comparison_reviews), do: :comparison_reviews
  def normalize_filter(:version_changes), do: :version_changes
  def normalize_filter(:health_snapshots), do: :health_snapshots
  def normalize_filter(:publish_readiness), do: :publish_readiness
  def normalize_filter(:all), do: nil
  def normalize_filter(nil), do: nil
  def normalize_filter(""), do: nil
  def normalize_filter("all"), do: nil
  def normalize_filter("open_comparison_reviews"), do: :open_comparison_reviews
  def normalize_filter("comparison_reviews"), do: :comparison_reviews
  def normalize_filter("version_changes"), do: :version_changes
  def normalize_filter("health_snapshots"), do: :health_snapshots
  def normalize_filter("publish_readiness"), do: :publish_readiness
  def normalize_filter(_filter), do: nil

  def filter_value(filter) do
    filter
    |> activity_mode()
    |> activity_filter_value()
  end

  defp open_summary(_events, opts) do
    case Keyword.get(opts, :open_summary) do
      %{requests: requests, count: count} = summary
      when is_list(requests) and is_integer(count) ->
        summary

      _missing ->
        ComparisonReviewQueue.open_summary([])
    end
  end

  defp visible_events(_events, :open_comparison_reviews, %{requests: requests})
       when is_list(requests) do
    requests
    |> ordered_lifecycle_events()
  end

  defp visible_events(events, :comparison_reviews, _open_summary) when is_list(events) do
    visible_events_by_type(events, @comparison_review_event_types)
  end

  defp visible_events(events, :version_changes, _open_summary) when is_list(events) do
    visible_events_by_type(events, @version_change_event_types)
  end

  defp visible_events(events, :health_snapshots, _open_summary) when is_list(events) do
    visible_events_by_type(events, @health_snapshot_event_types)
  end

  defp visible_events(events, :publish_readiness, _open_summary) when is_list(events) do
    visible_events_by_type(events, @publish_readiness_event_types)
  end

  defp visible_events(events, _mode, _open_summary) when is_list(events) do
    ordered_lifecycle_events(events)
  end

  defp visible_events_by_type(events, event_types) do
    events
    |> Enum.filter(&(event_type(&1) in event_types))
    |> ordered_lifecycle_events()
  end

  defp ordered_lifecycle_events(events) do
    Enum.sort_by(events, &lifecycle_event_sort_key/1, :desc)
  end

  defp lifecycle_event_sort_key(event) when is_map(event) do
    occurred_at =
      case Map.get(event, :occurred_at) || Map.get(event, "occurred_at") do
        %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
        _missing -> 0
      end

    event_id =
      Map.get(event, :dashboard_lifecycle_event_id) ||
        Map.get(event, "dashboard_lifecycle_event_id")

    {occurred_at, event_id}
  end

  defp event_type(event) when is_map(event),
    do: Map.get(event, :event_type) || Map.get(event, "event_type")

  defp activity_mode(filter), do: normalize_filter(filter) || :all

  defp activity_title(:comparison_reviews), do: "Review Activity"
  defp activity_title(:version_changes), do: "Version Activity"
  defp activity_title(:health_snapshots), do: "Health Snapshots"
  defp activity_title(:publish_readiness), do: "Publish Readiness"
  defp activity_title(:open_comparison_reviews), do: "Review Queue"
  defp activity_title(_mode), do: "Activity"

  defp activity_filter_value(:comparison_reviews), do: "comparison_reviews"
  defp activity_filter_value(:version_changes), do: "version_changes"
  defp activity_filter_value(:health_snapshots), do: "health_snapshots"
  defp activity_filter_value(:publish_readiness), do: "publish_readiness"
  defp activity_filter_value(:open_comparison_reviews), do: "open_comparison_reviews"
  defp activity_filter_value(_mode), do: ""

  defp activity_filter_label(:comparison_reviews), do: "Reviews"
  defp activity_filter_label(:version_changes), do: "Version changes"
  defp activity_filter_label(:health_snapshots), do: "Health snapshots"
  defp activity_filter_label(:publish_readiness), do: "Publish readiness"
  defp activity_filter_label(:open_comparison_reviews), do: "Open reviews"
  defp activity_filter_label(_mode), do: "All activity"

  defp open_review_queue(%{requests: requests}, :open_comparison_reviews), do: requests
  defp open_review_queue(_open_summary, _mode), do: []

  defp queue_state(:open_comparison_reviews, %{count: 0}, _selected_placement_id), do: :empty

  defp queue_state(
         :open_comparison_reviews,
         %{placement_ids: placement_ids},
         selected_placement_id
       )
       when is_binary(selected_placement_id) and selected_placement_id != "" do
    if selected_placement_id in placement_ids, do: :open, else: :selection_stale
  end

  defp queue_state(:open_comparison_reviews, _open_summary, _selected_placement_id), do: :open
  defp queue_state(_mode, _open_summary, _selected_placement_id), do: :not_applicable

  defp queue_state_value(:not_applicable), do: ""
  defp queue_state_value(state), do: Atom.to_string(state)

  defp queue_message(:empty), do: "No open comparison reviews."

  defp queue_message(:selection_stale),
    do: "Selected review placement is no longer part of the open review queue."

  defp queue_message(_state), do: nil
end
