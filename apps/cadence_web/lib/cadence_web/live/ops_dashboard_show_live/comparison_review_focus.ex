defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewFocus do
  @moduledoc false

  alias Cadence.Dashboards.ComparisonReviewQueue

  @spec open_summary([map()]) :: ComparisonReviewQueue.open_summary()
  defdelegate open_summary(events), to: ComparisonReviewQueue
  defdelegate open_request_count_text(events), to: ComparisonReviewQueue
  defdelegate open_request_ids_attr(events), to: ComparisonReviewQueue
  defdelegate open_request_ids(events), to: ComparisonReviewQueue
  defdelegate open_placements_attr(events), to: ComparisonReviewQueue
  defdelegate open_placement_ids(events), to: ComparisonReviewQueue
  defdelegate open_requests(events), to: ComparisonReviewQueue
  defdelegate request_resolved?(event, events), to: ComparisonReviewQueue
  defdelegate request_resolution_event_id(event, events), to: ComparisonReviewQueue
  defdelegate request_summary(event, events \\ []), to: ComparisonReviewQueue
  defdelegate request_placements(event), to: ComparisonReviewQueue
  defdelegate request_findings(event), to: ComparisonReviewQueue
  defdelegate request_value(event, key), to: ComparisonReviewQueue
  defdelegate finding_value(finding, key), to: ComparisonReviewQueue
  defdelegate resolution_summary(event), to: ComparisonReviewQueue
  defdelegate resolution_value(event, key), to: ComparisonReviewQueue
  defdelegate event_value(event, key), to: ComparisonReviewQueue
  defdelegate payload_value(payload, key), to: ComparisonReviewQueue

  def finding_summary(finding) when is_map(finding) do
    summary = ComparisonReviewQueue.finding_summary(finding)

    Map.put(summary, :placement_href, placement_href(summary.placement_id))
  end

  defp placement_href(""), do: nil
  defp placement_href(placement_id) when is_binary(placement_id), do: "#widget-#{placement_id}"
  defp placement_href(_placement_id), do: nil
end
