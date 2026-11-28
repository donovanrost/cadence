Mix.install([:req, :jason])
Code.require_file("rest_client.exs", __DIR__)
Code.require_file("invitations.exs", __DIR__)
Code.require_file("route_changes.exs", __DIR__)
Code.require_file("earendil_dashboard_import.exs", __DIR__)
Code.require_file("earendil_orbits.exs", __DIR__)
Code.require_file("earendil_simulator.exs", __DIR__)

defmodule EarendilSeed do
  @moduledoc false

  alias EarendilRouteChanges, as: RouteChanges

  import EarendilRestClient,
    only: [request!: 3, request!: 4, request!: 5, request_envelope!: 3, sign_in: 3]

  @batch_size 100
  @run_id "run-earendil-demo-v1"
  # The simulator's loopback admin token (a public local fixture, allowlisted in .gitleaks.toml).
  @sim_admin_token "earendil-local-admin"
  @provider_name "Earendil Demo Ground Network"
  @account_name "Earendil Demo Ground Network"
  @site_rows [
    {"svalbard", "Svalbard", "Norway / Arctic", "SVA", 78.23, 15.41, 6},
    {"troll", "Troll", "Antarctica", "TRL", -72.01, 2.54, 4},
    {"fairbanks", "Fairbanks", "Alaska / North America", "FAI", 64.84, -147.72, 4},
    {"kiruna", "Kiruna", "Sweden / Europe", "KIR", 67.86, 20.23, 4},
    {"hawaii", "Hawaii", "Pacific / North America", "HAW", 19.82, -155.47, 3},
    {"santiago", "Santiago", "Chile / South America", "SCL", -33.45, -70.67, 3},
    {"punta-arenas", "Punta Arenas", "Chile / Southern hemisphere", "PUQ", -53.16, -70.91, 4},
    {"hartebeesthoek", "Hartebeesthoek", "South Africa", "HBK", -25.89, 27.69, 3},
    {"perth", "Perth", "Australia / Indian Ocean", "PER", -31.95, 115.86, 3},
    {"invercargill", "Invercargill", "New Zealand / South Pacific", "INV", -46.41, 168.35, 4},
    {"singapore", "Singapore", "Southeast Asia", "SIN", 1.35, 103.82, 3},
    {"mauritius", "Mauritius", "Indian Ocean", "MRU", -20.16, 57.5, 3},
    {"azores", "Azores", "North Atlantic", "AZO", 37.74, -25.67, 3},
    {"dubai", "Dubai", "Middle East", "DXB", 25.2, 55.27, 3},
    {"alice-springs", "Alice Springs", "Australia / Interior", "ASP", -23.7, 133.88, 3}
  ]

  def run do
    started = now()
    # The current harness measures up to 1,000; the simulator's SCID range reaches 1,023.
    count = integer_env!("EARENDIL_SPACECRAFT_COUNT", 500, 1..1000)
    sites = integer_env!("EARENDIL_SITE_COUNT", 10, 2..15)
    base = System.get_env("BASE_URL") || "http://127.0.0.1:#{System.get_env("PORT", "4001")}"
    email = System.fetch_env!("CADENCE_ADMIN_EMAIL")
    password = System.fetch_env!("CADENCE_ADMIN_PASSWORD")
    approve_configuration? = System.get_env("EARENDIL_SEED_APPROVE_CONFIGURATION", "1") != "0"

    client = phase("admin session", fn -> sign_in(base, email, password) end)

    {client, organization_id, mission_id} =
      phase("organization and mission", fn -> scope(client, email) end)

    {client, revision_id} = phase("catalog import", fn -> seed_catalog(client, mission_id) end)

    {_client, approver} =
      phase("second administrator", fn ->
        EarendilInvitations.ensure_person(
          client,
          organization_id,
          "qa-org-admin-2@example.com",
          "organization_admin",
          "QA Org Admin 2"
        )
      end)

    phase("catalog approval", fn -> approve_catalog(approver, mission_id, revision_id) end)
    {client, catalog} = request!(client, :get, "/missions/#{mission_id}/catalog")
    composition_id = get_in(catalog, ["database", "current_revision", "composition_id"])
    unless composition_id, do: fail!("catalog pin", "current revision has no composition_id")
    site_rows = Enum.take(@site_rows, sites)
    phase("simulator run", fn -> EarendilSimulator.ensure(count, site_rows, @sim_admin_token) end)

    deliveries =
      phase("simulator delivery profiles", fn ->
        EarendilSimulator.ensure_deliveries(site_rows)
      end)

    {client, provider} =
      phase("provider account and mission provider", fn ->
        ensure_provider(client, organization_id, mission_id)
      end)

    client = phase("dashboard source probe", fn -> probe_dashboard_source(client, mission_id) end)
    client = seed_fleet(client, approver, mission_id, count, site_rows, composition_id)

    client =
      phase("provider transports and spacecraft routes", fn ->
        seed_routes(client, approver, mission_id, count, site_rows, provider, deliveries)
      end)

    client =
      phase("spacecraft sources and configuration drafts", fn ->
        seed_configurations(client, approver, mission_id, count, approve_configuration?)
      end)

    client = phase("orbits", fn -> EarendilOrbits.seed(client, mission_id) end)
    phase("dashboard import", fn -> seed_dashboards(client, organization_id, mission_id) end)

    IO.puts("Earendil: organization #{organization_id}, mission #{mission_id}")

    IO.puts("  #{sites} station and profile changes approved by the second administrator")

    if approve_configuration? do
      IO.puts("  configuration activation approved by the second administrator")
    else
      IO.puts("  configuration drafts saved without activation")
    end

    ids_path = Path.expand("../../var/stack/seed.ids", __DIR__)
    File.mkdir_p!(Path.dirname(ids_path))
    File.write!(ids_path, "#{organization_id}\n#{mission_id}\n")
    IO.puts("total: #{elapsed(started)}")
  end

  defp seed_catalog(client, mission_id) do
    path = "/missions/#{mission_id}/catalog"
    {client, catalog} = request!(client, :get, path)

    if get_in(catalog, ["database", "current_revision", "id"]) do
      revision = catalog["database"]["current_revision"]
      IO.puts("  catalog revision #{revision["number"]} already imported")
      {client, revision["id"]}
    else
      {client, run_id} = start_catalog_import(client, path, catalog)
      await_catalog(client, path, run_id, 120)
    end
  end

  defp start_catalog_import(client, path, catalog) do
    source =
      Path.expand("../../dev/catalogs/demo_spacecraft.yaml", __DIR__)
      |> File.read!()
      |> with_demo_verifiers()

    fields = [
      file: {source, filename: "demo_spacecraft.yaml", content_type: "application/yaml"},
      revision_label: "Earendil demo",
      revision_notes: "Synthetic command and telemetry catalog"
    ]

    fields =
      case catalog["database"] do
        %{"id" => id} -> Keyword.put(fields, :database_id, id)
        _ -> Keyword.put(fields, :name, "Demo Spacecraft — Command & Telemetry")
      end

    {client, response} = request!(client, :post, path <> "/imports", nil, multipart: fields)
    {client, response["import_run_id"]}
  end

  defp await_catalog(_client, _path, _run_id, 0), do: fail!("catalog import", "timed out")

  defp await_catalog(client, path, run_id, remaining) do
    {client, run} = request!(client, :get, path <> "/imports/#{run_id}")

    case run["status"] do
      "succeeded" ->
        revision = run["revision"]
        IO.puts("  catalog revision #{revision["number"]} imported")
        {client, revision["id"]}

      "failed" ->
        fail!("catalog import", run["diagnostics"])

      _running ->
        Process.sleep(500)
        await_catalog(client, path, run_id, remaining - 1)
    end
  end

  defp approve_catalog(approver, mission_id, catalog_revision_id) do
    path = "/missions/#{mission_id}/mission-model-revisions"
    {approver, candidates} = request!(approver, :get, path)

    case Enum.find(candidates["revisions"], &catalog_revision?(&1, catalog_revision_id)) do
      nil ->
        # An idempotent rerun has no candidate after approval.
        {_, approved} = request!(approver, :get, path <> "?status=approved")

        unless Enum.any?(approved["revisions"], &catalog_revision?(&1, catalog_revision_id)),
          do: fail!("catalog approval", "revision is neither candidate nor approved")

      revision ->
        revision_path = path <> "/#{revision["id"]}"

        {approver, comparison} =
          request!(approver, :post, revision_path <> "/comparison", %{})

        unless comparison["passed"], do: fail!("catalog comparison", comparison)

        {_, approved} =
          request!(approver, :post, revision_path <> "/approve", %{
            comparison_report_id: comparison["report_id"]
          })

        unless approved["status"] == "approved", do: fail!("catalog approval", approved)
    end

    :ok
  end

  defp catalog_revision?(revision, id),
    do: get_in(revision, ["catalog_revision", "id"]) == id

  @verified_commands ~w(NOOP RESET_COUNTERS SET_MODE)
  @verifiers """
      verifiers:
        - name: Uplink started
          phase: start
          timeout_ms: 30000
          success_criteria:
            criteria_type: comparison
            subject_ref: transport:started
            comparison: equal
            value: true
        - name: Accepted on board
          phase: completion
          timeout_ms: 30000
          success_criteria:
            criteria_type: comparison
            subject_ref: transport:completed
            comparison: equal
            value: true
  """
  @mode_verifier """
        - name: Mode applied
          phase: completion
          timeout_ms: 60000
          success_criteria:
            criteria_type: comparison
            subject_ref: telemetry:HK.sc_mode
            comparison: equal
            value_from_argument: mode
            use_calibrated: false
  """

  defp with_demo_verifiers(source) do
    Enum.reduce(@verified_commands, source, fn name, acc ->
      line = "  - name: #{name}\n"
      ^line = if String.contains?(acc, line), do: line, else: fail!("catalog", "#{name} missing")
      suffix = if name == "SET_MODE", do: @verifiers <> @mode_verifier, else: @verifiers
      String.replace(acc, line, line <> suffix, global: false)
    end)
  end

  defp ensure_provider(client, organization_id, mission_id) do
    account_path = "/organizations/#{organization_id}/provider-accounts"
    {client, listing} = request!(client, :get, account_path)
    account = Enum.find(listing["accounts"], &(&1["name"] == @account_name))

    {client, account_id} =
      if account do
        {client, account["id"]}
      else
        request!(client, :post, account_path, %{
          provider_key: "simulator",
          name: @account_name,
          settings: %{
            base_url: System.fetch_env!("EARENDIL_PROVIDER_URL"),
            environment_ref: @run_id
          },
          credential: %{backend: "env", key: "EARENDIL_DEMO_PROVIDER_TOKEN"}
        })
        |> then(fn {client, created} -> {client, created["id"]} end)
      end

    {client, detail} = request!(client, :get, account_path <> "/#{account_id}")

    grant =
      Enum.find(
        detail["grants"],
        &(&1["state"] == "active" and &1["mission"]["id"] == mission_id)
      )

    {client, grant_id} =
      if grant do
        {client, grant["id"]}
      else
        {client, created} =
          request!(client, :post, account_path <> "/#{account_id}/grants", %{
            mission_id: mission_id,
            expected_account_version: detail["account"]["version"],
            reason: "Synthetic Earendil demo"
          })

        {client, created["grant"]["id"]}
      end

    provider_path = "/missions/#{mission_id}/providers"
    {client, listing} = request!(client, :get, provider_path)
    provider = Enum.find(listing["providers"], &(&1["name"] == @provider_name))

    {client, provider_id} =
      if provider do
        {client, provider["id"]}
      else
        {client, created} =
          request!(client, :post, provider_path, %{
            grant_id: grant_id,
            display_name: @provider_name,
            policy_mode: "approval_required"
          })

        {client, created["provider"]["id"]}
      end

    {client, validate} = request!(client, :post, provider_path <> "/#{provider_id}/validate", %{})
    unless validate["result"]["ok"], do: fail!("provider validate", validate["result"])
    {client, sync} = request!(client, :post, provider_path <> "/#{provider_id}/sync", %{})
    unless sync["result"]["ok"], do: fail!("provider sync", sync["result"])
    {client, sync["provider"]}
  end

  defp seed_fleet(client, approver, mission_id, count, site_rows, composition_id) do
    {client, existing} =
      phase("fleet read", fn ->
        fleet_scids(client, mission_id, nil, MapSet.new())
      end)

    missing = Enum.reject(1..count, &MapSet.member?(existing, &1))
    {client, config} = request!(client, :get, "/missions/#{mission_id}/config")

    client =
      cond do
        missing == [] ->
          IO.puts("Earendil fleet: #{count} spacecraft already present")
          client

        config["change_set"] ->
          IO.puts("Earendil fleet: resuming the open change set")
          client

        true ->
          stage_fleet(client, mission_id, missing, site_rows, composition_id)
      end

    approve_change_set(client, approver, mission_id)
    client
  end

  defp fleet_scids(client, mission_id, cursor, found) do
    path = "/missions/#{mission_id}/spacecraft?limit=500"
    path = if cursor, do: path <> "&cursor=" <> URI.encode_www_form(cursor), else: path
    {client, envelope} = request_envelope!(client, :get, path)
    found = Enum.reduce(envelope["data"]["spacecraft"], found, &MapSet.put(&2, &1["scid"]))

    case get_in(envelope, ["meta", "next_cursor"]) do
      nil -> {client, found}
      next -> fleet_scids(client, mission_id, next, found)
    end
  end

  defp approve_change_set(client, approver, mission_id) do
    path = "/missions/#{mission_id}/config"
    {client, %{"change_set" => set}} = request!(client, :get, path)

    set =
      if set && set["state"] == "open" do
        {_, submitted} =
          request!(client, :post, path <> "/change-sets/#{set["id"]}/submit", %{
            reason: "Seed synthetic Earendil fleet",
            expected_version: set["version"]
          })

        submitted
      else
        set
      end

    if set && set["state"] == "in_review" do
      {_, approved} =
        request!(
          approver,
          :post,
          path <> "/change-sets/#{set["change_set_id"] || set["id"]}/review",
          %{
            decision: "approve",
            expected_version: set["version"]
          }
        )

      unless approved["state"] == "applied", do: fail!("fleet approval", approved)
    end
  end

  defp seed_routes(client, approver, mission_id, count, site_rows, provider, deliveries) do
    {client, %{"transports" => transports}} =
      request!(client, :get, "/missions/#{mission_id}/transports")

    present = MapSet.new(transports, & &1["id"])
    sites = length(site_rows)

    transport_ops =
      Enum.flat_map(site_rows, fn {slug, name, _region, _code, _lat, _lon, _antennas} ->
        site_id = "earendil-#{slug}"
        station_id = "ground_station_earendil_#{String.replace(slug, "-", "_")}"

        for {direction, suffix, service_id} <- [
              {"downlink", "", "service-realtime-ttc-downlink"},
              {"uplink", "-uplink", "service-realtime-ttc-uplink"}
            ],
            id = "transport-#{site_id}#{suffix}",
            not MapSet.member?(present, id) do
          delivery = deliveries[site_id][direction]

          %{
            kind: "transport",
            action: "create",
            entity_id: id,
            document: %{
              display_name: "#{name} S-band #{direction}",
              origin: "provider_managed",
              ground_station_id: station_id,
              mission_provider_id: provider["id"],
              mission_provider_version: provider["version"],
              service_profile_ref: %{id: service_id, version: 1},
              delivery_profile_ref: %{id: delivery["id"], version: delivery["version"]},
              metadata: %{"ground_station_id" => site_id, "synthetic" => true}
            }
          }
        end
      end)

    existing =
      RouteChanges.extra_route_ids(
        client,
        mission_id,
        "profile-earendil-block-1"
      )

    routes =
      1..count
      |> Enum.flat_map(fn index ->
        craft_id =
          "spacecraft-earendil-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"

        primary = Enum.at(site_rows, rem(index - 1, sites))
        candidate = Enum.at(site_rows, rem(index - 1 + div(sites, 2), sites))

        [
          route_op(craft_id, primary, "primary", "primary", "none"),
          route_op(craft_id, candidate, "candidate", "candidate", "none"),
          route_op(craft_id, primary, "uplink", "none", "primary")
        ]
      end)
      |> Enum.reject(&MapSet.member?(existing, &1.entity_id))

    case RouteChanges.submit(
           client,
           mission_id,
           "earendil-routes",
           "Seed Earendil extra routes",
           transport_ops ++ routes
         ) do
      :applied -> :ok
      {:in_review, _id, _version} -> approve_change_set(client, approver, mission_id)
    end

    IO.puts("  #{count} craft with two downlinks and one uplink route")
    client
  end

  defp route_op(craft_id, {slug, name, _, _, _, _, _}, role, downlink, uplink) do
    site_id = "earendil-#{slug}"
    station_id = "ground_station_earendil_#{String.replace(slug, "-", "_")}"
    transport_id = "transport-#{site_id}#{if role == "uplink", do: "-uplink", else: ""}"

    RouteChanges.route(
      "spacecraft_route_#{craft_id}-#{role}",
      craft_id,
      station_id,
      transport_id,
      "#{name} — #{role}",
      "TT&C #{if role == "uplink", do: "uplink", else: "downlink"}",
      downlink,
      uplink
    )
  end

  defp seed_configurations(client, approver, mission_id, count, approve_configuration?) do
    {client, catalog} = request!(client, :get, "/missions/#{mission_id}/catalog")
    revision_id = get_in(catalog, ["database", "current_revision", "id"])
    unless revision_id, do: fail!("configuration", "catalog revision is missing")

    first_id = "spacecraft-earendil-001"

    packet_path =
      "/missions/#{mission_id}/spacecraft/#{first_id}/configuration/workspace/catalogs/#{revision_id}/packets"

    {client, packet_choices} = request!(client, :get, packet_path)
    apids = packet_choices["packets"] |> Enum.map(& &1["apid"]) |> Enum.uniq() |> Enum.sort()
    unless length(apids) == 10, do: fail!("configuration", "expected 10 catalog packet APIDs")

    {reviews, switches} =
      1..count
      |> Task.async_stream(
        &seed_one_configuration(client, mission_id, &1, revision_id, apids),
        max_concurrency: 8,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {index, id, token, review?, switch?}}, {reviews, switches} ->
          if rem(index, 50) == 0, do: IO.puts("  configured #{index}/#{count} spacecraft")

          {if(review?, do: [{id, token} | reviews], else: reviews),
           if(switch?, do: [id | switches], else: switches)}

        {:exit, reason}, _acc ->
          fail!("configuration worker", reason)
      end)

    IO.puts("  #{count} spacecraft sources, Telemetry Decom installations and saved drafts")

    if approve_configuration? and reviews != [],
      do: review_configurations(client, approver, mission_id, reviews)

    if switches != [], do: enable_switches(client, approver, mission_id, switches)
    client
  end

  defp seed_one_configuration(client, mission_id, index, revision_id, apids) do
    id = "spacecraft-earendil-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"
    name = "EARENDIL-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"
    base = "/missions/#{mission_id}/spacecraft/#{id}"
    {client, source_id} = ensure_source(client, base, name)
    client = ensure_decom(client, base)

    {_client, snapshot, document} =
      ensure_configuration(client, base, revision_id, source_id, apids)

    review? = is_nil(snapshot["active"]) or snapshot["active"]["document"] != document

    switch? =
      get_in(snapshot, ["switches", "telemetry_enabled", "value"]) != true or
        get_in(snapshot, ["switches", "commanding_enabled", "value"]) != true

    {index, id, snapshot["token"], review?, switch?}
  end

  defp ensure_source(client, base, name) do
    {client, sources} = request!(client, :get, base <> "/source-endpoints")
    source = Enum.find(sources, &(&1["source_ref"] == name))

    {client, source} =
      if source do
        {client, source}
      else
        request!(client, :post, base <> "/source-endpoints", %{
          source_endpoint: %{
            source_ref: name,
            display_name: "#{name} TT&C",
            metadata: %{"synthetic" => true, "fixture" => "reflect-orbital-v1"}
          }
        })
      end

    {client, source["source_endpoint_id"] || fail!("configuration", "source id missing")}
  end

  defp ensure_decom(client, base) do
    {client, apps} = request!(client, :get, base <> "/apps")
    decom = Enum.find(apps["apps"], &(&1["key"] == "telemetry_decom"))

    if decom && decom["state"] == "installed" do
      client
    else
      {client, _installed} =
        request!(client, :post, base <> "/apps/telemetry_decom/install", %{})

      client
    end
  end

  defp ensure_configuration(client, base, revision_id, source_id, apids) do
    workspace = base <> "/configuration/workspace"
    {client, snapshot} = request!(client, :get, workspace)

    document =
      snapshot["document"]
      |> Map.put("catalog_revision_id", revision_id)
      |> Map.put("telemetry_source_endpoint_id", source_id)
      |> Map.put("handled_apids", apids)

    snapshot =
      if snapshot["saved_version"] && snapshot["document"] == document &&
           snapshot["external_changes"] == false do
        snapshot
      else
        {_, saved} =
          request!(client, :put, workspace <> "/draft", %{
            token: snapshot["token"],
            document: document
          })

        saved
      end

    {client, snapshot, document}
  end

  defp review_configurations(client, approver, mission_id, reviews) do
    base = "/missions/#{mission_id}"
    reviews = Enum.sort_by(reviews, &elem(&1, 0))
    {first_id, _} = hd(reviews)

    {client, first} =
      request!(client, :get, base <> "/spacecraft/#{first_id}/configuration/workspace")

    {client, requested} =
      request!(client, :post, base <> "/configuration/reviews", %{
        spacecraft: Map.new(reviews),
        policy_token: get_in(first, ["approval", "policy_token"]),
        intent: "review"
      })

    unless requested["state"] == "approval_pending",
      do: fail!("configuration review", requested)

    {_, approved} =
      request!(
        approver,
        :post,
        base <> "/activations/#{requested["request_id"]}/approve",
        %{reason: "Seed Earendil configuration activation"}
      )

    unless approved["outcome"] == "applied",
      do: fail!("configuration approval", approved)

    IO.puts(
      "  bulk configuration review approved for #{requested["spacecraft_count"]} spacecraft"
    )

    client
  end

  defp enable_switches(client, approver, mission_id, ids) do
    ops =
      Enum.map(ids, fn id ->
        %{
          kind: "spacecraft",
          action: "update",
          entity_id: id,
          changes: [
            %{path: "telemetry_enabled", value: true},
            %{path: "commanding_enabled", value: true}
          ]
        }
      end)

    case RouteChanges.submit(
           client,
           mission_id,
           "earendil-switches",
           "Enable Earendil telemetry and commanding",
           ops
         ) do
      :applied -> :ok
      {:in_review, _id, _version} -> approve_change_set(client, approver, mission_id)
    end

    IO.puts("  telemetry and commanding switches enabled for #{length(ids)} spacecraft")
  end

  defp seed_dashboards(client, organization_id, mission_id) do
    {client, directory} = request!(client, :get, "/missions/#{mission_id}/spacecraft")
    present = MapSet.new(Enum.map(directory["spacecraft"], & &1["id"]))

    required =
      MapSet.new(
        Enum.map(1..10, fn index ->
          "spacecraft-earendil-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"
        end)
      )

    if MapSet.subset?(required, present) do
      {client, _result} =
        EarendilDashboardImport.import_documents(client, organization_id, mission_id)

      client
    else
      IO.puts("  six Earendil dashboards await the first 10 applied spacecraft")
      client
    end
  end

  defp probe_dashboard_source(client, mission_id) do
    path = "/missions/#{mission_id}/data-sources"
    {client, directory} = request!(client, :get, path)
    source = Enum.find(directory["sources"], &(&1["id"] == "managed_questdb_primary"))
    unless source, do: fail!("dashboard source", "managed QuestDB source is unavailable")

    {client, result} = request!(client, :post, path <> "/#{source["id"]}/probe", %{})
    IO.puts("  managed QuestDB: #{get_in(result, ["probe", "health", "status"]) || "unknown"}")
    client
  end

  defp stage_fleet(client, mission_id, missing, site_rows, composition_id) do
    {client, setup} =
      phase("stage sites and profile", fn ->
        stage_setup(client, mission_id, site_rows, composition_id)
      end)

    {client, staged} =
      phase("stage #{length(missing)} spacecraft", fn ->
        Enum.reduce(Enum.chunk_every(missing, @batch_size), {client, setup}, fn batch,
                                                                                {client, _last} ->
          stage_batch(client, mission_id, batch, composition_id)
        end)
      end)

    {client, result} =
      phase("submit fleet for review", fn ->
        request!(
          client,
          :post,
          "/missions/#{mission_id}/config/change-sets/#{staged["change_set_id"]}/submit",
          %{reason: "Seed synthetic Earendil fleet", expected_version: staged["version"]}
        )
      end)

    IO.puts(
      "Earendil fleet: #{result["state"]} (#{length(missing)} spacecraft, change set #{staged["change_set_id"]})"
    )

    client
  end

  defp stage_setup(client, mission_id, site_rows, composition_id) do
    station_ops = Enum.map(site_rows, &station_op/1)

    ops = station_ops ++ [profile_op(composition_id)]
    path = "/missions/#{mission_id}/config"
    {client, preview} = request!(client, :post, path <> "/preview", %{ops: ops})
    unless preview["verdict"] == "go", do: fail!("setup preview", preview)

    request!(client, :post, path <> "/stage", %{
      summary: "Seed Earendil sites and profile",
      source: %{kind: "dev_seed", name: "earendil"},
      ops: ops
    })
  end

  defp profile_op(composition_id) do
    %{
      kind: "spacecraft_profile",
      action: "create",
      entity_id: "profile-earendil-block-1",
      document: %{
        display_name: "Earendil Block 1 — Demo",
        downlink_protocol: "tm",
        uplink_protocol: "tc",
        frame_parameters: %{frame_size: 1115, ocf_length: 0, fecf: false},
        applications: %{telemetry_decom: %{}},
        composition_id: composition_id,
        metadata: %{"synthetic" => true, "fixture" => "reflect-orbital-v1"}
      }
    }
  end

  defp station_op({slug, name, region, code, latitude, longitude, antennas}) do
    %{
      kind: "ground_station",
      action: "create",
      entity_id: "ground_station_earendil_#{String.replace(slug, "-", "_")}",
      document: %{
        display_name: "#{name} (Demo)",
        code: code,
        provider: @provider_name,
        region: region,
        # The mission's own location (#957): pass prediction uses it, and it wins over the
        # simulator's report, whose station ids differ from these.
        latitude_deg: latitude,
        longitude_deg: longitude,
        metadata: %{
          "provider_ground_station_ref" => "earendil-#{slug}",
          "antenna_count" => antennas,
          "synthetic" => true
        }
      }
    }
  end

  defp stage_batch(client, mission_id, batch, composition_id) do
    ops = Enum.map(batch, &spacecraft_op/1)

    {client, preview} =
      request!(client, :post, "/missions/#{mission_id}/config/preview", %{
        ops: [profile_op(composition_id) | ops]
      })

    unless preview["verdict"] == "go", do: fail!("fleet preview", preview)

    {client, stage} =
      request!(client, :post, "/missions/#{mission_id}/config/stage", %{
        summary: "Seed Earendil spacecraft #{hd(batch)}–#{List.last(batch)}",
        source: %{kind: "dev_seed", name: "earendil"},
        ops: ops
      })

    IO.puts("  staged through SCID #{List.last(batch)} (#{stage["staged_count"]} changes)")
    {client, stage}
  end

  defp scope({client, _session}, email) do
    slug = "reflect-orbital"
    {client, listing} = request!(client, :get, "/admin/organizations?q=#{slug}")
    organization = Enum.find(listing["organizations"], &(&1["slug"] == slug))

    {client, org_id} =
      if organization do
        {client, organization["id"]}
      else
        {client, created} =
          request!(client, :post, "/admin/organizations", %{
            name: "Reflect Orbital",
            slug: slug,
            first_admin_email: email
          })

        {client, created["organization"]["id"]}
      end

    client = accept_first_admin_invitation(client, org_id)

    {client, session} =
      request!(client, :put, "/session/organization", %{organization_id: org_id})

    client = %{client | csrf: session["csrf_token"]}
    {client, directory} = request!(client, :get, "/organizations/#{org_id}/people")

    unless Enum.any?(directory["members"], &(&1["email"] == email)),
      do: fail!("first administrator", "environment admin has no Reflect Orbital membership")

    organization = Enum.find(session["organizations"], &(&1["id"] == org_id))
    mission = Enum.find(organization["missions"], &(&1["slug"] == "earendil"))

    {client, mission_id} =
      if mission do
        {client, mission["id"]}
      else
        {client, created} =
          request!(client, :post, "/organizations/#{org_id}/missions", %{
            name: "Earendil",
            slug: "earendil"
          })

        {client, created["mission"]["id"]}
      end

    {client, org_id, mission_id}
  end

  defp accept_first_admin_invitation(client, organization_id) do
    {client, listing} = request!(client, :get, "/account/invitations")

    case Enum.find(listing["invitations"], fn invitation ->
           get_in(invitation, ["organization", "id"]) == organization_id
         end) do
      nil ->
        client

      invitation ->
        {client, _accepted} =
          request!(client, :post, "/account/invitations/#{invitation["id"]}/accept", %{})

        client
    end
  end

  defp spacecraft_op(index) do
    name = "EARENDIL-#{String.pad_leading(Integer.to_string(index), 3, "0")}"

    %{
      kind: "spacecraft",
      action: "create",
      entity_id: "spacecraft-#{String.downcase(name)}",
      document: %{
        display_name: name,
        scid: index,
        spacecraft_type_id: "profile-earendil-block-1",
        spacecraft_type_version: 1,
        telemetry_enabled: true,
        commanding_enabled: true,
        metadata: %{
          "synthetic" => true,
          "fixture" => "reflect-orbital-v1",
          "plane" => div(index - 1, 25) + 1,
          "slot" => rem(index - 1, 25) + 1
        }
      }
    }
  end

  defp phase(name, fun) do
    started = now()
    result = fun.()
    IO.puts("#{name}: #{elapsed(started)}")
    result
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp elapsed(started), do: "#{Float.round((now() - started) / 1000, 2)}s"

  defp integer_env!(name, default, range) do
    value = System.get_env(name, Integer.to_string(default))

    case Integer.parse(value) do
      {n, ""} ->
        if n in range, do: n, else: fail!(name, "expected an integer in #{inspect(range)}")

      _ ->
        fail!(name, "expected an integer in #{inspect(range)}")
    end
  end

  defp fail!(phase, details),
    do: raise("#{phase}: #{inspect(details, limit: 12, printable_limit: 500)}")
end

EarendilSeed.run()
