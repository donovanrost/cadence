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

  # Layout 1 (#257): still pinned, because rows recorded before #273 compare against it.
  test "golden digests, layout 1: one fixed request per action" do
    assert PlanOperations.digest_v1(:approve, @request) ==
             "a0854d493cd7541e2c00e2e5f3e201c8b944914392f1e285d97b403ea7886f4c"

    assert PlanOperations.digest_v1(:submit, @request) ==
             "11b324bee0d933ab07e018d492356b7ebb570098306bbb1efaded36a4cfbf747"
  end

  # Layout 2 (#273): adds the approver's expected_expired_digest (nil when absent).
  test "golden digests, layout 2: with and without the expected expired digest" do
    assert PlanOperations.digest(:approve, @request) ==
             "9421c1ee50d99f0a2bbbc3d8bad948de23a0636f11560eea08c0c0379c05a81d"

    assert PlanOperations.digest(:approve, Map.put(@request, :expected_expired_digest, "abc123")) ==
             "ff23db96ebb43eb7ed5912be74f845414fa054b0cf9f97bcd8aa21e97b0453c7"

    refute PlanOperations.digest(:approve, @request) ==
             PlanOperations.digest_v1(:approve, @request)

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
