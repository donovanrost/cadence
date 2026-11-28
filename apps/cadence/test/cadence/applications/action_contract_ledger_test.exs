defmodule Cadence.Applications.ActionContractLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionContractLedger, ActionRequest}

  test "matches declared, provider, and registry rows exactly" do
    assert :ok = ActionContractLedger.validate()

    ledgers = ActionContractLedger.ledgers()

    assert map_size(ledgers) == 3
    assert ledgers.declared == []
    assert ledgers.declared == ledgers.provider
    assert ledgers.declared == ledgers.registry
  end

  test "admits no request once TelemetryDecom is headless (#669)" do
    former = %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      surface_id: "packet_bindings",
      surface_version: 1,
      action_id: "save_packet_bindings"
    }

    for request <- [
          former,
          %{former | surface_id: "manage", action_id: "save_configuration"},
          %{former | application_key: "ops_console"},
          %{former | surface_id: nil, surface_version: nil}
        ] do
      assert {:error, :unsupported_application_action} = ActionContractLedger.admit(request)
    end
  end
end
