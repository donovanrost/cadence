defmodule Cadence.Applications.ActionContractLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionContractLedger, ActionRequest}

  test "matches declared, provider, and registry rows exactly" do
    assert :ok = ActionContractLedger.validate()

    ledgers = ActionContractLedger.ledgers()

    assert map_size(ledgers) == 3
    assert length(ledgers.declared) == 41
    assert ledgers.declared == ledgers.provider
    assert ledgers.declared == ledgers.registry
    assert length(Enum.uniq(ledgers.declared)) == 41

    assert ledgers.declared
           |> Enum.frequencies_by(&elem(&1, 0)) == %{
             "mission_catalog" => 13,
             "spacecraft" => 12,
             "telemetry_decom" => 4,
             "comms" => 12
           }
  end

  test "admits only the exact complete request envelope" do
    valid = %ActionRequest{
      application_key: "comms",
      application_version: 1,
      surface_id: "provider_new",
      surface_version: 1,
      action_id: "create_provider"
    }

    assert :ok = ActionContractLedger.admit(valid, Cadence.Applications.Comms.ActionProvider)

    for request <- [
          %{valid | application_key: "spacecraft"},
          %{valid | application_version: 2},
          %{valid | surface_id: "provider_show", surface_version: 2},
          %{valid | action_id: "archive_provider", surface_id: "provider_new"},
          %{valid | surface_id: nil, surface_version: nil}
        ] do
      assert {:error, :unsupported_application_action} =
               ActionContractLedger.admit(request, Cadence.Applications.Comms.ActionProvider)
    end
  end
end
