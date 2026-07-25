defmodule Cadence.Management.ProvidersTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Management.Providers
  alias Cadence.Management.Providers.ProviderConfiguration

  setup do
    persist_mission_scope("org-management-provider", "mission-management-provider")
  end

  test "owns mission-provider configuration without invoking control operations", %{
    organization: organization,
    mission: mission
  } do
    provider =
      MissionProvider.new(%{
        mission_id: mission.mission_id,
        display_name: "Ground Network Simulator",
        provider_type: :simulator,
        client_key: :simulator_http,
        base_url: "http://127.0.0.1:4101",
        credential_ref: "config://simulator-test",
        environment_ref: "local-demo"
      })

    assert {:ok, persisted} =
             Providers.persist_provider(organization.organization_id, provider)

    assert {:ok, %ProviderConfiguration{} = configuration} =
             Providers.operational_configuration(
               organization.organization_id,
               mission.mission_id,
               persisted.provider_id
             )

    assert configuration.provider == persisted
    assert ProviderConfiguration.matches?(configuration, persisted)
  end
end
