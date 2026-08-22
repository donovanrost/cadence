defmodule CadenceWeb.DashboardReviewFixtures do
  @moduledoc false

  alias Cadence.Dashboards.LifecycleEvent

  def comparison_review_request_event(opts \\ []) do
    event_id = Keyword.get(opts, :event_id, "dashboard-lifecycle-event-1")
    placement_ids = Keyword.get(opts, :placement_ids, ["placement-1", "placement-2"])
    findings = Keyword.get_lazy(opts, :findings, fn -> findings_for_placements(placement_ids) end)

    lifecycle_event(
      event_id,
      :comparison_review_requested,
      Keyword.merge(
        [
          occurred_at: ~U[2026-06-24 12:00:00Z],
          payload: %{
            "schema" => "dashboard_comparison_review_request.v1",
            "request_kind" => "comparison_open_findings_review",
            "open_count" => length(findings),
            "open_placement_ids" => placement_ids,
            "open_findings" => %{
              "schema" => "dashboard_comparison_open_findings.v1",
              "findings" => findings
            }
          }
        ],
        opts
      )
    )
  end

  def comparison_review_resolution_event(opts \\ []) do
    source_request_event_id =
      Keyword.get(opts, :source_request_event_id, "dashboard-lifecycle-event-1")

    event_opts = Keyword.delete(opts, :payload)

    payload =
      %{
        "schema" => "dashboard_comparison_review_resolution.v1",
        "source_request_event_id" => source_request_event_id,
        "disposition" => "review_completed",
        "resolution_reason" => "Reviewed by mission analyst",
        "selected_placement_id" => "placement-1",
        "affected_placement_ids" => ["placement-1"]
      }
      |> Map.merge(Keyword.get(opts, :payload, %{}))
      |> Map.put_new("source_request_event_id", source_request_event_id)

    lifecycle_event(
      Keyword.get(opts, :event_id, "dashboard-lifecycle-event-2"),
      :comparison_review_resolved,
      Keyword.merge(
        [
          occurred_at: ~U[2026-06-24 12:30:00Z],
          payload: payload
        ],
        event_opts
      )
    )
  end

  def lifecycle_event(event_id, event_type, opts \\ []) do
    LifecycleEvent.new(%{
      dashboard_lifecycle_event_id: event_id,
      organization_id: Keyword.get(opts, :organization_id, "org-1"),
      mission_id: Keyword.get(opts, :mission_id, "mission-1"),
      dashboard_id: Keyword.get(opts, :dashboard_id, "dashboard-1"),
      event_type: event_type,
      dashboard_version: Keyword.get(opts, :dashboard_version, 3),
      previous_lifecycle_state: Keyword.get(opts, :previous_lifecycle_state, "active"),
      current_lifecycle_state: Keyword.get(opts, :current_lifecycle_state, "active"),
      actor_id: Keyword.get(opts, :actor_id),
      occurred_at: Keyword.get(opts, :occurred_at, ~U[2026-06-24 12:00:00Z]),
      payload: Keyword.get(opts, :payload, %{})
    })
  end

  def open_findings_payload(opts \\ []) do
    placement_ids = Keyword.get(opts, :placement_ids, ["placement-1"])
    findings = Keyword.get_lazy(opts, :findings, fn -> findings_for_placements(placement_ids) end)

    %{
      "schema" => "dashboard_comparison_open_findings.v1",
      "source_schema" => "dashboard_comparison_investigation_preset.v1",
      "comparison" => %{
        "open_count" => length(findings),
        "open_placement_ids" => placement_ids
      },
      "workflow_intent" => %{
        "schema" => "dashboard_comparison_workflow_intent.v1",
        "kind" => "bulk_correction_authority_review",
        "source" => "dashboard_comparison_rollup",
        "action" => "request_comparison_review",
        "selection_kind" => "open_comparison_findings",
        "selection_count" => length(findings),
        "placement_ids" => placement_ids
      },
      "findings" => findings
    }
  end

  def findings_for_placements(placement_ids) when is_list(placement_ids) do
    placement_ids
    |> Enum.with_index()
    |> Enum.map(fn {placement_id, index} ->
      %{
        "placement_id" => placement_id,
        "title" => default_title(index),
        "state" => default_state(index),
        "decision_status" => "unhandled"
      }
    end)
  end

  defp default_title(0), do: "Bus voltage"
  defp default_title(1), do: "Current"
  defp default_title(index), do: "Finding #{index + 1}"

  defp default_state(0), do: "increased"
  defp default_state(1), do: "missing"
  defp default_state(_index), do: "unhandled"
end
