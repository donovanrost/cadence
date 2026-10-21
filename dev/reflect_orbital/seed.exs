defmodule Cadence.Dev.ReflectOrbital.Seed do
  @moduledoc false
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow}
  alias Cadence.Auth.Scope

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore,
    Transport
  }

  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccounts,
    ProviderAccountGrants,
    ProviderCredentials
  }

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.{Repo, Spacecraft, SpacecraftType}

  @url "http://127.0.0.1:4101"
  @token_key "EARENDIL_DEMO_PROVIDER_TOKEN"

  def run do
    if Mix.env() != :dev, do: raise("The Earendil fixture may only seed the development database")
    Logger.configure(level: :warning)
    System.put_env(@token_key, "earendil-local-provider")
    {:ok, _apps} = Application.ensure_all_started(:cadence)
    email = System.get_env("EARENDIL_DEMO_EMAIL", "admin@example.com")
    {:ok, user} = Cadence.Accounts.fetch_user_by_email(email)

    ensure_simulator()
    deliveries = ensure_deliveries()

    {:ok, scope} = Repo.transaction(fn -> seed_scope(user) end)
    provider = seed_provider(scope)
    transports = seed_sites(provider, deliveries)
    seed_fleet(transports)
    Cadence.Dev.ReflectOrbital.Configuration.prepare(scope)
    verify!()

    IO.puts("""

    Reflect Orbital / Earendil is ready for #{email}.
    500 spacecraft, 20 planes, 10 simulated sites, 38 antennas.
    500 provider mappings and 1,000 primary/backup downlink routes.
    500 saved configurations share demo_spacecraft.yaml: 10 telemetry packets and 27 commands.
    Configuration activation remains an explicit review step in Cadence.
    Simulator environment: #{F.run_id()}
    Fleet: http://localhost:4001/missions/#{F.mission_id()}/spacecraft
    Comms: http://localhost:4001/missions/#{F.mission_id()}/comms/providers
    Sites: http://localhost:4001/missions/#{F.mission_id()}/comms/ground-stations
    Contacts: http://localhost:4001/missions/#{F.mission_id()}/ops/contacts
    Select Reflect Orbital in the organization switcher first.
    All spacecraft, orbits, sites, and telemetry definitions are synthetic.
    """)
  end

  defp seed_scope(user) do
    {:ok, organization} =
      Cadence.Organizations.persist_organization(
        Organization.new(%{
          organization_id: F.organization_id(),
          slug: "reflect-orbital",
          display_name: "Reflect Orbital",
          metadata: F.metadata()
        })
      )

    {:ok, _mission} =
      Cadence.Missions.persist_mission(
        Mission.new(%{
          mission_id: F.mission_id(),
          organization_id: F.organization_id(),
          slug: "earendil",
          display_name: "Earendil",
          metadata:
            Map.merge(F.metadata(), %{
              "description" =>
                "500-spacecraft solar-reflector constellation operations rehearsal",
              "scenario" => "20 planes × 25 spacecraft; synthetic 625 km near-polar LEO",
              "reference" => "https://www.reflectorbital.com/",
              "configuration_notice" =>
                "Illustrative demo assumptions, not Reflect Orbital flight configuration"
            })
        })
      )

    membership =
      case Cadence.Accounts.fetch_user_membership(user.user_id, F.organization_id()) do
        {:ok, membership} ->
          membership

        {:error, :not_found} ->
          membership =
            OrganizationMembership.new(%{
              user_id: user.user_id,
              organization_id: F.organization_id(),
              role: :organization_admin,
              metadata: F.metadata()
            })

          {:ok, _row} = membership |> OrganizationMembershipRow.changeset() |> Repo.insert()
          membership
      end

    Scope.new(%{user: user, organization: organization, organization_membership: membership})
  end

  defp seed_provider(scope) do
    ensure_record(
      ProviderCredentials.fetch(F.organization_id(), F.account_id(), F.credential_ref()),
      fn ->
        ProviderCredentials.create(scope, F.account_id(), %{
          provider_credential_ref: F.credential_ref(),
          backend_type: :env,
          backend_key: @token_key,
          metadata: F.metadata()
        })
      end
    )

    version =
      case ProviderAccounts.fetch(scope, F.account_id()) do
        {:ok, _account, version} ->
          version

        {:error, :provider_account_not_found} ->
          {:ok, _account, version} =
            ProviderAccounts.create(scope, %{
              provider_account_id: F.account_id(),
              display_name: "Earendil Demo Ground Network",
              provider_type: :simulator,
              base_url: @url,
              region: "local",
              environment_ref: F.run_id(),
              credential_ref: F.credential_ref(),
              event_ingestion_mode: :polling,
              metadata: F.metadata()
            })

          version
      end

    true = version.environment_ref == F.run_id() and version.base_url == @url
    {:ok, _account} = ProviderAccounts.validate(scope, F.account_id())

    grant =
      ensure_record(
        ProviderAccountGrants.fetch_active_for_system(F.organization_id(), F.grant_id()),
        fn ->
          ProviderAccountGrants.grant(scope, F.mission_id(), F.account_id(), %{
            provider_account_grant_id: F.grant_id(),
            metadata: F.metadata()
          })
        end
      )

    ensure_record(
      GroundNetworks.fetch_provider(F.organization_id(), F.mission_id(), F.provider_id()),
      fn ->
        GroundNetworks.persist_provider(
          scope,
          MissionProvider.new(%{
            provider_id: F.provider_id(),
            mission_id: F.mission_id(),
            display_name: "Earendil Demo Ground Network",
            provider_account_id: F.account_id(),
            provider_account_version: version.version,
            provider_account_grant_id: grant.provider_account_grant_id,
            provider_account_grant_version: grant.version,
            provider_type: version.provider_type,
            client_key: version.client_key,
            base_url: version.base_url,
            credential_ref: version.credential_ref,
            environment_ref: version.environment_ref,
            metadata: F.metadata()
          })
        )
      end
    )

    {:ok, _provider} = GroundNetworks.validate_provider(scope, F.mission_id(), F.provider_id())
    {:ok, provider} = GroundNetworks.sync_provider(scope, F.mission_id(), F.provider_id())
    provider
  end

  defp seed_sites(provider, deliveries) do
    Enum.map(F.sites(), fn site ->
      {:ok, _station} =
        GroundStationStore.persist_ground_station(
          F.organization_id(),
          GroundStation.new(%{
            ground_station_id: site["id"],
            mission_id: F.mission_id(),
            display_name: site["name"],
            provider: provider.display_name,
            region: site["region"],
            metadata:
              Map.merge(
                F.metadata(),
                Map.merge(site, %{
                  "provider_ground_station_ref" => site["id"],
                  "bands" => ["S"],
                  "minimum_elevation_deg" => 10,
                  "antenna_diameter_m" => 5.4
                })
              )
          })
        )

      delivery = Map.fetch!(deliveries, site["id"])

      transport =
        ensure_record(
          Cadence.Comms.TransportStore.fetch_transport(
            F.organization_id(),
            F.mission_id(),
            "transport-#{site["id"]}"
          ),
          fn ->
            Cadence.Management.Transports.persist_transport(
              F.organization_id(),
              Transport.new(%{
                transport_id: "transport-#{site["id"]}",
                mission_id: F.mission_id(),
                display_name: "#{site["name"]} S-band downlink",
                origin: :provider_managed,
                mission_provider_id: provider.provider_id,
                mission_provider_version: provider.version,
                service_profile_ref: %{"id" => F.service_id(), "version" => 1},
                delivery_profile_ref: %{"id" => delivery["id"], "version" => delivery["version"]},
                metadata: Map.merge(F.metadata(), %{"ground_station_id" => site["id"]})
              })
            )
          end
        )

      {site, transport}
    end)
  end

  defp seed_fleet(transports) do
    {:ok, _profile} =
      Cadence.SpacecraftTypeStore.persist_spacecraft_type(
        F.organization_id(),
        SpacecraftType.new(%{
          spacecraft_type_id: F.profile_id(),
          mission_id: F.mission_id(),
          display_name: "Earendil Block 1 — Demo",
          downlink_protocol: :tm,
          uplink_protocol: :tc,
          frame_parameters: %{"frame_size" => F.frame_size(), "ocf_length" => 0, "fecf" => false},
          applications: %{"telemetry_decom" => %{}},
          metadata: F.metadata()
        })
      )

    F.spacecraft()
    |> Enum.with_index()
    |> Enum.each(fn {attrs, index} ->
      {:ok, _result} =
        Repo.transaction(fn ->
          {:ok, craft} =
            Cadence.SpacecraftStore.persist_spacecraft(F.organization_id(), Spacecraft.new(attrs))

          {:ok, _source} =
            Cadence.SourceEndpoints.persist_source_endpoint(
              F.organization_id(),
              SourceEndpoint.new(%{
                source_endpoint_id: "source-#{craft.spacecraft_id}",
                mission_id: F.mission_id(),
                spacecraft_id: craft.spacecraft_id,
                source_ref: craft.display_name,
                display_name: "#{craft.display_name} TT&C",
                metadata: F.metadata()
              })
            )

          seed_route(craft, Enum.at(transports, rem(index, 10)), :primary)
          seed_route(craft, Enum.at(transports, rem(index + 5, 10)), :candidate)
        end)
    end)
  end

  defp seed_route(craft, {site, transport}, role) do
    id = "route-#{craft.spacecraft_id}-#{role}"

    ensure_record(
      RoutingRuleStore.fetch_routing_rule(F.organization_id(), F.mission_id(), id),
      fn ->
        RoutingRuleStore.create_routing_rule(
          F.organization_id(),
          RoutingRule.new(%{
            routing_rule_id: id,
            mission_id: F.mission_id(),
            spacecraft_id: craft.spacecraft_id,
            display_name: "#{site["name"]} — #{role}",
            purpose_label: "TT&C downlink",
            direction: :inbound,
            transport_id: transport.transport_id,
            transport_version: transport.version,
            role: role,
            metadata: Map.merge(F.metadata(), %{"ground_station_id" => site["id"]})
          })
        )
      end
    )
  end

  defp verify! do
    fleet = Cadence.SpacecraftStore.list_spacecraft(F.organization_id(), F.mission_id())
    500 = length(fleet)
    500 = fleet |> Enum.map(& &1.scid) |> Enum.uniq() |> length()

    Enum.each(fleet, fn craft ->
      {:ok, %{routes: routes, findings: []}} =
        Cadence.Contacts.ProviderScheduling.list_ready_downlink_routes(
          F.organization_id(),
          F.mission_id(),
          craft.spacecraft_id
        )

      2 = length(routes)
    end)

    IO.puts("Verified: all 500 spacecraft have unique SCIDs and two ready provider routes.")
  end

  defp ensure_simulator do
    case request(:get, "/admin/v1/runs/#{F.run_id()}", :admin) do
      {:ok, %{"state" => "running"}} ->
        :ok

      {:ok, %{"state" => "paused"}} ->
        request!(:post, "/admin/v1/runs/#{F.run_id()}/resume", :admin, %{})

      {:error, 404} ->
        case request(:get, "/admin/v1/scenarios/#{F.scenario_id()}", :admin) do
          {:ok, _scenario} -> :ok
          {:error, 404} -> request!(:post, "/admin/v1/scenarios", :admin, F.scenario())
        end

        request!(:post, "/admin/v1/scenarios/#{F.scenario_id()}/runs", :admin, %{
          "id" => F.run_id(),
          "seed" => 20_261_019,
          "speed" => 1.0
        })

      other ->
        raise "Cannot reuse simulator run: #{inspect(other)}"
    end
  end

  defp ensure_deliveries do
    existing = request!(:get, "/provider/v1/delivery-profiles", :provider)

    Map.new(F.sites(), fn site ->
      delivery =
        Enum.find(existing, &(&1["client_reference"] == site["id"])) ||
          request!(:post, "/provider/v1/delivery-profiles", :provider, F.delivery(site))

      {site["id"], delivery}
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

  defp request!(method, path, namespace, body \\ nil) do
    {:ok, data} = request(method, path, namespace, body)
    data
  end

  defp request(method, path, namespace, body \\ nil) do
    token = if namespace == :admin, do: "earendil-local-admin", else: "earendil-local-provider"
    headers = [{"authorization", "Bearer #{token}"}, {"x-simulator-environment-ref", F.run_id()}]

    opts = [
      method: method,
      url: @url <> path,
      headers: headers,
      retry: false,
      receive_timeout: 30_000
    ]

    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    case Req.request(opts) do
      {:ok, %{status: status, body: %{"data" => data}}} when status in 200..299 ->
        {:ok, data}

      {:ok, %{status: 404}} ->
        {:error, 404}

      {:ok, response} ->
        raise "Simulator #{method} #{path}: HTTP #{response.status} #{inspect(response.body)}"

      {:error, _reason} ->
        raise "Simulator unavailable at #{@url}; start dev/reflect_orbital_simulator.exs first"
    end
  end
end
