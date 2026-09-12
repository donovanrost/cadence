defmodule Cadence.Reads.CommandReviewTest do
  use Cadence.DataCase, async: true
  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Commanding.{CommandApproval, CommandApprovalRow, CommandRequestRow, RequestStore}
  alias Cadence.CommandReviewFixtures, as: Fixtures
  alias Cadence.Management.Commanding.RequestReview
  alias Cadence.Reads.{CommandMonitor, CommandReview}

  setup do
    c = Fixtures.scope!()
    Map.put(c, :request, Fixtures.request!(c))
  end

  test "the reviewed request exposes exact semantics and curated actor evidence", c do
    assert {:ok, data} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)
    document = data |> Jason.encode!() |> Jason.decode!()
    assert document["request"]["source_endpoint_ref"] == "endpoint_review"

    assert Jason.decode!(document["request"]["resolved_argument_values_json"]) == %{
             "amount" => 3,
             "channel" => "primary"
           }

    assert document["can_decide"]
    assert document["history"] == %{"entries" => [], "limit" => 25, "next_after" => nil}
    refute Jason.encode!(data) =~ "private-"

    assert {:ok, receipt} =
             RequestReview.decide(c.scope, c.mission, c.request.command_request_id, input(data))

    assert receipt["actor_id"] == c.user.user_id
    assert receipt["decision"] == "approved"

    assert {:ok, current} =
             RequestStore.fetch_request(c.org, c.mission, c.request.command_request_id)

    assert current.lifecycle_state == :approved

    assert {:rejected, _} =
             RequestReview.decide(c.scope, c.mission, c.request.command_request_id, input(data))

    assert [%{decided_by: actor}] = RequestStore.list_approvals(c.org, c.mission, [])
    assert actor == %{"actor_kind" => "user", "user_id" => c.user.user_id}
  end

  test "a 2000-byte review reason survives persistence and history without truncation", c do
    reason = String.duplicate("é", 1000)
    assert byte_size(reason) == 2000
    assert {:ok, data} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)

    assert {:ok, _receipt} =
             RequestReview.decide(
               c.scope,
               c.mission,
               c.request.command_request_id,
               Map.put(input(data), "reason", reason)
             )

    assert {:ok, current} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)
    assert [decision] = current["history"]["entries"]
    assert decision["reason"] == reason
  end

  test "approval history is paged by durable identity within the exact request", c do
    other = Fixtures.request!(c)

    for n <- 0..26 do
      approval!(
        c,
        c.request.command_request_id,
        "decision-#{String.pad_leading(to_string(n), 3, "0")}"
      )

      approval!(c, other.command_request_id, "foreign-#{n}")
    end

    assert {:ok, first} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)
    assert length(first["history"]["entries"]) == 25
    assert first["history"]["next_after"] == "decision-024"

    assert {:ok, last} =
             CommandReview.load(c.scope, c.mission, c.request.command_request_id, %{
               "after" => "decision-024"
             })

    assert Enum.map(last["history"]["entries"], & &1["id"]) == ["decision-025", "decision-026"]
    assert is_nil(last["history"]["next_after"])
    refute Jason.encode!(first) =~ "private-approval"

    assert {:error, :unavailable} =
             CommandReview.load(c.scope, c.mission, c.request.command_request_id, %{
               "request_id" => other.command_request_id
             })
  end

  test "fresh persisted account and membership deny stale scope reads and decisions", c do
    assert {:ok, data} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)
    assert {:ok, %{can_review: true}} = CommandMonitor.load(c.scope, c.mission)

    for {schema, id, attrs} <- [
          {OrganizationMembershipRow, c.member.organization_membership_id, [role: "member"]},
          {OrganizationMembershipRow, c.member.organization_membership_id,
           [lifecycle_state: "revoked"]},
          {UserRow, c.user.user_id, [lifecycle_state: "disabled"]}
        ] do
      row = Repo.get!(schema, id)
      row |> change(attrs) |> Repo.update!()
      assert {:ok, %{can_review: false}} = CommandMonitor.load(c.scope, c.mission)

      assert {:error, :unavailable} =
               CommandReview.load(c.scope, c.mission, c.request.command_request_id)

      assert {:rejected, _} =
               RequestReview.decide(c.scope, c.mission, c.request.command_request_id, input(data))

      Repo.get!(schema, id)
      |> change(Map.take(Map.from_struct(row), Keyword.keys(attrs)))
      |> Repo.update!()
    end

    assert RequestStore.list_approvals(c.org, c.mission, []) == []
  end

  test "foreign scopes, service actors and self-review cannot decide", c do
    assert {:ok, data} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)
    foreign = Fixtures.scope!()

    for scope <- [
          foreign.scope,
          %{c.scope | mission_id: "foreign"},
          %{c.scope | actor_kind: :service}
        ] do
      assert {:error, :unavailable} =
               CommandReview.load(scope, c.mission, c.request.command_request_id)

      assert {:rejected, _} =
               RequestReview.decide(scope, c.mission, c.request.command_request_id, input(data))
    end

    request = Fixtures.request!(c, %{requested_by: %{"user_id" => c.user.user_id}})
    assert {:ok, self_review} = CommandReview.load(c.scope, c.mission, request.command_request_id)
    refute self_review["can_decide"]

    assert {:rejected, _} =
             RequestReview.decide(
               c.scope,
               c.mission,
               request.command_request_id,
               input(self_review)
             )

    assert RequestStore.list_approvals(c.org, c.mission, []) == []
  end

  test "changed content, forged actor, unknown input and oversized reasons fail before a decision",
       c do
    assert {:ok, data} = CommandReview.load(c.scope, c.mission, c.request.command_request_id)

    for bad <- [
          Map.put(input(data), "decided_by", %{"user_id" => "forged"}),
          Map.put(input(data), "reason", String.duplicate("é", 1001)),
          Map.put(input(data), "decision", "released"),
          Map.put(input(data), "expected_review", "x")
        ] do
      assert {:rejected, _} =
               RequestReview.decide(c.scope, c.mission, c.request.command_request_id, bad)
    end

    Repo.get!(CommandRequestRow, c.request.command_request_id)
    |> change(priority: 1)
    |> Repo.update!()

    assert {:rejected, _} =
             RequestReview.decide(c.scope, c.mission, c.request.command_request_id, input(data))

    assert RequestStore.list_approvals(c.org, c.mission, []) == []
  end

  defp input(data),
    do: %{
      "decision" => "approved",
      "reason" => "Reviewed target and arguments",
      "expected_review" => data["expected_review"]
    }

  defp approval!(c, request, id) do
    approval =
      CommandApproval.new(%{
        command_approval_id: id,
        organization_id: c.org,
        mission_id: c.mission,
        command_request_id: request,
        decision: :rejected,
        decided_by: %{"user_id" => "reviewer", "private" => "private-approval"},
        decided_at: ~U[2026-09-10 08:01:00Z],
        reason: "Legacy decision",
        metadata: %{"private" => "private-approval"}
      })

    Repo.insert!(CommandApprovalRow.changeset(approval))
  end
end
