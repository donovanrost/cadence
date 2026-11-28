defmodule Cadence.Applications.ActionContractLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionContractLedger, ActionRequest}

  test "matches declared, provider, and registry rows exactly" do
    assert :ok = ActionContractLedger.validate()

    ledgers = ActionContractLedger.ledgers()

    assert map_size(ledgers) == 3
    assert length(ledgers.declared) == 6
    assert ledgers.declared == ledgers.provider
    assert ledgers.declared == ledgers.registry
    assert length(Enum.uniq(ledgers.declared)) == 6

    assert ledgers.declared
           |> Enum.frequencies_by(&elem(&1, 0)) == %{
             "telemetry_decom" => 4,
             "comms" => 2
           }
  end

  test "admits only the exact complete request envelope" do
    valid = %ActionRequest{
      application_key: "comms",
      application_version: 1,
      surface_id: "routing_new",
      surface_version: 1,
      action_id: "save"
    }

    assert :ok = ActionContractLedger.admit(valid, Cadence.Applications.Comms.ActionProvider)

    for request <- [
          %{valid | application_key: "telemetry_decom"},
          %{valid | application_version: 2},
          %{valid | surface_id: "transport", surface_version: 2},
          %{valid | action_id: "archive_provider", surface_id: "routing_new"},
          # Host-action sweep batch 1: the transport and ground station forms bind nothing.
          %{valid | surface_id: "transport_new"},
          %{valid | surface_id: "ground_station_edit"},
          %{valid | surface_id: nil, surface_version: nil}
        ] do
      assert {:error, :unsupported_application_action} =
               ActionContractLedger.admit(request, Cadence.Applications.Comms.ActionProvider)
    end
  end
end
