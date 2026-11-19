defmodule Cadence.ContactPlanning.PlanOperationsReplayTest do
  @moduledoc """
  #273 (ca-security): a row recorded under layout 1 still replays for the same request WITHOUT an
  expected_expired_digest, and never matches a request WITH one.
  """

  use Cadence.DataCase, async: true

  alias Cadence.ContactPlanning.PlanOperations
  alias Cadence.Repo

  @request %{expected_version: 2, note: "Ok", acknowledgements: []}

  setup do
    org = "ops-org-#{System.unique_integer([:positive])}"
    mission = "ops-mission-#{System.unique_integer([:positive])}"
    answer = %{"plan_id" => "plan-1", "outcome" => "approved"}

    Repo.insert_all(PlanOperations, [
      %{
        contact_plan_operation_id: "op-row-#{System.unique_integer([:positive])}",
        organization_id: org,
        mission_id: mission,
        operation_id: "op-v1",
        contact_plan_id: "plan-1",
        action: "approve",
        actor_id: "user-1",
        request_sha256: PlanOperations.digest_v1(:approve, @request),
        response_status: 202,
        response_document: answer,
        inserted_at: DateTime.utc_now()
      }
    ])

    %{org: org, mission: mission, answer: answer}
  end

  test "a layout-1 row replays a request without an expected expired digest", c do
    assert {:replay, {202, answer}} =
             PlanOperations.check(
               c.org,
               c.mission,
               "op-v1",
               "plan-1",
               :approve,
               "user-1",
               @request
             )

    assert answer == c.answer
  end

  test "a request with an expected expired digest never matches a layout-1 row", c do
    request = Map.put(@request, :expected_expired_digest, "abc123")

    assert :duplicate_operation =
             PlanOperations.check(
               c.org,
               c.mission,
               "op-v1",
               "plan-1",
               :approve,
               "user-1",
               request
             )
  end
end
