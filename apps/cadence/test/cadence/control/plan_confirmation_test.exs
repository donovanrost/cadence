defmodule Cadence.Control.PlanConfirmationTest do
  @moduledoc "Plan detail's execution summary (lead: K1/K2 headers, bookingStopped)."
  use ExUnit.Case, async: true

  alias Cadence.Control.PlanConfirmation

  defp item(state, reservation \\ "provider_reservation_x"),
    do: %{lifecycle_state: state, provider_reservation_id: reservation}

  test "nothing to count before execution" do
    assert PlanConfirmation.execution([]) == nil
  end

  test "counts by how far each booking got; requested = sent + never_sent" do
    items = [
      item(:reserved),
      item(:reserved),
      item(:uncertain),
      item(:rejected),
      # The provider failed or lost it after it was placed.
      item(:failed),
      # Failed before the provider call (expired snapshot): never sent.
      item(:failed, nil),
      item(:pending, nil),
      item(:requesting, nil)
    ]

    assert PlanConfirmation.execution(items) == %{
             requested: 8,
             sent: 5,
             confirmed: 2,
             uncertain: 1,
             rejected: 1,
             failed: 1,
             never_sent: 3
           }
  end
end
