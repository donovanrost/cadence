defmodule Cadence.Commanding.CommandApprovalRecordTest do
  @moduledoc """
  #117 step 4b (P3; DECISIONS #112; ca-security, domain, api-ops): a command request's decision row
  is a complete four-eyes record, provable from the row alone. A decision names the review token
  it decided, exactly the ids the separation check was given, and admin_mode (no default: a
  missing one raises). A request released without a second GO gets its own `not_required` row in
  the release's transaction; `decide_request` never writes one. The migration refuses while rows
  exist.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.{Ids, Missions, Organizations}

  alias Cadence.Commanding.{
    ApprovalDecisions,
    CommandApprovalRow,
    CommandRequest,
    CommandRequestRow,
    RequestQueueStore,
    RequestStore
  }

  alias Cadence.Governance.DecisionRecord
  alias Cadence.Management.Commanding.ReviewPrecondition
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @migration "repo/migrations/20261121100000_command_approval_record.exs"

  test "a decision records its review token, separated_from and admin_mode, read back from the row" do
    c = fixture!(:approval_pending)
    {:ok, request} = RequestStore.fetch_request(c.org, c.mission, c.request)
    token = ReviewPrecondition.digest(request)

    assert {:ok, %{approval: approval}} =
             RequestStore.decide_request(
               c.org,
               c.mission,
               c.request,
               :approved,
               %{"actor_kind" => "user", "user_id" => "reviewer"},
               expected_review: token,
               admin_mode: true
             )

    row = Repo.get!(CommandApprovalRow, approval.command_approval_id)
    assert row.subject_digest == token
    # Exactly what ensure_not_self_approval gave Accountability.separate: the requester.
    assert row.separated_from == ["requester"]
    assert row.admin_mode == true

    assert [%DecisionRecord{decision: :approved, admin_mode: true, subject: subject}] =
             ApprovalDecisions.decisions(c.org)

    assert subject == %{
             kind: "command_request",
             id: c.request,
             version: nil,
             digest: token,
             previous_digest: nil
           }
  end

  test "admin_mode has no default: a decider that omits it raises, and nothing is written" do
    c = fixture!(:approval_pending)

    assert_raise KeyError, ~r/:admin_mode/, fn ->
      RequestStore.decide_request(
        c.org,
        c.mission,
        c.request,
        :approved,
        %{"actor_kind" => "user", "user_id" => "reviewer"},
        []
      )
    end

    assert Repo.all(CommandApprovalRow) == []
  end

  test "decide_request never writes not_required: only a release does (ca-security)" do
    c = fixture!(:approval_pending)

    assert_raise FunctionClauseError, fn ->
      RequestStore.decide_request(
        c.org,
        c.mission,
        c.request,
        :not_required,
        %{"actor_kind" => "user", "user_id" => "reviewer"},
        admin_mode: false
      )
    end
  end

  test "a request released without a second GO records not_required in the release; admin_mode required" do
    c = fixture!(:validated)
    {:ok, request} = RequestStore.fetch_request(c.org, c.mission, c.request)
    by = %{"actor_kind" => "user", "user_id" => "releaser"}

    assert_raise KeyError, ~r/:admin_mode/, fn ->
      RequestQueueStore.enqueue_request(c.org, c.mission, c.request, by, [])
    end

    assert {:ok, _} =
             RequestQueueStore.enqueue_request(c.org, c.mission, c.request, by, admin_mode: false)

    assert [row] =
             Repo.all(from(r in CommandApprovalRow, where: r.command_request_id == ^c.request))

    assert row.decision == "not_required"
    assert row.separated_from == []
    assert row.admin_mode == false
    assert row.subject_digest == ReviewPrecondition.digest(request)
    assert row.decided_by_document["value"]["user_id"] == "releaser"
  end

  test "the migration refuses while command_approvals has rows, before any DDL" do
    [{module, _bytecode} | _] =
      Code.require_file(Path.join(to_string(:code.priv_dir(:cadence)), @migration))

    assert {:ok, _} = Repo.query(module.guard_sql())

    c = fixture!(:approval_pending)

    {:ok, _} =
      RequestStore.decide_request(
        c.org,
        c.mission,
        c.request,
        :rejected,
        %{"actor_kind" => "user", "user_id" => "reviewer"},
        reason: "No",
        admin_mode: false
      )

    assert {:error, %Postgrex.Error{postgres: %{message: message}}} =
             Repo.query(module.guard_sql())

    assert message =~ "command_approvals has 1 row(s)"
    assert message =~ "Never a trigger-disabled DELETE"
  end

  defp fixture!(state) do
    id = Ids.new("record_test")

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{organization_id: id, slug: id, display_name: "Record test"})
      )

    {:ok, mission} =
      Missions.persist_mission(
        Mission.new(%{
          mission_id: id,
          organization_id: org.organization_id,
          slug: id,
          display_name: "Record test"
        })
      )

    request =
      CommandRequest.new(%{
        command_request_id: id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: "endpoint",
        mission_model_revision_id: "model",
        command_id: "command",
        command_name: "Recorded command",
        lifecycle_state: state,
        requested_by: %{"actor_kind" => "user", "user_id" => "requester"},
        argument_values: %{"amount" => 3},
        resolved_argument_values: %{"amount" => 3},
        requested_at: DateTime.utc_now()
      })

    Repo.insert!(CommandRequestRow.changeset(request))
    %{org: org.organization_id, mission: mission.mission_id, request: request.command_request_id}
  end
end
