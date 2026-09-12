defmodule Cadence.Applications.HistoricalWorkflowActionsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.OpsConsole.Actions.HistoricalWorkflowActions, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Jobs
  alias Cadence.Management.DataSources.Store
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.HistoricalWorkflows, as: Read
  alias Cadence.Telemetry.DataManagement
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow

  setup do
    %{organization: org} = persist_mission_scope("org-native", "mission-native")

    user =
      User.new(%{user_id: "native-user", email: "native@example.test", display_name: "Native"})

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: :organization_admin
      })

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    assert {:ok, _} =
             Store.persist_data_source(%DataSource{
               data_source_id: "native-source",
               organization_id: org.organization_id,
               mission_id: "mission-native",
               isolation_level: :mission_isolated,
               adapter: Cadence.Dashboards.Sources.Telemetry
             })

    assert {:ok, binding} =
             Store.persist_data_binding(%DataBinding{
               binding_id: "native-binding",
               organization_id: org.organization_id,
               mission_id: "mission-native",
               data_source_id: "native-source",
               realm: :backfill,
               logical_source: :telemetry
             })

    %{scope: scope, binding: binding, capture: capture(scope)}
  end

  test "native validation is read only, confirmed requests retain exact input and reject duplicate runs",
       c do
    request = request(c)
    assert {:ok, %{valid: true}} = execute(c, "validate-request", request)
    assert Repo.aggregate(EventRow, :count) == 0

    unconfirmed = put_in(request, ["request", "confirmed"], "false")
    assert {:rejected, ["confirmation_required"]} = execute(c, "record-request", unconfirmed)
    assert Repo.aggregate(EventRow, :count) == 0

    assert {:ok, result} = execute(c, "record-request", request)
    assert result.group_id == "native-group"
    assert result.event_count == 2
    assert result.actor_id == c.scope.user.user_id
    assert result.operation_id == "operation-one"
    assert length(result.event_ids) == 2
    assert Repo.aggregate(EventRow, :count) == 2

    assert {:rejected, ["request_changed_or_exists"]} = execute(c, "record-request", request)
    assert Repo.aggregate(EventRow, :count) == 2
    rows = Repo.all(EventRow)
    assert Enum.all?(rows, &(&1.source_from == ~U[2026-09-08 14:00:17.000000Z]))
  end

  test "binding changes and unowned authority fields are rejected before effects", c do
    input = request(c)
    assert {:ok, _} = Store.persist_data_binding(%{c.binding | dataset: "changed-dataset"})
    assert {:rejected, ["request_changed_or_exists"]} = execute(c, "record-request", input)
    injected = put_in(input, ["request", "organization_id"], "foreign")
    assert {:rejected, ["invalid_or_unavailable"]} = execute(c, "record-request", injected)
    assert Repo.aggregate(EventRow, :count) == 0
  end

  test "group decisions consume exact review evidence and return actual started job identities",
       c do
    assert {:ok, _} = execute(c, "record-request", request(c))
    c = %{c | capture: capture(c.scope, "native-group")}
    approval = decision(c, "approved")
    assert {:ok, approved} = execute(c, "transition-group", approval)
    assert approved.event_count == 2
    assert {:rejected, ["review_changed"]} = execute(c, "transition-group", approval)

    c = %{c | capture: capture(c.scope, "native-group")}
    assert {:ok, started} = execute(c, "transition-group", decision(c, "started"))
    assert started.job_count == 2

    for id <- started.job_ids do
      assert {:ok, job} = Jobs.fetch_job(id)
      assert job.mission_id == "mission-native"
      assert job.payload["attrs"]["payload"]["host_operation_id"] == "operation-one"
    end
  end

  test "job changes invalidate an approved review and readers cannot manage", c do
    assert {:ok, _} = execute(c, "record-request", request(c))
    c = %{c | capture: capture(c.scope, "native-group")}
    assert {:ok, _} = execute(c, "transition-group", decision(c, "approved"))
    c = %{c | capture: capture(c.scope, "native-group")}

    assert {:ok, _} =
             Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-native",
               "native-group-001",
               %{}
             )

    count = Repo.aggregate(EventRow, :count)

    assert {:rejected, ["review_changed"]} =
             execute(c, "transition-group", decision(c, "started"))

    assert Repo.aggregate(EventRow, :count) == count

    assert {:rejected, ["forbidden"]} =
             Actions.execute(
               c.scope,
               "mission-native",
               "reader",
               c.capture,
               "transition-group",
               decision(c, "started"),
               "reader-op"
             )
  end

  test "independent page reads retain defaults and reject unknown selectors", c do
    assert {:page, model, _, %{"bindings_page" => "2"}} =
             execute(c, "read-page", %{"query" => %{"bindings_page" => "2"}})

    assert model.defaults == c.capture.model.defaults
    assert model.bindings.page == 2
    assert {:rejected, _} = execute(c, "read-page", %{"query" => %{"organization_id" => "other"}})
  end

  test "native retry preserves its decision reason and actual job and audit identities", c do
    {job, _event} = failed_item(c, true)
    c = %{c | capture: capture(c.scope, "failed-group")}
    reason = String.duplicate("界", 600)

    input = %{
      "group_id" => "failed-group",
      "evidence" => c.capture.model.selected.evidence,
      "reason" => reason,
      "confirmed" => true
    }

    assert {:ok, result} = execute(c, "retry-group", input)
    assert result.retry_counts == %{retried: 1, skipped: 0, nonretryable: 0, failed: 0}
    assert result.job_ids == [job.job_id]
    [event_id] = result.event_ids
    assert Cadence.Repo.get!(EventRow, event_id).reason == reason
    assert {:ok, current} = Jobs.fetch_job(job.job_id)
    assert current.status == :queued
  end

  test "native correction pins the failed event and cannot replay its old group review", c do
    {job, event} = failed_item(c, false)
    c = %{c | capture: capture(c.scope, "failed-group")}

    input = %{
      "group_id" => "failed-group",
      "evidence" => c.capture.model.selected.evidence,
      "event_id" => event.backfill_lifecycle_event_id,
      "reason" => "Correct the archived request",
      "confirmed" => true
    }

    assert {:ok, result} = execute(c, "request-correction", input)
    assert result.event_count == 1
    [id] = result.event_ids

    recorded =
      Cadence.Reads.Telemetry.fetch_backfill_lifecycle_event(id,
        organization_id: c.scope.organization_id,
        mission_id: "mission-native"
      )

    assert recorded.payload["corrects_event_id"] == event.backfill_lifecycle_event_id
    assert recorded.payload["corrects_job_id"] == job.job_id
    assert recorded.payload["request_group_id"] == "failed-group"
    assert {:rejected, ["review_changed"]} = execute(c, "request-correction", input)
  end

  defp failed_item(c, retryable) do
    assert {:ok, job} =
             Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-native",
               "failed-run",
               %{}
             )

    assert [_] = Jobs.claim_jobs(1)
    assert {:ok, job} = Jobs.fail_worker_start(job.job_id, :archive_failed)

    assert {:ok, event} =
             DataManagement.record_historical_data_workflow_event(
               :backfill,
               :failed,
               %{
                 organization_id: c.scope.organization_id,
                 mission_id: "mission-native",
                 backfill_run_id: job.run_id,
                 realm: :backfill,
                 data_source_id: "native-source",
                 binding_id: "native-binding",
                 payload: %{
                   "request_group_id" => "failed-group",
                   "job_id" => job.job_id,
                   "source" => %{
                     "failure" => %{
                       "retryable" => retryable,
                       "recovery_action" =>
                         if(retryable, do: "retry_job", else: "correct_workflow_request")
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    {job, event}
  end

  defp capture(scope, group \\ nil) do
    query = if group, do: %{"group" => group}, else: %{}
    assert {:ok, model, review} = Read.load(scope, "mission-native", "manage", query)
    %{model: model, review: review}
  end

  defp execute(c, action, input),
    do:
      Actions.execute(
        c.scope,
        "mission-native",
        "manage",
        c.capture,
        action,
        input,
        "operation-one"
      )

  defp decision(c, stage),
    do: %{
      "group_id" => "native-group",
      "evidence" => c.capture.model.selected.evidence,
      "stage" => stage,
      "reason" => String.duplicate("界", 600),
      "confirmed" => true
    }

  defp request(c),
    do: %{
      "binding_evidence" => c.capture.review.bindings["native-binding"],
      "request" => %{
        "workflow" => "backfill",
        "run_id" => "native-group",
        "realm" => "backfill",
        "data_source_id" => "native-source",
        "source_binding_id" => "native-binding",
        "point_ids" => "HK.temp,HK.rate",
        "source_from" => "2026-09-08T08:00:17-06:00",
        "source_to" => "2026-09-08T15:00:23Z",
        "reason" => String.duplicate("界", 600),
        "confirmed" => "true"
      }
    }
end
