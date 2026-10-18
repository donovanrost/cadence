defmodule Cadence.ContactPlanning.OpportunityCapabilityTest do
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.OpportunityCapability

  @payload %{
    "organization_id" => "org-capability-test",
    "mission_id" => "mission-capability-test",
    "spacecraft_id" => "spacecraft-capability-test",
    "route_key" => "route-1",
    "route" => %{"provider" => "provider-1"},
    "opportunity" => %{"id" => "opportunity-1"}
  }

  test "a capability survives the signing process exiting" do
    parent = self()

    {signer, monitor} =
      spawn_monitor(fn ->
        send(parent, {:capability, OpportunityCapability.sign(@payload)})
      end)

    assert_receive {:capability, token}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^signer, :normal}, 5_000
    assert {:ok, verified} = OpportunityCapability.verify(token)
    assert verified["mission_id"] == @payload["mission_id"]
  end

  test "rejects a tampered capability before using its payload" do
    token = OpportunityCapability.sign(@payload)
    token_size = byte_size(token)
    prefix = binary_part(token, 0, token_size - 1)
    last = :binary.last(token)
    tampered = prefix <> <<Bitwise.bxor(last, 1)>>

    assert {:error, :invalid_opportunity_capability} = OpportunityCapability.verify(tampered)
  end

  test "rejects an expired capability" do
    token = OpportunityCapability.sign(@payload)

    Process.sleep(1_100)

    assert {:error, :invalid_opportunity_capability} =
             OpportunityCapability.verify(token, max_age: 0)
  end
end
