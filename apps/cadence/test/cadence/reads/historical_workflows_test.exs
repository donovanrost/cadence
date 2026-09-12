defmodule Cadence.Reads.HistoricalWorkflowsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.Scope
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Jobs
  alias Cadence.Management.DataSources.Store
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.HistoricalWorkflows, as: Read
  alias Cadence.Telemetry.DataManagement
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow

  setup do
    %{organization: org} = persist_mission_scope("org-history", "mission-history")
    %{reader: scope(org, :member), admin: scope(org, :organization_admin)}
  end

  test "mission readers receive real history while management stays administrator scoped", c do
    insert_events("group-one", 1)
    insert_events("foreign", 1, mission: "foreign")

    assert {:ok, model, review} =
             Read.load(c.reader, "mission-history", "reader", %{"group" => "group-one"})

    assert model.permissions == %{request: true, manage: false}
    assert model.groups.total == 1
    assert model.selected.summary.requested == 1
    assert model.selected.audit.entries |> hd() |> Map.fetch!(:id) == "group-one-event-1"
    assert Enum.all?(model.selected.transitions, &(&1.eligible_count == 0))
    assert length(review.selected.events) == 1
    assert {:error, :forbidden} = Read.load(c.reader, "mission-history", "manage", %{})

    assert {:ok, admin, _} =
             Read.load(c.admin, "mission-history", "manage", %{"group" => "group-one"})

    assert Enum.find(admin.selected.transitions, &(&1.stage == "approved")).eligible_count == 1

    assert {:error, {:request_group_not_found, "foreign"}} =
             Read.load(c.admin, "mission-history", "reader", %{"group" => "foreign"})
  end

  test "a group beyond 1000 events has bounded audit pages and complete review evidence", c do
    insert_events("large", 1_005)

    assert {:ok, model, review} =
             Read.load(c.admin, "mission-history", "manage", %{
               "group" => "large",
               "audit_page" => "41"
             })

    assert model.selected.summary.size == 1_005
    assert model.selected.audit.total == 1_005
    assert length(model.selected.audit.entries) == 5
    assert length(review.selected.events) == 1_005
    assert {:ok, json} = JSONBoundary.safe_workflow_output(model)
    assert length(json["selected"]["audit"]["entries"]) == 5
    refute Map.has_key?(json["selected"], "events")
  end

  test "directory, audit and origin paging remain independent of selected group", c do
    insert_events("selected", 61, origins: true)
    for index <- 1..26, do: insert_events("directory-#{index}", 1)

    assert {:ok, model, _} =
             Read.load(c.admin, "mission-history", "manage", %{
               "group" => "selected",
               "page" => "2",
               "audit_page" => "3",
               "origins_page" => "3"
             })

    assert model.groups.total == 27
    assert length(model.groups.entries) == 2
    assert model.selected.id == "selected"
    assert model.selected.audit.total == 61
    assert length(model.selected.audit.entries) == 11
    assert model.selected.origins.total == 61
    assert length(model.selected.origins.entries) == 11
  end

  test "current job evidence changes the review and stage availability without writing events",
       c do
    insert_events("selected", 1)
    attrs = %{organization_id: "org-history", mission_id: "mission-history"}

    assert {:ok, _, _} =
             DataManagement.record_historical_data_workflow_group_transition(
               :backfill,
               :approved,
               "selected",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, before, _} =
             Read.load(c.admin, "mission-history", "manage", %{"group" => "selected"})

    assert Enum.find(before.selected.transitions, &(&1.stage == "started")).eligible_count == 1

    assert {:ok, job} =
             Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-history",
               "selected-run-1",
               %{}
             )

    assert {:ok, after_job, _} =
             Read.load(c.admin, "mission-history", "manage", %{"group" => "selected"})

    assert after_job.selected.evidence != before.selected.evidence
    assert Enum.find(after_job.selected.transitions, &(&1.stage == "started")).eligible_count == 0
    assert [entry] = after_job.selected.jobs.entries
    assert entry.id == job.job_id
    assert entry.status == "queued"
    assert Repo.aggregate(EventRow, :count) == 2
  end

  test "binding choices page actual active scoped telemetry bindings and preserve supplied defaults",
       c do
    assert {:ok, source} =
             Store.persist_data_source(%DataSource{
               data_source_id: "history-source",
               organization_id: "org-history",
               mission_id: "mission-history",
               isolation_level: :mission_isolated,
               adapter: Cadence.Dashboards.Sources.Telemetry
             })

    for index <- 1..31 do
      assert {:ok, _} =
               Store.persist_data_binding(%DataBinding{
                 binding_id: "history-binding-#{String.pad_leading(to_string(index), 2, "0")}",
                 organization_id: "org-history",
                 mission_id: "mission-history",
                 data_source_id: source.data_source_id,
                 realm: :backfill,
                 logical_source: :telemetry
               })
    end

    defaults = Map.put(Read.initial_defaults(), "reason", "Keep this draft")

    assert {:ok, model, internal} =
             Read.load(
               c.reader,
               "mission-history",
               "reader",
               %{"binding_q" => "history-binding", "bindings_page" => "2"},
               defaults
             )

    assert model.bindings.total == 31
    assert length(model.bindings.entries) == 6
    assert model.defaults == defaults

    assert Enum.all?(model.bindings.entries, fn binding ->
             binding.source_id == source.data_source_id and binding.realm == "backfill" and
               internal.bindings[binding.id] == binding.evidence
           end)
  end

  test "query admission rejects unowned or malformed selectors" do
    for params <- [
          %{"mission_id" => "other"},
          %{"page" => "0"},
          %{"page" => "1000001"},
          %{"group" => []},
          %{"binding_q" => <<255>>}
        ] do
      assert {:error, :invalid_historical_workflow_query} = Read.admit_query(params)
    end
  end

  test "correction availability follows the actual job identity and completed lineage", c do
    assert {:ok, job} =
             Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-history",
               "failed-run",
               %{}
             )

    assert [_] = Jobs.claim_jobs(1)
    assert {:ok, _} = Jobs.fail_worker_start(job.job_id, :source_failed)

    attrs = %{
      organization_id: "org-history",
      mission_id: "mission-history",
      backfill_run_id: "failed-run",
      realm: :backfill,
      data_source_id: "source",
      binding_id: "binding",
      payload: %{
        "request_group_id" => "correction",
        "host_operation_id" => "failed-operation",
        "job_id" => "wrong-job",
        "source" => %{
          "failure" => %{"retryable" => false, "recovery_action" => "correct_workflow_request"}
        }
      }
    }

    assert {:ok, wrong} =
             DataManagement.record_historical_data_workflow_event(
               :backfill,
               :failed,
               attrs,
               dashboard_runtime_invalidation?: false
             )

    attrs = put_in(attrs, [:payload, "job_id"], job.job_id)

    assert {:ok, valid} =
             DataManagement.record_historical_data_workflow_event(
               :backfill,
               :failed,
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, before, _} =
             Read.load(c.admin, "mission-history", "manage", %{"group" => "correction"})

    rows = Map.new(before.selected.audit.entries, &{&1.id, &1})
    refute rows[wrong.backfill_lifecycle_event_id].correction_available
    assert rows[valid.backfill_lifecycle_event_id].correction_available
    assert rows[valid.backfill_lifecycle_event_id].operation_id == "failed-operation"

    assert {:ok, _} =
             DataManagement.record_historical_data_workflow_event(
               :backfill,
               :completed,
               %{
                 attrs
                 | backfill_run_id: "replacement-run",
                   payload: %{"corrects_event_id" => valid.backfill_lifecycle_event_id}
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, after_completion, _} =
             Read.load(c.admin, "mission-history", "manage", %{"group" => "correction"})

    assert before.selected.evidence != after_completion.selected.evidence

    refute Enum.find(
             after_completion.selected.audit.entries,
             &(&1.id == valid.backfill_lifecycle_event_id)
           ).correction_available
  end

  defp scope(org, role) do
    user =
      User.new(%{
        user_id: "history-user-#{role}",
        email: "#{role}@example.test",
        display_name: "History operator"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization: org,
      organization_id: org.organization_id,
      organization_membership: membership
    })
  end

  defp insert_events(group, count, opts \\ []) do
    time = ~U[2026-09-09 00:00:00.000000Z]

    rows =
      Enum.map(1..count, fn index ->
        payload = %{
          "request_group_id" => group,
          "request_item_index" => index,
          "request_item_count" => count,
          "workflow" => "backfill",
          "stage" => "requested"
        }

        payload =
          if opts[:origins],
            do: Map.put(payload, "dashboard_context", %{"dashboard_id" => "dashboard-#{index}"}),
            else: payload

        %{
          backfill_lifecycle_event_id: "#{group}-event-#{index}",
          backfill_run_id: "#{group}-run-#{index}",
          organization_id: "org-history",
          mission_id: Keyword.get(opts, :mission, "mission-history"),
          realm: "backfill",
          data_source_id: "source",
          binding_id: "binding",
          point_id: "point-#{index}",
          event_type: "backfill_requested",
          authority: "advisory",
          reason: "Requested",
          occurred_at: time,
          inserted_at: time,
          payload: %{"value" => payload}
        }
      end)

    assert {^count, nil} = Repo.insert_all(EventRow, rows)
  end
end
