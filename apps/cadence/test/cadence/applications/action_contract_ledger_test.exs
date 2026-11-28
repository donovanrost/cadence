defmodule Cadence.Applications.ActionContractLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionContractLedger, ActionRequest}

  test "matches declared, provider, and registry rows exactly" do
    assert :ok = ActionContractLedger.validate()

    ledgers = ActionContractLedger.ledgers()

    assert map_size(ledgers) == 3
    assert length(ledgers.declared) == 4
    assert ledgers.declared == ledgers.provider
    assert ledgers.declared == ledgers.registry
    assert length(Enum.uniq(ledgers.declared)) == 4

    assert ledgers.declared
           |> Enum.frequencies_by(&elem(&1, 0)) == %{
             "telemetry_decom" => 4
           }
  end

  test "admits only the exact complete request envelope" do
    valid = %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      surface_id: "packet_bindings",
      surface_version: 1,
      action_id: "save_packet_bindings"
    }

    assert :ok =
             ActionContractLedger.admit(valid, Cadence.Applications.TelemetryDecom.ActionProvider)

    for request <- [
          %{valid | application_key: "ops_console"},
          %{valid | application_version: 2},
          %{valid | surface_version: 2},
          %{valid | action_id: "unknown_action"},
          %{valid | surface_id: "unknown_surface"},
          %{valid | surface_id: nil, surface_version: nil}
        ] do
      assert {:error, :unsupported_application_action} =
               ActionContractLedger.admit(
                 request,
                 Cadence.Applications.TelemetryDecom.ActionProvider
               )
    end
  end
end
