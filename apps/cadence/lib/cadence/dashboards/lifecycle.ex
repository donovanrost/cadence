defmodule Cadence.Dashboards.Lifecycle do
  @moduledoc "Dashboard lifecycle status, audit events, and review workflow."

  alias Cadence.Dashboards.{
    DashboardLifecycleStatus,
    Document,
    DocumentStore,
    PublishReadinessPayload,
    ValidationResult
  }

  def status(summary), do: DashboardLifecycleStatus.from_summary(summary)

  def version_action(summary, version),
    do: DashboardLifecycleStatus.version_action(summary, version)

  defdelegate list_events(organization_id, mission_id, dashboard_id),
    to: DocumentStore,
    as: :list_lifecycle_events

  defdelegate fetch_event(organization_id, mission_id, lifecycle_event_id),
    to: DocumentStore,
    as: :fetch_lifecycle_event

  defdelegate list_open_comparison_reviews(organization_id, mission_id, dashboard_id),
    to: DocumentStore,
    as: :list_open_comparison_review_requests

  defdelegate comparison_review_queue(organization_id, mission_id, dashboard_id),
    to: DocumentStore

  defdelegate record_comparison_review_request(
                organization_id,
                mission_id,
                dashboard_id,
                payload,
                opts
              ),
              to: DocumentStore

  defdelegate record_comparison_review_resolution(
                organization_id,
                mission_id,
                dashboard_id,
                payload,
                opts
              ),
              to: DocumentStore

  defdelegate record_health_snapshot(organization_id, mission_id, dashboard_id, snapshot, opts),
    to: DocumentStore

  def record_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        %Document{} = document,
        %ValidationResult{} = validation,
        summary,
        opts
      ) do
    if document.dashboard_id == dashboard_id do
      payload =
        PublishReadinessPayload.publish_readiness_payload_for(document, validation, summary)

      record_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts
      )
    else
      {:error, :dashboard_document_mismatch}
    end
  end

  defdelegate record_publish_readiness_check(
                organization_id,
                mission_id,
                dashboard_id,
                payload,
                opts
              ),
              to: DocumentStore
end
