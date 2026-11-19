defmodule Cadence.Contacts.ReservationChangeTest do
  @moduledoc """
  qa 11-14: the reconciler announced :contacts_changed for every poll (~38/s on dev). A provider
  poll now announces only when a field readers see changed (domain's rule).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.ProviderReservations
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.ProviderChangeFixtures

  setup do
    context = ProviderChangeFixtures.setup_contact()

    :ok =
      ScopedReadUpdates.subscribe(:contacts_changed, context.organization_id, context.mission_id)

    %{context: context}
  end

  defp announced(context),
    do: {:contacts_changed, context.organization_id, context.mission_id}

  test "a poll that changes nothing visible announces nothing; a status change announces once",
       %{context: context} do
    # The provider answers exactly what it answered before (attempt_count still bumps).
    assert {:ok, _} = ProviderChangeFixtures.advance(context, 1, %{})
    refute_receive {:contacts_changed, _, _}, 200

    assert {:ok, %{delivery_state: delivery}} =
             ProviderChangeFixtures.advance(context, 1, %{"delivery_state" => "flowing"})

    assert to_string(delivery) == "flowing"
    message = announced(context)
    assert_receive ^message, 1_000
    refute_receive {:contacts_changed, _, _}, 200
  end

  test "a repeated provider error with a fresh recorded_at announces only the first time",
       %{context: context} do
    error = fn ->
      %{
        "outcome" => "transient",
        "reason" => "timeout",
        "recorded_at" => DateTime.to_iso8601(DateTime.utc_now())
      }
    end

    id = context.reservation.provider_reservation_id

    assert {:ok, _} =
             ProviderReservations.record_provider_error(
               context.organization_id,
               context.mission_id,
               id,
               error.()
             )

    message = announced(context)
    assert_receive ^message, 1_000

    assert {:ok, _} =
             ProviderReservations.record_provider_error(
               context.organization_id,
               context.mission_id,
               id,
               error.()
             )

    refute_receive {:contacts_changed, _, _}, 200
  end
end
