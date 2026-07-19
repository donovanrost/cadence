defmodule CadenceWeb.Assets.DashboardRenderedViewportWorkflowFixtures do
  @moduledoc false

  import ExUnit.Assertions
  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Repo

  def seed_failed_replacement_retry_workflow!(org, mission, dashboard, opts) do
    group_id = Keyword.fetch!(opts, :group_id)
    source_run_id = Keyword.fetch!(opts, :source_run_id)
    corrected_run_id = Keyword.fetch!(opts, :corrected_run_id)
    replay_run_id = Keyword.fetch!(opts, :replay_run_id)
    point_id = Keyword.get(opts, :point_id, "HK.current")

    dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => replay_run_id,
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    source_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        source_run_id,
        point_id,
        group_id,
        1,
        1,
        dashboard_context: dashboard_context
      )

    _source_requested = record_backfill_workflow_event!(org, mission, "requested", source_attrs)
    _source_approved = record_backfill_workflow_event!(org, mission, "approved", source_attrs)
    _source_started = record_backfill_workflow_event!(org, mission, "started", source_attrs)

    source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        source_run_id,
        Keyword.get(opts, :source_failure_reason, :replacement_retry_source_failed)
      )

    source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: source_run_id,
          point_id: point_id,
          request_group_id: group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => dashboard_context,
            "job_id" => source_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => false,
                "retry_blockers" => ["operator_correction_required"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    correction_payload = %{
      "dashboard_context" => dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => source_run_id,
      "corrects_event_id" => source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => source_job.job_id
    }

    corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        corrected_run_id,
        point_id,
        group_id,
        1,
        1,
        dashboard_context: dashboard_context
      )
      |> Map.put(:payload, correction_payload)

    _corrected_requested =
      record_backfill_workflow_event!(org, mission, "requested", corrected_attrs)

    _corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", corrected_attrs)

    _corrected_started = record_backfill_workflow_event!(org, mission, "started", corrected_attrs)

    corrected_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        corrected_run_id,
        Keyword.get(opts, :corrected_failure_reason, :replacement_retry_corrected_failed)
      )

    corrected_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: corrected_run_id,
          point_id: point_id,
          request_group_id: group_id,
          item_index: 1,
          item_count: 1,
          payload:
            Map.merge(correction_payload, %{
              "job_id" => corrected_job.job_id,
              "job_type" => "telemetry_historical_data_workflow",
              "workflow_job_status" => "failed",
              "source" => %{
                "failure" => %{
                  "code" => "replacement_worker_failed",
                  "retryable" => true,
                  "retry_blockers" => [],
                  "recovery_action" => "retry_job"
                }
              }
            })
        }
      )

    %{
      group_id: group_id,
      source_failed_event: source_failed_event,
      corrected_run_id: corrected_run_id,
      corrected_job: corrected_job,
      corrected_failed_event: corrected_failed_event
    }
  end

  def record_backfill_workflow_event!(org, mission, stage, attrs) do
    run_id = Map.fetch!(attrs, :run_id)
    point_id = Map.get(attrs, :point_id)
    request_group_id = Map.fetch!(attrs, :request_group_id)
    item_index = Map.fetch!(attrs, :item_index)
    item_count = Map.fetch!(attrs, :item_count)
    payload_overrides = Map.get(attrs, :payload, %{})

    event_attrs =
      %{
        backfill_run_id: run_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :backfill,
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        source_from: ~U[2023-11-14 22:12:00Z],
        source_to: ~U[2023-11-14 22:15:00Z],
        authority: :advisory,
        reason: "browser_smoke_closure_fixture_#{stage}",
        actor_id: "system",
        actor_kind: "system",
        payload:
          Map.merge(
            %{
              "request_source" => "dashboard_direct_request",
              "request_mode" => "bulk_points",
              "request_group_id" => request_group_id,
              "request_item_index" => item_index,
              "request_item_count" => item_count,
              "request_item_run_id" => run_id
            },
            payload_overrides
          )
      }
      |> Map.merge(maybe_event_point_attrs(point_id))

    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               stage,
               event_attrs,
               dashboard_runtime_invalidation?: false
             )

    event
  end

  def historical_workflow_item_attrs(
        org,
        mission,
        run_id,
        point_id,
        request_group_id,
        item_index,
        item_count,
        opts
      ) do
    dashboard_context = Keyword.fetch!(opts, :dashboard_context)
    comparison_review_origin = Keyword.get(opts, :comparison_review_origin)

    %{
      backfill_run_id: run_id,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2023-11-14 22:12:00Z],
      source_to: ~U[2023-11-14 22:15:00Z],
      authority: :advisory,
      reason: "browser_smoke_real_group_job",
      actor_id: "system",
      actor_kind: "system",
      run_id: run_id,
      point_id: point_id,
      request_group_id: request_group_id,
      item_index: item_index,
      item_count: item_count,
      payload:
        %{
          "request_source" => "dashboard_direct_request",
          "request_mode" => "bulk_points",
          "request_group_id" => request_group_id,
          "request_item_index" => item_index,
          "request_item_count" => item_count,
          "request_item_run_id" => run_id,
          "dashboard_context" => dashboard_context
        }
        |> maybe_put("comparison_review_origin", comparison_review_origin)
    }
    |> maybe_domain_point_attrs(point_id)
  end

  def maybe_event_point_attrs(point_id) when is_binary(point_id) and point_id != "" do
    %{observable_id: point_id, point_id: point_id}
  end

  def maybe_event_point_attrs(_point_id), do: %{}

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def maybe_domain_point_attrs(attrs, point_id) when is_binary(point_id) and point_id != "" do
    attrs
    |> Map.put(:observable_id, point_id)
    |> Map.put(:point_id, point_id)
  end

  def maybe_domain_point_attrs(attrs, _point_id), do: attrs

  def enqueue_failed_historical_workflow_job!(mission, run_id, reason) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == job.job_id))
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, reason)
    assert failed_job.status == :failed
    failed_job
  end

  def enqueue_completed_historical_workflow_job!(mission, run_id) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    background_job_row = Repo.get!(BackgroundJobRow, job.job_id)
    completed_job = %{job | status: :completed, completed_at: DateTime.utc_now()}

    assert {:ok, updated_row} =
             background_job_row
             |> BackgroundJobRow.changeset(completed_job)
             |> Repo.update()

    BackgroundJobRow.to_domain(updated_row)
  end

  def enqueue_stale_running_historical_workflow_job!(mission, run_id) do
    assert {:ok, job} = enqueue_historical_workflow_job(mission, run_id)
    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == job.job_id))
    assert {:ok, running_job} = Cadence.Jobs.fetch_job(job.job_id)

    stale_job = %{
      running_job
      | started_at: DateTime.add(DateTime.utc_now(), -1_200, :second)
    }

    assert {:ok, updated_row} =
             job.job_id
             |> then(&Repo.get!(BackgroundJobRow, &1))
             |> BackgroundJobRow.changeset(stale_job)
             |> Repo.update()

    BackgroundJobRow.to_domain(updated_row)
  end

  def enqueue_historical_workflow_job(mission, run_id) do
    Cadence.Jobs.enqueue(
      :telemetry_historical_data_workflow,
      mission.mission_id,
      run_id,
      %{
        "workflow" => "backfill",
        "attrs" => %{"backfill_run_id" => run_id}
      }
    )
  end
end
