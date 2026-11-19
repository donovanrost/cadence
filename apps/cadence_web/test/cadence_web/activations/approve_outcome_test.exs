defmodule CadenceWeb.Activations.ApproveOutcomeTest do
  @moduledoc """
  #263: once a REST activation approval is recorded, the answer says so whatever the apply does.
  An apply that fails, doesn't finish, errors or raises is `needs_review`, never a refusal, and its
  cause is logged (first line only), never sent.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cadence.Control.Activations.ActivationExecution
  alias CadenceWeb.Activations.ApproveOutcome

  test "a succeeded apply is applied; any other recorded execution needs review" do
    succeeded = %ActivationExecution{status: :succeeded}
    failed = %ActivationExecution{status: :failed}

    assert {^succeeded, "applied"} =
             ApproveOutcome.after_approval(:approved, "request-1", fn _ -> {:ok, succeeded} end)

    assert {^failed, "needs_review"} =
             ApproveOutcome.after_approval(:approved, "request-1", fn _ -> {:ok, failed} end)
  end

  test "an apply that errors before recording an execution needs review, the cause logged" do
    log =
      capture_log(fn ->
        assert {nil, "needs_review"} =
                 ApproveOutcome.after_approval(:approved, "request-2", fn _ ->
                   {:error, :activation_execution_interrupted}
                 end)
      end)

    assert log =~
             "activation request request-2: approved, but its apply didn't run: " <>
               "activation_execution_interrupted"
  end

  test "an apply that raises needs review, and only the first line of the cause is logged" do
    log =
      capture_log(fn ->
        assert {nil, "needs_review"} =
                 ApproveOutcome.after_approval(:approved, "request-3", fn _ ->
                   raise "apply broke\nrow values: secret-row"
                 end)
      end)

    assert log =~ "activation request request-3: approved, but its apply didn't run: apply broke"
    refute log =~ "secret-row"
  end

  test "an apply that exits or throws needs review, the cause logged" do
    log =
      capture_log(fn ->
        assert {nil, "needs_review"} =
                 ApproveOutcome.after_approval(:approved, "request-4", fn _ ->
                   exit({:timeout, {GenServer, :call, [:pool]}})
                 end)

        assert {nil, "needs_review"} =
                 ApproveOutcome.after_approval(:approved, "request-5", fn _ -> throw(:stop) end)
      end)

    assert log =~
             "activation request request-4: approved, but its apply didn't run: exit: {:timeout"

    assert log =~ "activation request request-5: approved, but its apply didn't run: throw: :stop"
  end
end
