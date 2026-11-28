defmodule Cadence.Applications.RegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ApplicationDefinition,
    Registry,
    ResourceClaimDefinition,
    ResourceContract
  }

  test "installation policy is explicit, scoped, and defaults to optional" do
    assert {:ok, optional} = Registry.fetch_available("telemetry_decom")
    assert optional.installation_policy == :optional
    refute Registry.platform?("telemetry_decom", :spacecraft)
    refute Registry.platform?("unknown", :mission)

    for key <- ["ops_console"] do
      assert Registry.platform?(key, :mission)
    end

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%{optional | installation_policy: :automatic})
  end

  test "resolves the latest registered application at the spacecraft" do
    assert {:ok, %ApplicationDefinition{} = definition} =
             Registry.fetch("telemetry_decom")

    assert definition.version == 1
    assert definition.installable_scopes == [:spacecraft]
    assert definition.status_query_id == "cadence.telemetry_decom.status"

    assert %ResourceContract{
             claims: [
               %ResourceClaimDefinition{
                 claim_type: :packet_apid,
                 scope: :spacecraft,
                 mode: :shared
               }
             ]
           } = definition.resource_contract
  end

  test "distinguishes unknown applications, unsupported versions, and unavailable definitions" do
    assert {:error, :unknown_application} = Registry.fetch("not_registered")

    assert {:error, :unsupported_application_version} =
             Registry.fetch("telemetry_decom", 99)

    assert {:ok, decom} = Registry.fetch_available("telemetry_decom")
    assert decom.availability == :available
    assert decom.installable_scopes == [:spacecraft]

    assert {:ok, cfdp} = Registry.fetch("cfdp")
    assert cfdp.availability == :roadmap
    assert {:error, :application_unavailable} = Registry.fetch_available("cfdp")
  end

  test "available definitions are safe choices for a spacecraft profile" do
    assert Enum.all?(Registry.all(), &(ApplicationDefinition.validate(&1) == :ok))

    assert Enum.map(Registry.available_for_scope(:spacecraft), & &1.application_key) == [
             "telemetry_decom"
           ]

    assert Enum.map(Registry.available_for_scope(:mission), & &1.application_key) == [
             "ops_console"
           ]

    assert Enum.sort(Registry.known_keys()) == [
             "cfdp",
             "ops_console",
             "telemetry_decom"
           ]
  end
end
