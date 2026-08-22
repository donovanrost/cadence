defmodule Cadence.Dashboards do
  @moduledoc """
  Compatibility facade for the dashboard public API.

  New callers should use the focused `DocumentCodec`, `Documents`,
  `Contracts`, `Diagnostics`, `Personalization`, and `Lifecycle` services.
  """

  alias Cadence.Dashboards.{
    Contracts,
    Diagnostics,
    DocumentCodec,
    Documents,
    Lifecycle,
    Personalization
  }

  defdelegate decode_document!(json), to: DocumentCodec, as: :decode!
  defdelegate decode_document(json), to: DocumentCodec, as: :decode
  defdelegate export_document(document), to: DocumentCodec, as: :encode
  def export_bundle(document, opts \\ []), do: DocumentCodec.encode_bundle(document, opts)
  defdelegate validate_export_bundle(json), to: DocumentCodec, as: :decode_import
  defdelegate load_document!(path), to: DocumentCodec, as: :load!
  defdelegate migrate_document_map(attrs), to: DocumentCodec, as: :migrate_map

  def clone_document(organization_id, mission_id, dashboard_id, opts \\ []),
    do: Documents.clone(organization_id, mission_id, dashboard_id, opts)

  def import_document(organization_id, mission_id, json, opts \\ []),
    do: Documents.import(organization_id, mission_id, json, opts)

  defdelegate validate_document(document), to: Contracts

  def validate_publish_readiness(organization_id, mission_id, document, opts \\ []),
    do: Contracts.validate_publish_readiness(organization_id, mission_id, document, opts)

  defdelegate validate_dashboard_request(request), to: Contracts, as: :validate_request
  defdelegate validate_dashboard_plan_result(result), to: Contracts, as: :validate_plan_result

  defdelegate validate_dashboard_resolve_result(result),
    to: Contracts,
    as: :validate_resolve_result

  defdelegate validate_dashboard_source_capabilities(capabilities),
    to: Contracts,
    as: :validate_source_capabilities

  defdelegate validate_dashboard_source_facts(facts),
    to: Contracts,
    as: :validate_source_facts

  defdelegate validate_dashboard_source_result(result),
    to: Contracts,
    as: :validate_source_result

  defdelegate validate_dashboard_planned_source_request(request),
    to: Contracts,
    as: :validate_planned_source_request

  defdelegate summarize_dashboard_source_execution(result),
    to: Diagnostics,
    as: :summarize_source_execution

  def dashboard_source_capability_posture_events(result, opts \\ []),
    do: Diagnostics.source_capability_posture_events(result, opts)

  def record_dashboard_source_capability_postures(result, opts \\ []),
    do: Diagnostics.record_source_capability_postures(result, opts)

  def list_dashboard_source_capability_posture_events(organization_id, mission_id, opts \\ []),
    do: Diagnostics.list_source_capability_posture_events(organization_id, mission_id, opts)

  defdelegate dashboard_lifecycle_status(summary), to: Lifecycle, as: :status
  defdelegate dashboard_version_action(summary, version), to: Lifecycle, as: :version_action

  def dashboard_runtime_invalidation_decisions(snapshot_or_recent_events, opts \\ []),
    do: Diagnostics.runtime_invalidation_decisions(snapshot_or_recent_events, opts)

  def record_dashboard_runtime_invalidation_decision(event, decision, opts \\ []),
    do: Diagnostics.record_runtime_invalidation_decision(event, decision, opts)

  def durable_dashboard_runtime_invalidation_decisions(opts \\ []),
    do: Diagnostics.durable_runtime_invalidation_decisions(opts)

  defdelegate persist_document(organization_id, document), to: Documents, as: :persist

  def update_document(organization_id, mission_id, dashboard_id, document, opts \\ []),
    do: Documents.update(organization_id, mission_id, dashboard_id, document, opts)

  defdelegate fetch_document(organization_id, mission_id, dashboard_id),
    to: Documents,
    as: :fetch

  defdelegate fetch_published_document(organization_id, mission_id, dashboard_id),
    to: Documents,
    as: :fetch_published

  defdelegate fetch_document_for_mode(organization_id, mission_id, dashboard_id, mode),
    to: Documents,
    as: :fetch_for_mode

  defdelegate list_documents(organization_id, mission_id), to: Documents, as: :list

  defdelegate list_dashboard_summaries(organization_id, mission_id),
    to: Documents,
    as: :list_summaries

  defdelegate list_archived_dashboard_summaries(organization_id, mission_id),
    to: Documents,
    as: :list_archived_summaries

  defdelegate list_dashboard_user_preferences(organization_id, mission_id, user_id),
    to: Personalization,
    as: :list_preferences

  defdelegate dashboard_navigation(organization_id, mission_id, user_id, summaries),
    to: Personalization,
    as: :navigation

  def set_dashboard_starred(
        organization_id,
        mission_id,
        user_id,
        dashboard_id,
        starred,
        opts \\ []
      ),
      do:
        Personalization.set_starred(
          organization_id,
          mission_id,
          user_id,
          dashboard_id,
          starred,
          opts
        )

  def record_dashboard_view(organization_id, mission_id, user_id, dashboard_id, opts \\ []),
    do: Personalization.record_view(organization_id, mission_id, user_id, dashboard_id, opts)

  def archive_document(organization_id, mission_id, dashboard_id, opts \\ []),
    do: Documents.archive(organization_id, mission_id, dashboard_id, opts)

  def restore_document(organization_id, mission_id, dashboard_id, opts \\ []),
    do: Documents.restore(organization_id, mission_id, dashboard_id, opts)

  def delete_document(organization_id, mission_id, dashboard_id, opts \\ []),
    do: Documents.delete(organization_id, mission_id, dashboard_id, opts)

  def save_dashboard_investigation_preset(
        organization_id,
        mission_id,
        dashboard_id,
        attrs,
        opts \\ []
      ),
      do: Personalization.save_preset(organization_id, mission_id, dashboard_id, attrs, opts)

  def list_dashboard_investigation_presets(organization_id, mission_id, dashboard_id, opts \\ []),
    do: Personalization.list_presets(organization_id, mission_id, dashboard_id, opts)

  defdelegate fetch_dashboard_investigation_preset(
                organization_id,
                mission_id,
                dashboard_id,
                preset_id
              ),
              to: Personalization,
              as: :fetch_preset

  defdelegate delete_dashboard_investigation_preset(
                organization_id,
                mission_id,
                dashboard_id,
                preset_id
              ),
              to: Personalization,
              as: :delete_preset

  defdelegate list_versions(organization_id, mission_id, dashboard_id), to: Documents
  defdelegate fetch_version(organization_id, mission_id, dashboard_id, version), to: Documents

  def publish_document(organization_id, mission_id, dashboard_id, version, opts \\ []),
    do: Documents.publish(organization_id, mission_id, dashboard_id, version, opts)

  def revert_document(organization_id, mission_id, dashboard_id, version, opts \\ []),
    do: Documents.revert(organization_id, mission_id, dashboard_id, version, opts)

  defdelegate list_lifecycle_events(organization_id, mission_id, dashboard_id),
    to: Lifecycle,
    as: :list_events

  defdelegate fetch_lifecycle_event(organization_id, mission_id, lifecycle_event_id),
    to: Lifecycle,
    as: :fetch_event

  defdelegate list_open_comparison_review_requests(organization_id, mission_id, dashboard_id),
    to: Lifecycle,
    as: :list_open_comparison_reviews

  defdelegate dashboard_comparison_review_queue(organization_id, mission_id, dashboard_id),
    to: Lifecycle,
    as: :comparison_review_queue

  def record_dashboard_comparison_review_request(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      ),
      do:
        Lifecycle.record_comparison_review_request(
          organization_id,
          mission_id,
          dashboard_id,
          payload,
          opts
        )

  def record_dashboard_comparison_review_resolution(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      ),
      do:
        Lifecycle.record_comparison_review_resolution(
          organization_id,
          mission_id,
          dashboard_id,
          payload,
          opts
        )

  def record_dashboard_health_snapshot(
        organization_id,
        mission_id,
        dashboard_id,
        snapshot,
        opts \\ []
      ),
      do:
        Lifecycle.record_health_snapshot(
          organization_id,
          mission_id,
          dashboard_id,
          snapshot,
          opts
        )

  def record_dashboard_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        document,
        validation,
        summary,
        opts
      ),
      do:
        Lifecycle.record_publish_readiness_check(
          organization_id,
          mission_id,
          dashboard_id,
          document,
          validation,
          summary,
          opts
        )

  def record_dashboard_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      ),
      do:
        Lifecycle.record_publish_readiness_check(
          organization_id,
          mission_id,
          dashboard_id,
          payload,
          opts
        )
end
