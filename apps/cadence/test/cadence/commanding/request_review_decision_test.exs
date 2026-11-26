defmodule Cadence.Commanding.RequestReviewDecisionTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.{
    CommandApproval,
    CommandApprovalRow,
    CommandRequest,
    CommandRequestRow,
    RequestStore
  }

  alias Cadence.{Ids, Missions, Organizations}
  alias Cadence.Management.Commanding.ReviewPrecondition
  alias Cadence.Missions.{Mission, MissionRow}
  alias Cadence.Organizations.{Organization, OrganizationRow}
  alias Cadence.TestSupport.DecisionRecordPurge
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  test "review preconditions, self-review and human-actor rules cannot create a decision" do
    c = fixture!()
    assert {:ok, request} = RequestStore.fetch_request(c.org, c.mission, c.request)
    review = ReviewPrecondition.digest(request)

    assert {:error, :command_review_changed} =
             decide(c, :approved, "reviewer", expected_review: String.duplicate("0", 64))

    assert {:error, {:command_request_self_approval_not_allowed, _}} =
             decide(c, :approved, "requester", expected_review: review)

    assert {:error, {:command_request_approval_requires_user_actor, _}} =
             RequestStore.decide_request(
               c.org,
               c.mission,
               c.request,
               :approved,
               %{"service_identity_id" => "service"},
               expected_review: review
             )

    assert RequestStore.list_approvals(c.org, c.mission, []) == []
    assert {:ok, result} = decide(c, :approved, "reviewer", expected_review: review)
    assert result.approval.decision == :approved
    assert result.command_request.lifecycle_state == :approved

    assert {:error, :command_review_changed} =
             decide(c, :rejected, "other-reviewer", expected_review: review)

    assert length(RequestStore.list_approvals(c.org, c.mission, [])) == 1
  end

  # #117 step 4a (four-eyes design B): a caller that requires the token (REST approve and reject)
  # is refused without it, and only after the human-approver check (api-ops), recording nothing.
  test "a required review token: absent is refused after the human check; present decides" do
    c = fixture!()
    assert {:ok, request} = RequestStore.fetch_request(c.org, c.mission, c.request)

    assert {:error, {:command_request_approval_requires_user_actor, _}} =
             RequestStore.decide_request(
               c.org,
               c.mission,
               c.request,
               :approved,
               %{"service_identity_id" => "service"},
               require_review: true
             )

    assert {:error, :command_review_required} =
             decide(c, :approved, "reviewer", require_review: true)

    # api-ops on #631: a token that isn't one is malformed (422), not stale; and a service gets
    # its human-approver refusal first, whatever token it sends.
    assert {:error, :command_review_invalid} =
             decide(c, :approved, "reviewer", require_review: true, expected_review: "junk")

    assert {:error, {:command_request_approval_requires_user_actor, _}} =
             RequestStore.decide_request(
               c.org,
               c.mission,
               c.request,
               :approved,
               %{"service_identity_id" => "service"},
               require_review: true,
               expected_review: String.duplicate("0", 64)
             )

    assert RequestStore.list_approvals(c.org, c.mission, []) == []

    assert {:ok, _} =
             decide(c, :rejected, "reviewer",
               require_review: true,
               expected_review: ReviewPrecondition.digest(request)
             )
  end

  test "an unknown approval decision never reads as approved (#117 step 4a)" do
    assert_raise ArgumentError, ~r/unknown command approval decision/, fn ->
      CommandApproval.new(%{
        organization_id: "org",
        mission_id: "mission",
        command_request_id: "request",
        decision: "not_required",
        decided_by: %{},
        decided_at: DateTime.utc_now()
      })
    end
  end

  test "two independent database connections cannot both decide the same pending request" do
    c = independent(&fixture!/0) |> Task.await()
    on_exit(fn -> independent(fn -> cleanup(c) end) |> Task.await() end)
    parent = self()

    blocker =
      independent(fn ->
        Repo.transaction(fn ->
          Repo.one!(
            from(row in CommandRequestRow,
              where: row.command_request_id == ^c.request,
              lock: "FOR UPDATE"
            )
          )

          send(parent, {:locked, self()})

          receive do
            :release -> :released
          after
            10_000 -> raise "lock release not delivered"
          end
        end)
      end)

    assert_receive {:locked, blocker_pid}, 2_000

    tasks =
      for {decision, reviewer} <- [{:approved, "reviewer-a"}, {:rejected, "reviewer-b"}] do
        independent(fn ->
          %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
          send(parent, {:decision_backend, pid})
          decide(c, decision, reviewer)
        end)
      end

    try do
      assert_receive {:decision_backend, first}, 2_000
      assert_receive {:decision_backend, second}, 2_000
      assert first != second
      assert wait_for_locks([first, second], 200)
      send(blocker_pid, :release)
      assert {:ok, :released} = Task.await(blocker)
      results = Enum.map(tasks, &Task.await(&1, 5_000))
      assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1

      assert length(
               Enum.filter(
                 results,
                 &match?({:error, {:command_request_not_pending_approval, _, _}}, &1)
               )
             ) == 1

      {request, approvals} =
        independent(fn ->
          {:ok, request} = RequestStore.fetch_request(c.org, c.mission, c.request)
          {request, RequestStore.list_approvals(c.org, c.mission, [])}
        end)
        |> Task.await()

      assert [approval] = approvals
      assert request.lifecycle_state == approval.decision
    after
      send(blocker_pid, :release)
      Task.shutdown(blocker, :brutal_kill)
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp decide(c, decision, reviewer, opts \\ []) do
    RequestStore.decide_request(
      c.org,
      c.mission,
      c.request,
      decision,
      %{"actor_kind" => "user", "user_id" => reviewer},
      opts
    )
  end

  defp fixture! do
    id = Ids.new("review_test")

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{organization_id: id, slug: id, display_name: "Review test"})
      )

    {:ok, mission} =
      Missions.persist_mission(
        Mission.new(%{
          mission_id: id,
          organization_id: org.organization_id,
          slug: id,
          display_name: "Review test"
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
        command_name: "Reviewed command",
        lifecycle_state: :approval_pending,
        requested_by: %{"actor_kind" => "user", "user_id" => "requester"},
        argument_values: %{"amount" => 3},
        resolved_argument_values: %{"amount" => 3},
        requested_at: DateTime.utc_now()
      })

    Repo.insert!(CommandRequestRow.changeset(request))
    %{org: org.organization_id, mission: mission.mission_id, request: request.command_request_id}
  end

  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_for_locks(_, 0), do: false

  defp wait_for_locks(pids, attempts) do
    %{rows: [[count]]} =
      SQL.query!(
        Repo,
        "SELECT count(DISTINCT pid) FROM pg_locks WHERE pid = ANY($1) AND NOT granted",
        [pids]
      )

    if count == length(pids) do
      true
    else
      Process.sleep(10)
      wait_for_locks(pids, attempts - 1)
    end
  end

  # Outside the sandbox: decision rows are append-only (DECISIONS #107), so their cleanup runs
  # with the test-only purge setting.
  defp cleanup(c) do
    {:ok, _} =
      DecisionRecordPurge.run(fn ->
        Repo.delete_all(
          from(row in CommandApprovalRow,
            where: row.organization_id == ^c.org and row.mission_id == ^c.mission
          )
        )
      end)

    Repo.delete_all(
      from(row in CommandRequestRow,
        where: row.organization_id == ^c.org and row.mission_id == ^c.mission
      )
    )

    Repo.delete_all(
      from(row in MissionRow,
        where: row.organization_id == ^c.org and row.mission_id == ^c.mission
      )
    )

    Repo.delete_all(from(row in OrganizationRow, where: row.organization_id == ^c.org))
  end
end
