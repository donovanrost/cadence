defmodule Cadence.Contacts.UplinkLegsTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.{ProviderReservation, UplinkLegs}

  @leg %{
    "routing_rule_id" => "route-uplink",
    "path_template_id" => "template-uplink",
    "path_template_version" => 2
  }

  test "a requested and confirmed leg adds the uplink path and a command window" do
    assert {["template-uplink"], [%{"path_template_id" => "template-uplink", "version" => 2}],
            [:telemetry_downlink, :command_window], %{"uplink" => %{"booked" => true}}} =
             UplinkLegs.scheduled_fields(reservation(@leg, %{"status" => "included"}))
  end

  test "a requested leg the provider rejected or ignored stays downlink-only, with the reason" do
    for confirmed <- [
          %{"status" => "rejected", "status_reason" => "busy"},
          %{"status" => "requested"}
        ] do
      assert {[], [], [:telemetry_downlink],
              %{"uplink" => %{"booked" => false, "reason" => "uplink not booked"}}} =
               UplinkLegs.scheduled_fields(reservation(@leg, confirmed))
    end
  end

  test "a booking without an uplink leg is unchanged" do
    assert {[], [], [:telemetry_downlink], %{}} =
             UplinkLegs.scheduled_fields(reservation(nil, nil))
  end

  test "an operator-attested booking shows its evidence and no command window until the provider confirms uplink (#53)" do
    attested = %{"operator_resolution" => %{"action" => "booked"}}

    unconfirmed = %{"booked" => false, "reason" => "uplink unconfirmed"}

    assert {[], [], [:telemetry_downlink],
            %{"booking_evidence" => "operator_attested", "uplink" => ^unconfirmed}} =
             UplinkLegs.scheduled_fields(%{
               reservation(@leg, nil)
               | metadata: attested,
                 lifecycle_state: :pending
             })

    # qa: a pending booking's snapshot can already say the leg is 'included'; that isn't the
    # provider confirming it.
    assert {[], [], [:telemetry_downlink], %{"uplink" => ^unconfirmed}} =
             UplinkLegs.scheduled_fields(%{
               reservation(@leg, %{"status" => "included"})
               | metadata: attested,
                 lifecycle_state: :pending
             })

    # Once the provider confirms the booking with the leg, the command window follows (#55).
    assert {_ids, _refs, [:telemetry_downlink, :command_window], %{"booking_evidence" => _}} =
             UplinkLegs.scheduled_fields(%{
               reservation(@leg, %{"status" => "included"})
               | metadata: attested,
                 lifecycle_state: :confirmed
             })
  end

  defp reservation(leg, confirmed) do
    %ProviderReservation{
      request_document: if(leg, do: %{"uplink" => leg}, else: %{}),
      provider_confirmed_snapshot_document: if(confirmed, do: %{"uplink" => confirmed}, else: %{})
    }
  end
end
