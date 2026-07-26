defmodule Cadence.Applications.StatusPlacementTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.StatusPlacement

  test "accepts the bounded Comms Validation status projection" do
    assert :ok =
             StatusPlacement.validate(%StatusPlacement{
               placement: :comms_validation,
               scope: :spacecraft,
               required?: true
             })
  end

  test "rejects undeclared placements, scopes, and required semantics" do
    valid = %StatusPlacement{placement: :comms_validation, scope: :spacecraft}

    assert {:error, :invalid_application_status_placement} =
             StatusPlacement.validate(%StatusPlacement{valid | placement: :navigation})

    assert {:error, :invalid_application_status_placement} =
             StatusPlacement.validate(%StatusPlacement{valid | scope: :account})

    assert {:error, :invalid_application_status_placement} =
             StatusPlacement.validate(%StatusPlacement{valid | required?: :sometimes})
  end
end
