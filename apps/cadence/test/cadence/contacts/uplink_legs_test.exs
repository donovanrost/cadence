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

  defp reservation(leg, confirmed) do
    %ProviderReservation{
      request_document: if(leg, do: %{"uplink" => leg}, else: %{}),
      provider_confirmed_snapshot_document: if(confirmed, do: %{"uplink" => confirmed}, else: %{})
    }
  end
end
