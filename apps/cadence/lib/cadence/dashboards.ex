defmodule Cadence.Dashboards do
  @moduledoc """
  Contract layer for the next-generation dashboard engine.

  This module intentionally starts as a small facade over document decoding and
  validation. Engine execution and persistence land in later slices.
  """

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DashboardContract,
    DashboardLifecycleStatus,
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    DocumentMigration,
    DocumentStore,
    InvestigationPreset,
    InvestigationPresets,
    LifecycleEvent,
    ManagedQuestDBProvisioningJobs,
    ManagedQuestDBProvisioningRuns,
    PlannedSourceRequest,
    PublishReadiness,
    PublishReadinessPayload,
    RuntimeInvalidation.DecisionEvent,
    RuntimeInvalidation.DecisionEvents,
    RuntimeInvalidation.DecisionProjection,
    RuntimeInvalidation.Event,
    SourceCapabilities,
    SourceExecutionSemantics,
    SourceFacts,
    SourceHealth,
    SourceHealthEvent,
    SourceHealthStatus,
    SourceResult,
    ValidationResult,
    Version
  }

  @spec decode_document!(binary()) :: Document.t()
  def decode_document!(json) when is_binary(json) do
    case json
         |> Jason.decode!()
         |> DocumentMigration.migrate_map() do
      {:ok, %DocumentMigration.Result{document: document}} ->
        document

      {:error, reason} ->
        raise ArgumentError, "invalid dashboard document: #{inspect(reason)}"
    end
  end

  @spec load_document!(Path.t()) :: Document.t()
  def load_document!(path) when is_binary(path) do
    path
    |> File.read!()
    |> decode_document!()
  end

  @spec validate_document(Document.t()) :: Cadence.Dashboards.ValidationResult.t()
  def validate_document(%Document{} = document), do: Document.validate(document)

  @spec validate_publish_readiness(binary(), binary(), Document.t(), keyword()) ::
          Cadence.Dashboards.ValidationResult.t()
  def validate_publish_readiness(organization_id, mission_id, %Document{} = document, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    PublishReadiness.validate(organization_id, mission_id, document, opts)
  end

  @spec validate_dashboard_request(DashboardResolveRequest.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_request(%DashboardResolveRequest{} = request) do
    DashboardContract.validate_request(request)
  end

  @spec validate_dashboard_plan_result(DashboardResolveResult.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_plan_result(%DashboardResolveResult{} = result) do
    DashboardContract.validate_plan_result(result)
  end

  @spec validate_dashboard_resolve_result(DashboardResolveResult.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_resolve_result(%DashboardResolveResult{} = result) do
    DashboardContract.validate_resolve_result(result)
  end

  @spec validate_dashboard_source_capabilities(SourceCapabilities.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_source_capabilities(%SourceCapabilities{} = capabilities) do
    DashboardContract.validate_source_capabilities(capabilities)
  end

  @spec validate_dashboard_source_facts(SourceFacts.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_source_facts(%SourceFacts{} = facts) do
    DashboardContract.validate_source_facts(facts)
  end

  @spec validate_dashboard_source_result(SourceResult.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_source_result(%SourceResult{} = result) do
    DashboardContract.validate_source_result(result)
  end

  @spec validate_dashboard_planned_source_request(PlannedSourceRequest.t()) ::
          :ok | {:error, [DashboardContract.violation()]}
  def validate_dashboard_planned_source_request(%PlannedSourceRequest{} = request) do
    DashboardContract.validate_planned_source_request(request)
  end

  @spec summarize_dashboard_source_execution(DashboardResolveResult.t()) ::
          SourceExecutionSemantics.summary()
  def summarize_dashboard_source_execution(%DashboardResolveResult{} = result) do
    SourceExecutionSemantics.summarize(result)
  end

  @spec dashboard_source_capability_posture_events(DashboardResolveResult.t(), keyword() | map()) ::
          [
            Cadence.OperationalEvents.Event.t()
          ]
  def dashboard_source_capability_posture_events(%DashboardResolveResult{} = result, opts \\ []) do
    SourceExecutionSemantics.source_capability_posture_events(result, opts)
  end

  @spec record_dashboard_source_capability_postures(DashboardResolveResult.t(), keyword() | map()) ::
          {:ok, [Cadence.OperationalEvents.Event.t()]} | {:error, term()}
  def record_dashboard_source_capability_postures(%DashboardResolveResult{} = result, opts \\ []) do
    result
    |> dashboard_source_capability_posture_events(opts)
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, events} ->
      case Cadence.OperationalEvents.persist_event(event) do
        {:ok, persisted_event} -> {:cont, {:ok, [persisted_event | events]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_dashboard_source_capability_posture_events(binary(), binary(), keyword()) :: [
          Cadence.OperationalEvents.Event.t()
        ]
  def list_dashboard_source_capability_posture_events(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Cadence.OperationalEvents.list_events(
      organization_id,
      mission_id,
      Keyword.merge(opts,
        category: :data_source,
        source_record_kind: :source_capability_posture
      )
    )
  end

  @spec dashboard_lifecycle_status(Cadence.Dashboards.DashboardSummary.t() | nil) ::
          DashboardLifecycleStatus.t()
  def dashboard_lifecycle_status(summary), do: DashboardLifecycleStatus.from_summary(summary)

  @spec dashboard_runtime_invalidation_decisions(map() | [map()], keyword()) :: [
          DecisionProjection.decision_row()
        ]
  def dashboard_runtime_invalidation_decisions(snapshot_or_recent_events, opts \\ [])
      when is_list(opts) do
    DecisionProjection.list(snapshot_or_recent_events, opts)
  end

  @spec record_dashboard_runtime_invalidation_decision(Event.t(), map(), keyword()) ::
          {:ok, DecisionEvent.t()} | {:error, term()}
  def record_dashboard_runtime_invalidation_decision(%Event{} = event, decision, opts \\ [])
      when is_map(decision) and is_list(opts) do
    DecisionEvents.record(event, decision, opts)
  end

  @spec durable_dashboard_runtime_invalidation_decisions(keyword()) :: [
          DecisionProjection.decision_row()
        ]
  def durable_dashboard_runtime_invalidation_decisions(opts \\ []) when is_list(opts) do
    DecisionEvents.list_decision_rows(opts)
  end

  @spec dashboard_version_action(
          Cadence.Dashboards.DashboardSummary.t() | nil,
          Version.t() | pos_integer()
        ) :: DashboardLifecycleStatus.version_action()
  def dashboard_version_action(summary, version),
    do: DashboardLifecycleStatus.version_action(summary, version)

  @spec migrate_document_map(map()) :: DocumentMigration.result()
  def migrate_document_map(attrs) when is_map(attrs), do: DocumentMigration.migrate_map(attrs)

  @spec persist_document(binary(), Document.t()) :: {:ok, Document.t()} | {:error, term()}
  def persist_document(organization_id, %Document{} = document) when is_binary(organization_id) do
    DocumentStore.persist_document(organization_id, document)
  end

  @spec update_document(binary(), binary(), binary(), Document.t(), keyword()) ::
          {:ok, Document.t()} | {:error, term()}
  def update_document(
        organization_id,
        mission_id,
        dashboard_id,
        %Document{} = document,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.update_document(organization_id, mission_id, dashboard_id, document, opts)
  end

  @spec fetch_document(binary(), binary(), binary()) ::
          {:ok, Document.t()} | {:error, :dashboard_not_found}
  def fetch_document(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.fetch_document(organization_id, mission_id, dashboard_id)
  end

  @spec fetch_published_document(binary(), binary(), binary()) ::
          {:ok, Document.t()}
          | {:error,
             :dashboard_not_found
             | :dashboard_archived
             | :dashboard_not_published
             | :dashboard_version_not_found}
  def fetch_published_document(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.fetch_published_document(organization_id, mission_id, dashboard_id)
  end

  @spec fetch_document_for_mode(
          binary(),
          binary(),
          binary(),
          :view | :published | :edit | :draft | :latest
        ) ::
          {:ok, Document.t()}
          | {:error,
             :dashboard_not_found
             | :dashboard_archived
             | :dashboard_not_published
             | :dashboard_version_not_found}
  def fetch_document_for_mode(organization_id, mission_id, dashboard_id, mode)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.fetch_document_for_mode(organization_id, mission_id, dashboard_id, mode)
  end

  @spec list_documents(binary(), binary()) :: [Document.t()]
  def list_documents(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    DocumentStore.list_documents(organization_id, mission_id)
  end

  @spec list_dashboard_summaries(binary(), binary()) :: [
          Cadence.Dashboards.DashboardSummary.t()
        ]
  def list_dashboard_summaries(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    DocumentStore.list_dashboard_summaries(organization_id, mission_id)
  end

  @spec list_archived_dashboard_summaries(binary(), binary()) :: [
          Cadence.Dashboards.DashboardSummary.t()
        ]
  def list_archived_dashboard_summaries(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    DocumentStore.list_archived_dashboard_summaries(organization_id, mission_id)
  end

  @spec archive_document(binary(), binary(), binary(), keyword()) :: :ok | {:error, term()}
  def archive_document(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.archive_document(organization_id, mission_id, dashboard_id, opts)
  end

  @spec restore_document(binary(), binary(), binary(), keyword()) :: :ok | {:error, term()}
  def restore_document(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.restore_document(organization_id, mission_id, dashboard_id, opts)
  end

  @spec delete_document(binary(), binary(), binary(), keyword()) :: :ok | {:error, term()}
  def delete_document(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.delete_document(organization_id, mission_id, dashboard_id, opts)
  end

  @spec save_dashboard_investigation_preset(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, InvestigationPreset.t()} | {:error, term()}
  def save_dashboard_investigation_preset(
        organization_id,
        mission_id,
        dashboard_id,
        attrs,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(attrs) and is_list(opts) do
    InvestigationPresets.save(organization_id, mission_id, dashboard_id, attrs, opts)
  end

  @spec list_dashboard_investigation_presets(binary(), binary(), binary(), keyword()) :: [
          InvestigationPreset.t()
        ]
  def list_dashboard_investigation_presets(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_list(opts) do
    InvestigationPresets.list(organization_id, mission_id, dashboard_id, opts)
  end

  @spec fetch_dashboard_investigation_preset(binary(), binary(), binary(), binary()) ::
          {:ok, InvestigationPreset.t()} | {:error, :investigation_preset_not_found}
  def fetch_dashboard_investigation_preset(organization_id, mission_id, dashboard_id, preset_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_binary(preset_id) do
    InvestigationPresets.fetch(organization_id, mission_id, dashboard_id, preset_id)
  end

  @spec delete_dashboard_investigation_preset(binary(), binary(), binary(), binary()) ::
          :ok | {:error, :investigation_preset_not_found}
  def delete_dashboard_investigation_preset(organization_id, mission_id, dashboard_id, preset_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_binary(preset_id) do
    InvestigationPresets.delete(organization_id, mission_id, dashboard_id, preset_id)
  end

  @spec list_versions(binary(), binary(), binary()) :: [Version.t()]
  def list_versions(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.list_versions(organization_id, mission_id, dashboard_id)
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, Version.t()} | {:error, :dashboard_version_not_found}
  def fetch_version(organization_id, mission_id, dashboard_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_integer(version) and version > 0 do
    DocumentStore.fetch_version(organization_id, mission_id, dashboard_id, version)
  end

  @spec publish_document(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Version.t()} | {:error, term()}
  def publish_document(organization_id, mission_id, dashboard_id, version, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_integer(version) and version > 0 do
    DocumentStore.publish_document(organization_id, mission_id, dashboard_id, version, opts)
  end

  @spec revert_document(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Version.t()} | {:error, term()}
  def revert_document(organization_id, mission_id, dashboard_id, version, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_integer(version) and version > 0 do
    DocumentStore.revert_document(organization_id, mission_id, dashboard_id, version, opts)
  end

  @spec list_lifecycle_events(binary(), binary(), binary()) :: [LifecycleEvent.t()]
  def list_lifecycle_events(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.list_lifecycle_events(organization_id, mission_id, dashboard_id)
  end

  @spec fetch_lifecycle_event(binary(), binary(), binary()) ::
          {:ok, LifecycleEvent.t()} | {:error, :not_found}
  def fetch_lifecycle_event(organization_id, mission_id, dashboard_lifecycle_event_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(dashboard_lifecycle_event_id) do
    DocumentStore.fetch_lifecycle_event(
      organization_id,
      mission_id,
      dashboard_lifecycle_event_id
    )
  end

  @spec list_open_comparison_review_requests(binary(), binary(), binary()) :: [LifecycleEvent.t()]
  def list_open_comparison_review_requests(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.list_open_comparison_review_requests(organization_id, mission_id, dashboard_id)
  end

  @spec dashboard_comparison_review_queue(binary(), binary(), binary()) ::
          ComparisonReviewQueue.open_summary()
  def dashboard_comparison_review_queue(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DocumentStore.comparison_review_queue(organization_id, mission_id, dashboard_id)
  end

  @spec record_dashboard_comparison_review_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_dashboard_comparison_review_request(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    DocumentStore.record_comparison_review_request(
      organization_id,
      mission_id,
      dashboard_id,
      payload,
      opts
    )
  end

  @spec record_dashboard_comparison_review_resolution(
          binary(),
          binary(),
          binary(),
          map(),
          keyword()
        ) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_dashboard_comparison_review_resolution(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    DocumentStore.record_comparison_review_resolution(
      organization_id,
      mission_id,
      dashboard_id,
      payload,
      opts
    )
  end

  @spec record_dashboard_health_snapshot(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_dashboard_health_snapshot(
        organization_id,
        mission_id,
        dashboard_id,
        snapshot,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(snapshot) and is_list(opts) do
    DocumentStore.record_health_snapshot(
      organization_id,
      mission_id,
      dashboard_id,
      snapshot,
      opts
    )
  end

  @spec record_dashboard_publish_readiness_check(
          binary(),
          binary(),
          binary(),
          Document.t(),
          ValidationResult.t(),
          term(),
          keyword()
        ) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_dashboard_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        %Document{} = document,
        %ValidationResult{} = validation,
        summary,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_list(opts) do
    if document.dashboard_id == dashboard_id do
      payload =
        PublishReadinessPayload.publish_readiness_payload_for(document, validation, summary)

      record_dashboard_publish_readiness_check(
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

  @spec record_dashboard_publish_readiness_check(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_dashboard_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    DocumentStore.record_publish_readiness_check(
      organization_id,
      mission_id,
      dashboard_id,
      payload,
      opts
    )
  end

  @spec record_source_health(map(), keyword()) ::
          {:ok, SourceHealthEvent.t(), SourceHealthStatus.t()}
          | {:ok, :unchanged, SourceHealthStatus.t()}
          | {:error, term()}
  def record_source_health(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    SourceHealth.record_source_health(attrs, opts)
  end

  @spec list_source_health_events(binary() | nil, binary() | nil, keyword()) :: [
          SourceHealthEvent.t()
        ]
  def list_source_health_events(organization_id, mission_id, opts \\ []) when is_list(opts) do
    SourceHealth.list_source_health_events(organization_id, mission_id, opts)
  end

  @spec list_source_health_statuses(binary() | nil, binary() | nil, keyword()) :: [
          SourceHealthStatus.t()
        ]
  def list_source_health_statuses(organization_id, mission_id, opts \\ []) when is_list(opts) do
    SourceHealth.list_source_health_statuses(organization_id, mission_id, opts)
  end

  @spec enqueue_managed_questdb_provisioning(map(), keyword()) ::
          {:ok, Cadence.Jobs.Job.t()} | {:error, term()}
  def enqueue_managed_questdb_provisioning(attrs, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    ManagedQuestDBProvisioningJobs.enqueue(attrs, opts)
  end

  @spec execute_enqueued_managed_questdb_provisioning(binary()) :: {:ok, map()} | {:error, term()}
  def execute_enqueued_managed_questdb_provisioning(run_id) when is_binary(run_id) do
    ManagedQuestDBProvisioningJobs.execute_enqueued_run(run_id)
  end

  @spec list_managed_questdb_provisioning_runs(binary(), keyword()) :: [
          ManagedQuestDBProvisioningRuns.t()
        ]
  def list_managed_questdb_provisioning_runs(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    ManagedQuestDBProvisioningRuns.list_for_mission(mission_id, opts)
  end

  @spec retry_managed_questdb_provisioning_run(binary()) ::
          {:ok, ManagedQuestDBProvisioningRuns.t()} | {:error, term()}
  def retry_managed_questdb_provisioning_run(job_id) when is_binary(job_id) do
    ManagedQuestDBProvisioningRuns.retry_failed(job_id)
  end

  @spec requeue_managed_questdb_provisioning_run(binary()) ::
          {:ok, ManagedQuestDBProvisioningRuns.t()} | {:error, term()}
  def requeue_managed_questdb_provisioning_run(job_id) when is_binary(job_id) do
    ManagedQuestDBProvisioningRuns.requeue_running(job_id)
  end
end
