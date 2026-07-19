defmodule Cadence.Telemetry.DataManagementFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage

  def sample(sample_id, generation_time, receipt_time, opts \\ []) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-product",
      spacecraft_id: "sc-1",
      point_id: Keyword.get(opts, :point_id, "HK.counter"),
      point_name: Keyword.get(opts, :point_id, "HK.counter"),
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: Keyword.get(opts, :raw_value, 42),
      engineering_value: Keyword.get(opts, :engineering_value, Keyword.get(opts, :raw_value, 42)),
      quality_state: :good,
      generation_time: generation_time,
      receipt_time: receipt_time,
      provenance: provenance(opts)
    }
  end

  def envelope_by_sample_id(envelopes, sample_id) do
    Enum.find(envelopes, &(&1.sample_id == sample_id))
  end

  def assert_bulk_decision_event!(
        observation_identity_id,
        correction_envelope,
        item_index,
        placement_id
      ) do
    assert [event] =
             Storage.list_observation_identity_decision_events(
               observation_identity_id,
               organization_id: "org-product",
               mission_id: "mission-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

    assert event.decision == :mark_canonical
    assert event.new_state["validity_state"] == "canonical"
    assert event.new_state["canonical_sample_id"] == correction_envelope.sample_id
    assert event.evidence_ref["kind"] == "dashboard_comparison_review"
    assert event.evidence_ref["id"] == "review-request-1"
    assert event.evidence_ref["placement_id"] == placement_id

    assert event.evidence_ref["bulk_workflow_item"] == %{
             "kind" => "telemetry_correction_authority_workflow_item",
             "workflow_id" => "bulk-correction-workflow-1",
             "item_index" => item_index,
             "item_count" => 3,
             "observation_identity_id" => observation_identity_id,
             "selection_kind" => "open_comparison_findings"
           }

    assert event.evidence_ref["correction_workflow"] == %{
             "authority" => "operator",
             "id" => "bulk-correction-workflow-1",
             "item_count" => 3,
             "item_index" => item_index,
             "item_observation_identity_id" => observation_identity_id,
             "kind" => "telemetry_correction_authority_workflow",
             "operator_id" => "operator-7",
             "reason" => "operator_accepted_bulk_correction_authority_review",
             "requested_by" => "dashboard_comparison_review",
             "selection_kind" => "open_comparison_findings"
           }
  end

  def assert_bulk_conflict_decision_event!(
        observation_identity_id,
        item_index,
        placement_id
      ) do
    assert [event] =
             Storage.list_observation_identity_decision_events(
               observation_identity_id,
               organization_id: "org-product",
               mission_id: "mission-product",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

    assert event.decision == :mark_conflict
    assert event.decision_reason == "dashboard_comparison_review_mark_conflict"
    assert event.actor_id == "operator-7"
    assert event.actor_kind == "operator"
    assert event.new_state["validity_state"] == "conflict"
    assert event.evidence_ref["kind"] == "dashboard_comparison_review_finding"
    assert event.evidence_ref["placement_id"] == placement_id
    assert event.evidence_ref["comparison_finding"]["placement_id"] == placement_id

    assert event.evidence_ref["bulk_workflow_item"] == %{
             "kind" => "telemetry_correction_authority_workflow_item",
             "workflow_id" => "review-request-1",
             "item_index" => item_index,
             "item_count" => 2,
             "observation_identity_id" => observation_identity_id,
             "selection_kind" => "open_comparison_findings"
           }

    assert event.evidence_ref["correction_workflow"] == %{
             "authority" => "operator",
             "id" => "review-request-1",
             "item_count" => 2,
             "item_index" => item_index,
             "item_observation_identity_id" => observation_identity_id,
             "kind" => "telemetry_correction_authority_workflow",
             "operator_id" => "operator-7",
             "reason" => "dashboard_comparison_review_mark_conflict",
             "requested_by" => "dashboard_comparison_review",
             "selection_kind" => "open_comparison_findings"
           }
  end

  def provenance(opts) do
    storage =
      %{}
      |> maybe_put("realm", atom_text(Keyword.get(opts, :realm)))
      |> maybe_put("data_source_id", Keyword.get(opts, :data_source_id))
      |> maybe_put("binding_id", Keyword.get(opts, :binding_id))

    if map_size(storage) == 0 do
      %{}
    else
      %{"storage" => storage}
    end
  end

  def atom_text(nil), do: nil
  def atom_text(value) when is_atom(value), do: Atom.to_string(value)
  def atom_text(value), do: value

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def failed_historical_workflow_job(run_id, opts \\ []) do
    workflow =
      opts
      |> Keyword.get(:workflow, :backfill)
      |> atom_text()

    payload_attrs =
      case workflow do
        "import" -> %{"import_run_id" => run_id}
        _workflow -> %{"backfill_run_id" => run_id}
      end

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               run_id,
               %{"workflow" => workflow, "attrs" => payload_attrs}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
    assert failed_job.status == :failed

    failed_job
  end

  def running_historical_workflow_job(run_id, opts \\ []) do
    workflow =
      opts
      |> Keyword.get(:workflow, :backfill)
      |> atom_text()

    payload_attrs =
      case workflow do
        "import" -> %{"import_run_id" => run_id}
        _workflow -> %{"backfill_run_id" => run_id}
      end

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               run_id,
               %{"workflow" => workflow, "attrs" => payload_attrs}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    claimed_job
  end

  def stale_running_historical_workflow_job(run_id) do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               run_id,
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    stale_job = %{
      claimed_job
      | started_at: DateTime.add(DateTime.utc_now(), -1_200, :second)
    }

    assert %BackgroundJobRow{} =
             stale_job.job_id
             |> then(&Repo.get!(BackgroundJobRow, &1))
             |> BackgroundJobRow.changeset(stale_job)
             |> Repo.update!()

    Cadence.Jobs.fetch_job(stale_job.job_id)
  end

  def record_group_failed_event(event_id, run_id, item_index, opts) do
    workflow =
      opts
      |> Keyword.get(:workflow, :backfill)
      |> atom_text()

    failure =
      %{"retryable" => Keyword.fetch!(opts, :retryable)}
      |> maybe_put("recovery_action", Keyword.get(opts, :recovery_action))

    payload =
      %{
        "request_group_id" => Keyword.get(opts, :request_group_id, "backfill-run-group-failed"),
        "request_item_index" => item_index,
        "request_item_count" => Keyword.get(opts, :item_count, 4),
        "source" => %{"failure" => failure}
      }
      |> maybe_put("job_id", Keyword.get(opts, :job_id))
      |> maybe_put("dashboard_context", Keyword.get(opts, :dashboard_context))

    workflow_attrs =
      %{
        backfill_lifecycle_event_id: event_id,
        organization_id: "org-product",
        mission_id: "mission-product",
        realm: :backfill,
        data_source_id:
          Keyword.get(
            opts,
            :data_source_id,
            if(workflow == "import",
              do: "customer_archive_import",
              else: "managed_questdb_backfill"
            )
          ),
        binding_id:
          Keyword.get(
            opts,
            :binding_id,
            if(workflow == "import", do: "import_telemetry", else: "backfill_telemetry")
          ),
        observable_id: Keyword.get(opts, :observable_id, "HK.group_failed#{item_index}"),
        point_id: Keyword.get(opts, :point_id, "HK.group_failed#{item_index}"),
        source_from: ~U[2026-06-22 10:00:00Z],
        source_to: ~U[2026-06-22 11:00:00Z],
        authority: :advisory,
        reason: "historical_data_job_failed",
        payload: payload
      }
      |> Map.put(if(workflow == "import", do: :import_run_id, else: :backfill_run_id), run_id)

    Cadence.record_telemetry_historical_data_workflow_event(
      workflow,
      "failed",
      workflow_attrs,
      dashboard_runtime_invalidation?: false
    )
  end

  def event_stage_order(%{event_type: :backfill_requested}), do: 1
  def event_stage_order(%{event_type: :backfill_approved}), do: 2
  def event_stage_order(%{event_type: :backfill_started}), do: 3
  def event_stage_order(%{event_type: :backfill_completed}), do: 4
  def event_stage_order(%{event_type: :backfill_failed}), do: 5
  def event_stage_order(%{event_type: :backfill_retried}), do: 6
  def event_stage_order(%{event_type: :import_requested}), do: 1
  def event_stage_order(%{event_type: :import_approved}), do: 2
  def event_stage_order(%{event_type: :import_started}), do: 3
  def event_stage_order(%{event_type: :import_completed}), do: 4
  def event_stage_order(%{event_type: :import_failed}), do: 5
  def event_stage_order(%{event_type: :import_retried}), do: 6
  def event_stage_order(_event), do: 99
end
