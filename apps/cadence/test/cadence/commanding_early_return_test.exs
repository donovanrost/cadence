defmodule Cadence.CommandingEarlyReturnTest do
  use Cadence.UnitCase, async: true

  test "returns empty verifier evaluations before opening repository transactions" do
    assert {:ok, []} = Cadence.Commanding.evaluate_command_verifiers([])
    assert {:ok, []} = Cadence.Commanding.evaluate_transport_command_verifiers([], [])
  end
end
