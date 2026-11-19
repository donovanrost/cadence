defmodule Cadence.Dev.ApogeeQaMission.Provider do
  @moduledoc """
  The QA mission's provider, direct transport and route (#231), split from
  dev/apogee_qa_mission.exs. Store and context functions only; the provider writes act as the
  environment's administrator, as the Earendil seed's do (no approval or decision).
  """

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport, TransportStore}
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias Cadence.Management.Transports

  @organization_id F.organization_id()
  @mission_id "mission-qa-23565"
  @account_id "account-qa-23565"
  @credential_ref "credential-qa-23565"
  @grant_id "grant-qa-23565"
  @provider_id "provider-qa-23565"
  @transport_id "transport-qa-23565-direct"
  # The simulator accepts one provider token, so the QA credential names Earendil's variable
  # (devops, #199). The value is read only to validate and sync in this process; never printed.
  @token_key "EARENDIL_DEMO_PROVIDER_TOKEN"
  @metadata %{"fixture" => "apogee-qa-mission-v1"}

  def mission_id, do: @mission_id
  def metadata, do: @metadata
  def token_key, do: @token_key

  @doc "The QA provider on the dev simulator: credential (by name), account, grant, mission provider."
  def ensure_provider(scope, offline?) do
    ensure_record(ProviderCredentials.fetch(@organization_id, @account_id, @credential_ref), fn ->
      ProviderCredentials.create(scope, @account_id, %{
        provider_credential_ref: @credential_ref,
        backend_type: :env,
        backend_key: @token_key,
        metadata: @metadata
      })
    end)

    version =
      case ProviderAccounts.fetch(scope, @account_id) do
        {:ok, _account, version} ->
          version

        {:error, :provider_account_not_found} ->
          {:ok, _account, version} =
            ProviderAccounts.create(scope, %{
              provider_account_id: @account_id,
              display_name: "QA simulator provider",
              provider_type: :simulator,
              base_url: F.provider_url(),
              region: "local",
              environment_ref: F.run_id(),
              credential_ref: @credential_ref,
              # Earendil's account already polls the simulator's events; a second poller on the
              # same environment would ingest them twice (qa's L12/L13 recipe).
              event_ingestion_mode: :disabled,
              metadata: @metadata
            })

          version
      end

    unless offline?, do: {:ok, _account} = ProviderAccounts.validate(scope, @account_id)

    grant =
      ensure_record(
        ProviderAccountGrants.fetch_active_for_system(@organization_id, @grant_id),
        fn ->
          ProviderAccountGrants.grant(scope, @mission_id, @account_id, %{
            provider_account_grant_id: @grant_id,
            metadata: @metadata
          })
        end
      )

    provider =
      ensure_record(
        GroundNetworks.fetch_provider(@organization_id, @mission_id, @provider_id),
        fn ->
          GroundNetworks.persist_provider(
            scope,
            MissionProvider.new(%{
              provider_id: @provider_id,
              mission_id: @mission_id,
              display_name: "QA simulator provider",
              provider_account_id: @account_id,
              provider_account_version: version.version,
              provider_account_grant_id: grant.provider_account_grant_id,
              provider_account_grant_version: grant.version,
              provider_type: version.provider_type,
              client_key: version.client_key,
              base_url: version.base_url,
              credential_ref: version.credential_ref,
              environment_ref: version.environment_ref,
              metadata: @metadata
            })
          )
        end
      )

    if offline? do
      provider
    else
      {:ok, _provider} = GroundNetworks.validate_provider(scope, @mission_id, @provider_id)
      {:ok, provider} = GroundNetworks.sync_provider(scope, @mission_id, @provider_id)
      provider
    end
  end

  @doc "A direct TCP-client transport (qa's in-use refusal check needs one with a route to it)."
  def ensure_direct_transport do
    ensure_record(
      TransportStore.fetch_transport(@organization_id, @mission_id, @transport_id),
      fn ->
        Transports.persist_transport(
          @organization_id,
          Transport.new(%{
            transport_id: @transport_id,
            mission_id: @mission_id,
            display_name: "QA direct TCP client",
            origin: :direct,
            configuration: %{
              "mode" => "connect",
              "direction_capability" => "inbound",
              "host" => "127.0.0.1",
              "port" => 47_991,
              "framing_mode" => "fixed_size",
              "frame_size" => F.frame_size(),
              "tls_enabled" => false
            },
            metadata: @metadata
          })
        )
      end
    )
  end

  @doc "One downlink routing rule from the craft to the transport."
  def ensure_route(craft, transport) do
    id = "route-#{craft.spacecraft_id}-direct"

    ensure_record(RoutingRuleStore.fetch_routing_rule(@organization_id, @mission_id, id), fn ->
      RoutingRuleStore.create_routing_rule(
        @organization_id,
        RoutingRule.new(%{
          routing_rule_id: id,
          mission_id: @mission_id,
          spacecraft_id: craft.spacecraft_id,
          display_name: "QA direct downlink",
          purpose_label: "TT&C downlink",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :primary,
          metadata: @metadata
        })
      )
    end)
  end

  defp ensure_record({:ok, record}, _create), do: record

  defp ensure_record({:error, reason}, create)
       when reason in [
              :provider_credential_not_found,
              :provider_account_grant_not_found,
              :mission_provider_not_found,
              :provider_not_found,
              :transport_not_found,
              :routing_rule_not_found
            ] do
    {:ok, record} = create.()
    record
  end
end
