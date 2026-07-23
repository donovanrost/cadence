defmodule Cadence.Management.ProviderAndManagedResourceContractsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataSource
  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Management.ManagedResources.ManagedResourceRequest
  alias Cadence.Management.Providers.ProviderConfiguration

  test "provider configuration hash ignores operational observations" do
    provider =
      MissionProvider.new(%{
        provider_id: "provider-1",
        organization_id: "organization-1",
        mission_id: "mission-1",
        display_name: "Ground network",
        provider_type: :simulator,
        base_url: "http://provider.example.test",
        credential_ref: "secret://provider-1",
        environment_ref: "test"
      })

    configuration = ProviderConfiguration.new(provider)

    assert ProviderConfiguration.matches?(configuration, %{
             provider
             | last_validated_at: ~U[2026-07-22 12:00:00Z],
               capabilities_document: %{"scheduling" => true}
           })

    refute ProviderConfiguration.matches?(configuration, %{provider | base_url: "http://other"})
  end

  test "managed resource request captures an exact durable action basis" do
    source = %DataSource{
      data_source_id: "source-1",
      organization_id: "organization-1",
      mission_id: "mission-1",
      owner: :customer,
      kind: :byo_tsdb,
      isolation_level: :mission_isolated,
      metadata: %{"tsdb_backend_lifecycle" => %{"status" => "provision_requested"}}
    }

    requested_at = ~U[2026-07-22 12:00:00Z]
    request = ManagedResourceRequest.new(source, :provision, requested_at, "request-1")

    assert request.request_id == "request-1"
    assert request.resource_id == source.data_source_id
    assert request.operation == :provision
    assert is_binary(request.content_sha256)
  end
end
