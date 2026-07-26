defmodule Cadence.Applications.LifecycleContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ActionConfirmation,
    LifecycleActionDefinition,
    LifecycleActions,
    LifecycleContract
  }

  test "publishes valid host-owned definitions for every standard lifecycle action" do
    assert Enum.all?(LifecycleActions.all(), &(LifecycleActionDefinition.validate(&1) == :ok))

    assert {:ok,
            %LifecycleActionDefinition{
              required_permission: "request_activation",
              execution: :approval_required,
              button_variant: :primary,
              confirmation: %ActionConfirmation{
                tone: :attention,
                confirm_label: "Request mission changes"
              }
            }} = LifecycleActions.fetch("request_activation")

    assert {:error, :unknown_application_lifecycle_action} =
             LifecycleActions.fetch("application_supplied_action")
  end

  test "resolves only standard actions declared by the application contract" do
    contract = %LifecycleContract{actions: ["save_configuration", "request_activation"]}

    assert :ok = LifecycleContract.validate(contract)

    assert {:ok, %LifecycleActionDefinition{action_id: "request_activation"}} =
             LifecycleContract.fetch_action(contract, "request_activation")

    assert {:error, :undeclared_application_action} =
             LifecycleContract.fetch_action(contract, "disable")
  end

  test "rejects duplicate and unknown lifecycle declarations" do
    assert {:error, :invalid_application_lifecycle_contract} =
             LifecycleContract.validate(%LifecycleContract{actions: ["disable", "disable"]})

    assert {:error, :invalid_application_lifecycle_contract} =
             LifecycleContract.validate(%LifecycleContract{actions: ["custom_disable"]})
  end
end
