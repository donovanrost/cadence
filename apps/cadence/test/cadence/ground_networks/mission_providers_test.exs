defmodule Cadence.GroundNetworks.MissionProvidersTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{CredentialResolver, MissionProvider, ProviderError}
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope("org-provider-test", "mission-provider-test")

    %{organization: organization, mission: mission}
  end

  describe "mission provider persistence" do
    test "persists, versions, lists, scopes, and archives setup", %{
      organization: organization,
      mission: mission
    } do
      provider = provider_fixture(mission.mission_id)

      assert {:ok, persisted} =
               GroundNetworks.persist_provider(organization.organization_id, provider)

      assert persisted.organization_id == organization.organization_id
      assert persisted.version == 1
      assert persisted.credential_ref == "config://simulator-test"
      refute inspect(persisted) =~ "super-secret-token"

      assert [listed] =
               GroundNetworks.list_providers(
                 organization.organization_id,
                 mission.mission_id
               )

      assert listed.provider_id == provider.provider_id

      assert {:error, :mission_provider_not_found} =
               GroundNetworks.fetch_provider(
                 "another-org",
                 mission.mission_id,
                 provider.provider_id
               )

      assert {:ok, version_two} =
               GroundNetworks.version_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id,
                 %{
                   display_name: "Simulator Staging",
                   environment_ref: "staging"
                 }
               )

      assert version_two.version == 2
      assert version_two.display_name == "Simulator Staging"
      assert version_two.capabilities_document == %{}
      assert version_two.inventory_sync_document == %{}

      assert {:ok, version_one} =
               GroundNetworks.fetch_provider_version(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id,
                 1
               )

      assert version_one.display_name == "Ground Network Simulator"

      assert [^version_two] =
               GroundNetworks.list_providers(
                 organization.organization_id,
                 mission.mission_id
               )

      assert {:ok, archived} =
               GroundNetworks.archive_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id
               )

      assert archived.version == 3
      assert archived.lifecycle_state == :archived

      assert GroundNetworks.list_providers(
               organization.organization_id,
               mission.mission_id
             ) == []

      assert {:error, :mission_provider_not_found} =
               GroundNetworks.fetch_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id
               )
    end

    test "rejects invalid base URLs and unsupported provider types", %{
      organization: organization,
      mission: mission
    } do
      invalid_url = provider_fixture(mission.mission_id, base_url: "tcp://127.0.0.1:4101")

      assert {:error, :invalid_provider_base_url} =
               GroundNetworks.persist_provider(organization.organization_id, invalid_url)

      provider = provider_fixture(mission.mission_id)

      assert {:ok, persisted} =
               GroundNetworks.persist_provider(organization.organization_id, provider)

      assert {:error, {:invalid_mission_provider, message}} =
               GroundNetworks.version_provider(
                 organization.organization_id,
                 mission.mission_id,
                 persisted.provider_id,
                 %{provider_type: "unknown"}
               )

      assert message =~ "unsupported provider_type"
    end
  end

  describe "validation and inventory synchronization" do
    test "validates capabilities and stores bounded provider-owned inventory without creating spacecraft",
         %{organization: organization, mission: mission} do
      provider = persist_provider!(organization.organization_id, mission.mission_id)
      checked_at = ~U[2026-07-14 12:00:00.000000Z]

      assert {:ok, validated} =
               GroundNetworks.validate_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id,
                 client: FakeProviderClient,
                 credential_resolver: &test_credential_resolver/1,
                 now: checked_at
               )

      assert validated.version == 1
      assert validated.last_validated_at == checked_at
      assert get_in(validated.metadata, ["control_plane", "status"]) == "healthy"
      assert get_in(validated.capabilities_document, ["operations", "inventory_discovery"])

      inventory =
        Enum.map(1..501, fn index ->
          %{"id" => "SC-#{index}", "display_name" => "Provider craft #{index}"}
        end)

      assert Cadence.list_spacecraft(organization.organization_id, mission.mission_id) == []

      assert {:ok, synced} =
               GroundNetworks.sync_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id,
                 client: FakeProviderClient,
                 credential_resolver: &test_credential_resolver/1,
                 spacecraft_response: {:ok, inventory},
                 ground_stations_response:
                   {:ok, [%{"id" => "station-alpha", "name" => "Station Alpha"}]},
                 now: checked_at
               )

      assert synced.version == 1
      assert synced.last_synced_at == checked_at
      assert get_in(synced.metadata, ["sync", "status"]) == "healthy"
      assert get_in(synced.inventory_sync_document, ["spacecraft", "total_count"]) == 501
      assert get_in(synced.inventory_sync_document, ["spacecraft", "cached_count"]) == 500
      assert get_in(synced.inventory_sync_document, ["spacecraft", "truncated"])
      assert length(get_in(synced.inventory_sync_document, ["service_profiles", "items"])) == 1
      assert length(get_in(synced.inventory_sync_document, ["delivery_profiles", "items"])) == 1
      assert Cadence.list_spacecraft(organization.organization_id, mission.mission_id) == []

      assert [_single_version] =
               GroundNetworks.list_provider_versions(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id
               )

      assert {:ok, context} =
               GroundNetworks.provider_context(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id
               )

      assert context.provider_ref == provider.provider_id
      assert context.client_key == "simulator_http"
      assert context.capabilities.operations.inventory_discovery
    end

    test "records sanitized control-plane failures", %{
      organization: organization,
      mission: mission
    } do
      provider = persist_provider!(organization.organization_id, mission.mission_id)

      error =
        ProviderError.from_response(401, %{
          "error" => %{"code" => "authentication_failed", "detail" => "token rejected"}
        })

      assert {:error, ^error} =
               GroundNetworks.validate_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id,
                 client: FakeProviderClient,
                 credential_resolver: &test_credential_resolver/1,
                 validate_response: {:error, error}
               )

      assert {:ok, failed} =
               GroundNetworks.fetch_provider(
                 organization.organization_id,
                 mission.mission_id,
                 provider.provider_id
               )

      assert get_in(failed.metadata, ["control_plane", "status"]) == "failed"
      assert get_in(failed.metadata, ["control_plane", "error", "detail"]) == "token rejected"
      refute inspect(failed.metadata) =~ "super-secret-token"
    end
  end

  describe "credential references" do
    test "resolves configured and environment-backed secrets without accepting literals" do
      previous_credentials = Application.get_env(:cadence, :ground_network_credentials)
      previous_environment = System.get_env("CADENCE_PROVIDER_TEST_TOKEN")

      on_exit(fn ->
        restore_application_env(:cadence, :ground_network_credentials, previous_credentials)
        restore_system_env("CADENCE_PROVIDER_TEST_TOKEN", previous_environment)
      end)

      Application.put_env(:cadence, :ground_network_credentials, %{"simulator" => "configured"})
      System.put_env("CADENCE_PROVIDER_TEST_TOKEN", "environment")

      assert CredentialResolver.resolve("config://simulator") == {:ok, "configured"}

      assert CredentialResolver.resolve("env://CADENCE_PROVIDER_TEST_TOKEN") ==
               {:ok, "environment"}

      assert {:error, {:unsupported_credential_reference, "literal-secret"}} =
               CredentialResolver.resolve("literal-secret")
    end
  end

  defp persist_provider!(organization_id, mission_id) do
    provider = provider_fixture(mission_id)
    {:ok, persisted} = GroundNetworks.persist_provider(organization_id, provider)
    persisted
  end

  defp provider_fixture(mission_id, opts \\ []) do
    MissionProvider.new(%{
      mission_id: mission_id,
      display_name: Keyword.get(opts, :display_name, "Ground Network Simulator"),
      provider_type: :simulator,
      client_key: :simulator_http,
      base_url: Keyword.get(opts, :base_url, "http://127.0.0.1:4101"),
      credential_ref: "config://simulator-test",
      environment_ref: "local-demo"
    })
  end

  defp test_credential_resolver("config://simulator-test"),
    do: {:ok, "super-secret-token"}

  defp test_credential_resolver(reference),
    do: {:error, {:credential_reference_not_found, reference}}

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
