defmodule Cadence.CCSDS.CFDP.FaultPolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.FaultPolicy
  alias Cadence.CCSDS.CFDP.TLV.FaultHandlerOverride

  test "uses per-transaction overrides before configured MIB defaults" do
    assert {:ok, policy} =
             FaultPolicy.new(
               default_handler: :cancel,
               handlers: %{file_checksum_failure: :suspend}
             )

    assert FaultPolicy.handler(policy, :file_checksum_failure) == :suspend
    assert FaultPolicy.handler(policy, :nak_limit_reached) == :cancel

    override = %FaultHandlerOverride{condition: :file_checksum_failure, handler: :ignore}
    assert FaultPolicy.handler(policy, :file_checksum_failure, [override]) == :ignore
  end

  test "rejects non-fault conditions and reserved handlers" do
    assert {:error, {:invalid_fault_condition, :no_error}} =
             FaultPolicy.new(handlers: %{no_error: :ignore})

    assert {:error, {:invalid_fault_handler, :default_handler, :retry}} =
             FaultPolicy.new(default_handler: :retry)
  end
end
