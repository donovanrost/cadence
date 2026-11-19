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

  test "golden digests: one fixed request per action" do
    assert PlanOperations.digest(:approve, @request) ==
             "a0854d493cd7541e2c00e2e5f3e201c8b944914392f1e285d97b403ea7886f4c"

    assert PlanOperations.digest(:submit, @request) ==
             "11b324bee0d933ab07e018d492356b7ebb570098306bbb1efaded36a4cfbf747"
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
