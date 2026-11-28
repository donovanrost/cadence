defmodule Cadence.Dev.ReflectOrbital.Seed do
  @moduledoc false
  alias Cadence.Auth.Scope

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    Transport,
    TransportStore,
    UplinkResolution
  }

  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Dev.ReflectOrbital.Approver
  alias Cadence.Dev.ReflectOrbital.Configuration
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.Dev.ReflectOrbital.Planning
  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias Cadence.Management.Transports
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.{Repo, Spacecraft, SpacecraftType}
  alias EarendilRouteChanges, as: RouteChanges

  @token_key "EARENDIL_DEMO_PROVIDER_TOKEN"
  @fleet_chunk 100

  def run do
    unless F.chaos_lab?() or (Code.ensure_loaded?(Mix) and Mix.env() == :dev),
      do: raise("The Earendil fixture requires development mode or the isolated chaos lab")

    Logger.configure(level: :warning)
    provider_token!()
    {:ok, _apps} = Application.ensure_all_started(:cadence)
    email = System.get_env("EARENDIL_DEMO_EMAIL", "admin@example.com")
    {:ok, user} = Cadence.Accounts.fetch_user_by_email(email)

    ensure_simulator()
    deliveries = ensure_deliveries()
    uplink_deliveries = ensure_uplink_deliveries()

    {:ok, scope} = Repo.transaction(fn -> seed_scope(user) end)
    provider = seed_provider(scope)
    transports = seed_sites(provider, deliveries)
    uplinks = seed_uplinks(provider, uplink_deliveries)
    {fleet_ms, :ok} = :timer.tc(&seed_fleet/0, :millisecond)
    approver = Approver.scope(scope.user)

    :applied =
      transports
      |> seed_routes(uplinks)
      |> Approver.approve_route_changes(approver, F.mission_id())

    Configuration.prepare(scope)
    approved = Approver.approve_candidates(approver)
    Planning.prepare(scope)
    verify!()
    server_url = "http://127.0.0.1:#{System.get_env("PORT", "4001")}"

    n = F.fleet_size()
    antennas = F.sites() |> Enum.map(& &1["antenna_count"]) |> Enum.sum()

    IO.puts("""

    Reflect Orbital / Earendil setup completed for #{email}.
    #{n} spacecraft, #{F.plane_count()} planes, #{F.site_count()} simulated sites, #{antennas} antennas.
    #{n} provider mappings, #{2 * n} primary/backup downlink routes and #{n} primary uplinks.
    #{n} saved configurations share demo_spacecraft.yaml: 10 telemetry packets and 27 commands.
    Mission-model revisions approved by the seeded second admin: #{length(approved)}.
    Fleet rows (spacecraft, switches, sources) written in #{fleet_ms} ms.
    Configuration activation remains an explicit review step in Cadence.
    Simulator environment: #{F.run_id()}
    Console: #{server_url}/console (organization Reflect Orbital, mission Earendil)
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
                "#{F.fleet_size()}-spacecraft solar-reflector constellation operations rehearsal",
              "scenario" =>
                "#{F.plane_count()} planes × 25 spacecraft; synthetic 625 km near-polar LEO",
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
          join(user)
      end

    Scope.new(%{user: user, organization: organization, organization_membership: membership})
  end

  # The seeding admin joins Reflect Orbital through the public access path: granted directly to a
  # durable account, otherwise invited and accepted as that signed-in user. No row inserts.
  defp join(user) do
    case Cadence.Accounts.establish_organization_access(user.email, F.organization_id(),
           membership_role: :organization_admin,
           invited_by_user_id: user.user_id,
           membership_metadata: F.metadata()
         ) do
      {:ok, %{mode: :granted, membership: membership}} ->
        membership

      {:ok, %{mode: :invited, invitation: invitation}} ->
        {:ok, %{membership: membership}} =
          Cadence.Accounts.accept_invitation_as_user(
            user.user_id,
            invitation.organization_invitation_id
          )

        membership
    end
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
              base_url: F.provider_url(),
              region: "local",
              environment_ref: F.run_id(),
              credential_ref: F.credential_ref(),
              event_ingestion_mode: :polling,
              metadata: F.metadata()
            })

          version
      end

    true = version.environment_ref == F.run_id() and version.base_url == F.provider_url()
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
      {:ok, station} =
        GroundStationStore.persist_ground_station(
          F.organization_id(),
          GroundStation.new(%{
            ground_station_id: site["id"],
            mission_id: F.mission_id(),
            display_name: site["name"],
            code: F.station_code(site["id"]),
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

      # Insert is on_conflict: :nothing, so bring an existing station's code up to date (it may
      # hold a code derived from its name by the profile-routing migration backfill).
      code = F.station_code(site["id"])

      if station.code != code do
        {:ok, _station} =
          GroundStationStore.update_ground_station(
            F.organization_id(),
            F.mission_id(),
            site["id"],
            %{code: code}
          )
      end

      delivery = Map.fetch!(deliveries, site["id"])

      transport =
        ensure_record(
          TransportStore.fetch_transport(
            F.organization_id(),
            F.mission_id(),
            "transport-#{site["id"]}"
          ),
          fn ->
            Transports.persist_transport(
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

  # One provider-managed uplink transport per site (#44, DECISIONS #44).
  defp seed_uplinks(provider, uplink_deliveries) do
    Map.new(F.sites(), fn site ->
      delivery = Map.fetch!(uplink_deliveries, site["id"])
      id = "transport-#{site["id"]}-uplink"

      transport =
        ensure_record(
          TransportStore.fetch_transport(F.organization_id(), F.mission_id(), id),
          fn ->
            Transports.persist_transport(
              F.organization_id(),
              Transport.new(%{
                transport_id: id,
                mission_id: F.mission_id(),
                display_name: "#{site["name"]} S-band uplink",
                ground_station_id: site["id"],
                origin: :provider_managed,
                mission_provider_id: provider.provider_id,
                mission_provider_version: provider.version,
                service_profile_ref: %{"id" => F.uplink_service_id(), "version" => 1},
                delivery_profile_ref: %{"id" => delivery["id"], "version" => delivery["version"]},
                metadata: Map.merge(F.metadata(), %{"ground_station_id" => site["id"]})
              })
            )
          end
        )

      {site["id"], {site, transport}}
    end)
  end

  defp seed_fleet do
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

    # One transaction per chunk, not per craft: commit cost dominated at 1,000 craft (#715).
    F.spacecraft()
    |> Enum.chunk_every(@fleet_chunk)
    |> Enum.each(fn chunk ->
      {:ok, :ok} =
        Repo.transaction(fn -> Enum.each(chunk, &seed_craft/1) end,
          timeout: :infinity
        )
    end)
  end

  defp seed_craft(attrs) do
    {:ok, craft} =
      Cadence.SpacecraftStore.persist_spacecraft(F.organization_id(), Spacecraft.new(attrs))

    # DECISIONS #109: change sets are the only writer of a spacecraft's Telemetry and
    # Commanding switches, and a saved configuration takes them from the spacecraft. Set
    # them here at the store level, like the spacecraft itself (no decision recorded), so
    # configuration.exs saves telemetry and commanding on (board #234).
    {:ok, _switched} =
      Cadence.SpacecraftStore.put_switches(
        F.organization_id(),
        F.mission_id(),
        craft.spacecraft_id,
        %{telemetry_enabled: true, commanding_enabled: true}
      )

    {:ok, _source} =
      Cadence.SourceEndpoints.create_source_endpoint(F.organization_id(), F.mission_id(), %{
        spacecraft_id: craft.spacecraft_id,
        source_ref: craft.display_name,
        display_name: "#{craft.display_name} TT&C",
        metadata: F.metadata()
      })
  end

  defp seed_routes(transports, uplinks) do
    client = RouteChanges.sign_in(F.organization_id())
    existing = RouteChanges.extra_route_ids(client, F.mission_id(), F.profile_id())
    sites = length(transports)

    ops =
      F.spacecraft()
      |> Enum.with_index()
      |> Enum.flat_map(fn {craft, index} ->
        # Primary and candidate sites are half the site ring apart.
        {site, _} = primary = Enum.at(transports, rem(index, sites))
        candidate = Enum.at(transports, rem(index + div(sites, 2), sites))
        uplink = Map.fetch!(uplinks, site["id"])

        [
          downlink_op(craft.spacecraft_id, primary, "primary"),
          downlink_op(craft.spacecraft_id, candidate, "candidate"),
          uplink_op(craft.spacecraft_id, uplink)
        ]
      end)
      |> Enum.reject(&MapSet.member?(existing, &1.entity_id))

    # Older fixture transports carried the station only in metadata. The extra-route kind
    # validates the actual station reference, so stage those bindings before the routes.
    bindings =
      for {site, transport} <- transports,
          transport.ground_station_id != site["id"] do
        %{
          kind: "transport",
          action: "update",
          entity_id: transport.transport_id,
          changes: [%{path: "ground_station_id", value: site["id"]}]
        }
      end

    RouteChanges.submit(
      client,
      F.mission_id(),
      "earendil-routes",
      "Seed Earendil extra routes",
      bindings ++ ops
    )
  end

  defp downlink_op(craft_id, {site, transport}, role) do
    RouteChanges.route(
      "spacecraft_route_#{craft_id}-#{role}",
      craft_id,
      site["id"],
      transport.transport_id,
      "#{site["name"]} — #{role}",
      "TT&C downlink",
      role,
      "none"
    )
  end

  # The primary uplink lands at the primary downlink site (DECISIONS #46).
  defp uplink_op(craft_id, {site, transport}) do
    RouteChanges.route(
      "spacecraft_route_#{craft_id}-uplink",
      craft_id,
      site["id"],
      transport.transport_id,
      "#{site["name"]} — uplink",
      "TT&C uplink",
      "none",
      "primary"
    )
  end

  defp verify! do
    fleet = Cadence.SpacecraftStore.list_spacecraft(F.organization_id(), F.mission_id())
    n = F.fleet_size()
    ^n = length(fleet)
    ^n = fleet |> Enum.map(& &1.scid) |> Enum.uniq() |> length()

    verify_routes!(fleet)
  end

  defp verify_routes!(fleet) do
    Enum.each(fleet, fn craft ->
      {:ok, %{routes: routes, findings: []}} =
        ProviderScheduling.list_ready_downlink_routes(
          F.organization_id(),
          F.mission_id(),
          craft.spacecraft_id
        )

      2 = length(routes)
    end)

    unresolved =
      F.organization_id()
      |> UplinkResolution.annotate(
        F.mission_id(),
        Enum.map(fleet, &%{spacecraft_id: &1.spacecraft_id, source_endpoint_id: nil})
      )
      |> Enum.filter(&Map.has_key?(&1, :failure))

    [] = unresolved

    IO.puts(
      "Verified: all #{length(fleet)} spacecraft have unique SCIDs, two ready downlink routes and one " <>
        "resolved primary uplink."
    )
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

  defp ensure_uplink_deliveries do
    existing = request!(:get, "/provider/v1/delivery-profiles", :provider)

    Map.new(F.sites(), fn site ->
      delivery = F.uplink_delivery(site)

      found =
        Enum.find(existing, &(&1["client_reference"] == delivery["client_reference"])) ||
          request!(:post, "/provider/v1/delivery-profiles", :provider, delivery)

      {site["id"], found}
    end)
  end

  defp ensure_record({:ok, record}, _create), do: record

  defp ensure_record({:error, reason}, create)
       when reason in [
              :provider_credential_not_found,
              :provider_account_grant_not_found,
              :mission_provider_not_found,
              :provider_not_found,
              :transport_not_found
            ] do
    {:ok, record} = create.()
    record
  end

  defp provider_token! do
    case System.get_env(@token_key) do
      value when is_binary(value) and value != "" -> value
      _ -> raise "#{@token_key} is required; run dev/stack env and use mise exec"
    end
  end

  defp request!(method, path, namespace, body \\ nil) do
    {:ok, data} = request(method, path, namespace, body)
    data
  end

  defp request(method, path, namespace, body \\ nil) do
    token = if namespace == :admin, do: "earendil-local-admin", else: provider_token!()
    headers = [{"authorization", "Bearer #{token}"}, {"x-simulator-environment-ref", F.run_id()}]

    opts = [
      method: method,
      url: F.provider_url() <> path,
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
        raise "Simulator unavailable at #{F.provider_url()}; start the simulator first"
    end
  end
end
