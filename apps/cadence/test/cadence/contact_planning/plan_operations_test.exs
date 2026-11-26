defmodule Cadence.ContactPlanning.PlanOperationsTest do
  @moduledoc """
  #257: the stored request digest is recomputed on every retry, so it is pinned (DECISIONS #108):
  a change to the normalization or the encoding would silently turn replays into
  duplicate_operation refusals.
  """

  use ExUnit.Case, async: true

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.PlanOperations

  @request %{
    expected_version: 3,
    note: "  Checked the gaps  ",
    acknowledgements: [
      %{requirement_id: "req-b", reason: " Second gap accepted "},
      %{requirement_id: "req-a", reason: "First gap accepted"}
    ]
  }

  # The approver's expected_expired_digest is part of the request (#273; nil when absent).
  test "golden digests: with and without the expected expired digest" do
    assert PlanOperations.digest(:approve, @request) ==
             "9421c1ee50d99f0a2bbbc3d8bad948de23a0636f11560eea08c0c0379c05a81d"

    assert PlanOperations.digest(:approve, Map.put(@request, :expected_expired_digest, "abc123")) ==
             "ff23db96ebb43eb7ed5912be74f845414fa054b0cf9f97bcd8aa21e97b0453c7"

    assert PlanOperations.digest(:submit, @request) ==
             "95089a90d7c522baa2e5d70b66601252e8d32f13eac6e722a962840c208bced9"

    # A blank digest is the same request as none.
    assert PlanOperations.digest(:approve, Map.put(@request, :expected_expired_digest, "")) ==
             PlanOperations.digest(:approve, @request)
  end

  test "normalization: whitespace, blank notes and acknowledgement order don't change it" do
    normalized = %{
      expected_version: 3,
      note: "Checked the gaps",
      acknowledgements: [
        %{requirement_id: "req-a", reason: "First gap accepted"},
        %{requirement_id: "req-b", reason: "Second gap accepted"}
      ]
    }

    assert PlanOperations.digest(:approve, normalized) ==
             PlanOperations.digest(:approve, @request)

    assert PlanOperations.digest(:approve, %{expected_version: 1, note: "   "}) ==
             PlanOperations.digest(:approve, %{
               expected_version: 1,
               note: nil,
               acknowledgements: []
             })

    refute PlanOperations.digest(:approve, @request) ==
             PlanOperations.digest(:approve, %{@request | expected_version: 4})
  end

  test "the actor fails closed: a scope with neither a user nor a service identity is refused" do
    assert {:ok, "user-1"} = PlanOperations.actor_id(%Scope{user: %{user_id: "user-1"}})

    assert {:ok, "svc-1"} =
             PlanOperations.actor_id(%Scope{service_identity: %{service_identity_id: "svc-1"}})

    assert {:error, :forbidden} = PlanOperations.actor_id(%Scope{})
  end
end
