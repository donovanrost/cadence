defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityRow do
  @moduledoc false

  alias Cadence.Dashboards.LifecycleEvent
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewFocus

  def request(event, lifecycle_events, selected_placement_id) when is_list(lifecycle_events) do
    if request_event?(event) do
      summary = ComparisonReviewFocus.request_summary(event, lifecycle_events)
      workflow_point_ids = workflow_request_point_ids(summary.findings)
      bulk_decision_items = bulk_decision_items(summary.findings)
      source_context = source_context(summary.findings)

      %{
        render?: true,
        event_id: summary.event_id,
        schema: summary.schema,
        kind: summary.kind,
        status: summary.status,
        resolved?: summary.resolved?,
        resolution_event_id: summary.resolution_event_id,
        result_event_id: summary.resolution_event_id,
        target_event_id: summary.event_id,
        open_count_text: summary.open_count_text,
        placements_attr: summary.placements_attr,
        workflow_request_available?: workflow_point_ids != [],
        workflow_request_point_ids_attr: Enum.join(workflow_point_ids, ","),
        workflow_request_point_count_text: Integer.to_string(length(workflow_point_ids)),
        bulk_decision_available?:
          bulk_decision_items != [] and source_context_available?(source_context),
        bulk_decision_count_text: Integer.to_string(length(bulk_decision_items)),
        bulk_decision_placement_ids_attr: bulk_decision_placement_ids_attr(bulk_decision_items),
        placement_links: placement_links(summary.placement_ids, selected_placement_id),
        findings: Enum.map(summary.findings, &finding_row(&1, selected_placement_id)),
        selected_placement_id: selected_placement_id
      }
    else
      empty()
    end
  end

  def resolution(event) do
    if resolution_event?(event) do
      summary = ComparisonReviewFocus.resolution_summary(event)
      workflow_summary = resolution_workflow_summary(event)

      %{
        render?: true,
        event_id: event_id(event),
        result_event_id: event_id(event),
        target_event_id: event_id(event),
        source_request_event_id: summary.source_request_event_id,
        disposition: summary.disposition,
        resolution_reason: summary.resolution_reason,
        selected_placement_id: summary.selected_placement_id,
        affected_placements_attr: summary.affected_placements_attr,
        affected_placements_text: summary.affected_placements_text,
        workflow_intent_kind: workflow_summary.workflow_intent_kind,
        workflow_intent_action: workflow_summary.workflow_intent_action,
        workflow_selection_count_text: workflow_summary.workflow_selection_count_text,
        source_open_count_text: workflow_summary.source_open_count_text,
        source_open_placements_attr: workflow_summary.source_open_placements_attr
      }
    else
      empty()
    end
  end

  defp placement_links(placement_ids, selected_placement_id) do
    Enum.map(placement_ids, fn placement_id ->
      %{
        placement_id: placement_id,
        href: "#widget-#{placement_id}",
        selected?: placement_id == selected_placement_id,
        selected_text: selected_text(placement_id == selected_placement_id)
      }
    end)
  end

  defp finding_row(finding, selected_placement_id) when is_map(finding) do
    summary = ComparisonReviewFocus.finding_summary(finding)

    %{
      placement_id: summary.placement_id,
      title: summary.title,
      state: summary.state,
      decision_status: summary.decision_status,
      observation_identity_id: observation_identity_id(finding),
      placement_href: summary.placement_href,
      placement_selected?: summary.placement_id == selected_placement_id,
      placement_selected_text: selected_text(summary.placement_id == selected_placement_id)
    }
  end

  defp bulk_decision_items(findings) when is_list(findings) do
    findings
    |> Enum.map(&bulk_decision_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp bulk_decision_item(finding) when is_map(finding) do
    observation_identity_id = observation_identity_id(finding)

    cond do
      not present_text?(observation_identity_id) ->
        nil

      ComparisonReviewFocus.payload_value(finding, "decision_status") == "applied" ->
        nil

      true ->
        %{
          placement_id: ComparisonReviewFocus.payload_value(finding, "placement_id"),
          observation_identity_id: observation_identity_id
        }
    end
  end

  defp bulk_decision_item(_finding), do: nil

  defp bulk_decision_placement_ids_attr(items) do
    items
    |> Enum.map(&Map.get(&1, :placement_id))
    |> Enum.filter(&present_text?/1)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp observation_identity_id(finding) when is_map(finding) do
    ComparisonReviewFocus.payload_value(finding, "observation_identity_id") ||
      ComparisonReviewFocus.payload_value(finding, "primary_observation_identity_id") ||
      ComparisonReviewFocus.payload_value(finding, "compare_observation_identity_id")
  end

  defp source_context(findings) when is_list(findings) do
    Enum.find_value(findings, &finding_source_context/1) || %{}
  end

  defp finding_source_context(finding) when is_map(finding) do
    [
      ComparisonReviewFocus.payload_value(finding, "primary_data_link"),
      ComparisonReviewFocus.payload_value(finding, "compare_data_link")
    ]
    |> Enum.find_value(&link_source_context/1)
  end

  defp finding_source_context(_finding), do: nil

  defp link_source_context(link) when is_map(link) do
    link
    |> ComparisonReviewFocus.payload_value("context")
    |> ComparisonReviewFocus.payload_value("data")
    |> case do
      data when is_map(data) -> data
      _data -> nil
    end
  end

  defp link_source_context(_link), do: nil

  defp source_context_available?(source_context) when is_map(source_context) do
    Enum.all?(
      ["realm", "data_source_id", "source_binding_id"],
      &(source_context |> ComparisonReviewFocus.payload_value(&1) |> present_text?())
    )
  end

  defp source_context_available?(_source_context), do: false

  defp workflow_request_point_ids(findings) when is_list(findings) do
    findings
    |> Enum.flat_map(&workflow_finding_point_ids/1)
    |> Enum.uniq()
  end

  defp workflow_finding_point_ids(finding) when is_map(finding) do
    [
      ComparisonReviewFocus.payload_value(finding, "point_id"),
      ComparisonReviewFocus.payload_value(finding, "observable_id"),
      ComparisonReviewFocus.payload_value(finding, "primary_observable_ids"),
      ComparisonReviewFocus.payload_value(finding, "compare_observable_ids")
    ]
    |> Enum.flat_map(&point_id_values/1)
    |> Enum.uniq()
  end

  defp workflow_finding_point_ids(_finding), do: []

  defp point_id_values(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp point_id_values(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp point_id_values(_value), do: []

  defp resolution_workflow_summary(event) do
    payload = ComparisonReviewFocus.event_value(event, :payload)
    workflow_intent = ComparisonReviewFocus.payload_value(payload, "workflow_intent")

    source_open_placement_ids =
      payload
      |> ComparisonReviewFocus.payload_value("source_open_placement_ids")
      |> List.wrap()
      |> Enum.filter(&present_text?/1)

    %{
      workflow_intent_kind: workflow_value(workflow_intent, "kind"),
      workflow_intent_action: workflow_value(workflow_intent, "action"),
      workflow_selection_count_text:
        workflow_intent |> ComparisonReviewFocus.payload_value("selection_count") |> count_text(),
      source_open_count_text:
        payload |> ComparisonReviewFocus.payload_value("source_open_count") |> count_text(),
      source_open_placements_attr: Enum.join(source_open_placement_ids, ",")
    }
  end

  defp workflow_value(workflow_intent, key) do
    workflow_intent
    |> ComparisonReviewFocus.payload_value(key)
    |> display_text()
  end

  defp count_text(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)
  defp count_text(value) when is_binary(value) and value != "", do: value
  defp count_text(_value), do: "-"

  defp display_text(value) when is_binary(value) and value != "", do: value
  defp display_text(value) when is_integer(value), do: Integer.to_string(value)
  defp display_text(_value), do: "-"

  defp present_text?(value), do: is_binary(value) and value != ""

  defp selected_text(true), do: "true"
  defp selected_text(false), do: "false"

  defp request_event?(%LifecycleEvent{event_type: :comparison_review_requested}), do: true
  defp request_event?(%{event_type: :comparison_review_requested}), do: true
  defp request_event?(%{"event_type" => :comparison_review_requested}), do: true
  defp request_event?(_event), do: false

  defp resolution_event?(%LifecycleEvent{event_type: :comparison_review_resolved}), do: true
  defp resolution_event?(%{event_type: :comparison_review_resolved}), do: true
  defp resolution_event?(%{"event_type" => :comparison_review_resolved}), do: true
  defp resolution_event?(_event), do: false

  defp event_id(%LifecycleEvent{dashboard_lifecycle_event_id: event_id}), do: event_id
  defp event_id(%{dashboard_lifecycle_event_id: event_id}), do: event_id
  defp event_id(%{"dashboard_lifecycle_event_id" => event_id}), do: event_id

  defp empty, do: %{render?: false}
end
