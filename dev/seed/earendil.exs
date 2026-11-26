Mix.install([:req, :jason])
Code.require_file("earendil_dashboards.exs", __DIR__)

defmodule EarendilSeed do
  @moduledoc false

  @api_base "/api/v1"
  @batch_size 100
  @sim_admin_token "earendil-local-admin"
  @run_id "run-earendil-demo-v1"
  @scenario_id "scenario-earendil-demo-v1"
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

    client = phase("admin session", fn -> sign_in(base, email, password) end)

    {client, organization_id, mission_id} =
      phase("organization and mission", fn -> scope(client, email) end)

    {client, revision_id} = phase("catalog import", fn -> seed_catalog(client, mission_id) end)
    site_rows = Enum.take(@site_rows, sites)
    phase("simulator run", fn -> ensure_simulator(count, site_rows) end)

    {client, _provider_id} =
      phase("provider account and mission provider", fn ->
        ensure_provider(client, organization_id, mission_id)
      end)

    client = phase("dashboard source probe", fn -> probe_dashboard_source(client, mission_id) end)
    seed_fleet(client, mission_id, count, site_rows, revision_id)
    phase("dashboard import", fn -> seed_dashboards(client, organization_id, mission_id) end)

    IO.puts("Earendil: organization #{organization_id}, mission #{mission_id}")

    IO.puts("  orbit elements wait on #732")
    IO.puts("  #{sites} station and profile changes await the fleet's independent review")
    IO.puts("  second-person invitations and approval wait on #745")
    IO.puts("  spacecraft configuration drafts wait on an applied fleet and bulk review #734")
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

  defp ensure_simulator(count, site_rows) do
    case sim_request(:get, "/admin/v1/runs/#{@run_id}") do
      {200, %{"state" => "running"}} ->
        :ok

      {200, %{"state" => "paused"}} ->
        {200, _run} = sim_request(:post, "/admin/v1/runs/#{@run_id}/resume", %{})
        :ok

      {404, _missing} ->
        create_simulator_run(count, site_rows)

      other ->
        fail!("simulator run", other)
    end
  end

  defp create_simulator_run(count, site_rows) do
    case sim_request(:get, "/admin/v1/scenarios/#{@scenario_id}") do
      {200, _scenario} ->
        :ok

      {404, _missing} ->
        scenario = %{
          id: @scenario_id,
          name: "Earendil synthetic rehearsal",
          spacecraft_count: count,
          spacecraft_prefix: "EARENDIL",
          ground_stations: site_maps(site_rows),
          orbit_readiness: %{
            status: "current",
            source_kind: "synthetic",
            ephemeris_ref: "earendil-demo-orbits-v1",
            version: 1,
            validity_seconds: 604_800
          }
        }

        {201, _scenario} = sim_request(:post, "/admin/v1/scenarios", scenario)
    end

    {201, _run} =
      sim_request(:post, "/admin/v1/scenarios/#{@scenario_id}/runs", %{
        id: @run_id,
        seed: 20_261_019,
        speed: 1.0
      })

    :ok
  end

  defp site_maps(rows) do
    ingress = System.fetch_env!("EARENDIL_INGRESS_BASE_PORT") |> String.to_integer()
    uplink = System.fetch_env!("EARENDIL_UPLINK_BASE_PORT") |> String.to_integer()

    rows
    |> Enum.with_index()
    |> Enum.map(fn {{slug, name, region, _code, latitude, longitude, antennas}, index} ->
      %{
        id: "earendil-#{slug}",
        name: "#{name} (Demo)",
        region: region,
        latitude_deg: latitude,
        longitude_deg: longitude,
        antenna_count: antennas,
        ingress_port: ingress + index,
        uplink_port: uplink + index,
        synthetic: true
      }
    end)
  end

  defp sim_request(method, path, body \\ nil) do
    base = System.fetch_env!("EARENDIL_PROVIDER_URL")
    headers = [{"authorization", "Bearer #{@sim_admin_token}"}]
    options = [method: method, url: base <> path, headers: headers, retry: false]
    options = if body, do: Keyword.put(options, :json, body), else: options

    case Req.request(options) do
      {:ok, response} when response.status in [200, 201, 404] ->
        {response.status, Map.get(response.body, "data", response.body)}

      {:ok, response} ->
        fail!("simulator #{method} #{path}", {response.status, response.body})

      {:error, reason} ->
        fail!("simulator #{method} #{path}", Exception.message(reason))
    end
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
    {client, provider_id}
  end

  defp seed_fleet(client, mission_id, count, site_rows, revision_id) do
    {client, existing} =
      phase("fleet read", fn ->
        {client, body} = request!(client, :get, "/missions/#{mission_id}/spacecraft")
        {client, MapSet.new(Enum.map(body["spacecraft"], & &1["scid"]))}
      end)

    missing = Enum.reject(1..count, &MapSet.member?(existing, &1))
    {client, config} = request!(client, :get, "/missions/#{mission_id}/config")

    cond do
      missing == [] ->
        IO.puts("Earendil fleet: #{count} spacecraft already present")

      config["change_set"] ->
        IO.puts("Earendil fleet: a change set is open; review it before rerunning the seed")

      true ->
        stage_fleet(client, mission_id, missing, site_rows, revision_id)
    end
  end

  defp seed_dashboards(client, organization_id, mission_id) do
    path = "/missions/#{mission_id}/dashboards"
    {client, directory} = request!(client, :get, "/missions/#{mission_id}/spacecraft")
    present = MapSet.new(Enum.map(directory["spacecraft"], & &1["id"]))

    required =
      MapSet.new(
        Enum.map(1..10, fn index ->
          "spacecraft-earendil-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"
        end)
      )

    if MapSet.subset?(required, present) do
      EarendilDashboardDocuments.documents(organization_id, mission_id)
      |> Enum.reduce(client, &import_dashboard(&2, &1, path))
    else
      IO.puts("  six Earendil dashboards await the first 10 applied spacecraft and #745 approval")
      client
    end
  end

  defp import_dashboard(client, document, path) do
    {client, result} = request!(client, :post, path, %{document: document, identity: "keep"})
    unless result["id"] == document.dashboard_id, do: fail!("dashboard import", result)

    state = if result["existing"], do: "existing", else: "created"
    IO.puts("  #{document.dashboard_id}: #{state}")
    client
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

  defp stage_fleet(client, mission_id, missing, site_rows, revision_id) do
    {client, setup} =
      phase("stage sites and profile", fn ->
        stage_setup(client, mission_id, site_rows, revision_id)
      end)

    {client, staged} =
      phase("stage #{length(missing)} spacecraft", fn ->
        Enum.reduce(Enum.chunk_every(missing, @batch_size), {client, setup}, fn batch,
                                                                                {client, _last} ->
          stage_batch(client, mission_id, batch, revision_id)
        end)
      end)

    {_client, result} =
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

    if result["state"] == "in_review",
      do:
        IO.puts("  approval waits on #745: invite a second person and use that person's session")
  end

  defp stage_setup(client, mission_id, site_rows, revision_id) do
    station_ops = Enum.map(site_rows, &station_op/1)

    ops = station_ops ++ [profile_op(revision_id)]
    path = "/missions/#{mission_id}/config"
    {client, preview} = request!(client, :post, path <> "/preview", %{ops: ops})
    unless preview["verdict"] == "go", do: fail!("setup preview", preview)

    request!(client, :post, path <> "/stage", %{
      summary: "Seed Earendil sites and profile",
      source: %{kind: "dev_seed", name: "earendil"},
      ops: ops
    })
  end

  defp profile_op(revision_id) do
    %{
      kind: "spacecraft_profile",
      action: "create",
      entity_id: "spacecraft_type_earendil_demo",
      document: %{
        display_name: "Earendil Block 1 — Demo",
        downlink_protocol: "tm",
        uplink_protocol: "tc",
        frame_parameters: %{frame_size: 1115, ocf_length: 0, fecf: false},
        applications: %{telemetry_decom: %{}},
        catalog_revision_id: revision_id,
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
        metadata: %{
          "provider_ground_station_ref" => "earendil-#{slug}",
          "latitude_deg" => latitude,
          "longitude_deg" => longitude,
          "antenna_count" => antennas,
          "synthetic" => true
        }
      }
    }
  end

  defp stage_batch(client, mission_id, batch, revision_id) do
    ops = Enum.map(batch, &spacecraft_op/1)

    {client, preview} =
      request!(client, :post, "/missions/#{mission_id}/config/preview", %{
        ops: [profile_op(revision_id) | ops]
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

  defp sign_in(base, email, password) do
    client = %{base: String.trim_trailing(base, "/"), cookies: %{}, csrf: nil}
    {client, page} = request!(client, :get, "/console/sign-in", nil, api?: false)
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page)
    client = %{client | csrf: csrf}
    {client, _} = request!(client, :post, "/auth/sign-in", %{email: email, password: password})
    {client, session} = request!(%{client | csrf: nil}, :get, "/session")

    unless session["admin_mode"] == true,
      do: fail!("admin sign-in", "environment admin session did not enter admin mode")

    {%{client | csrf: session["csrf_token"]}, session}
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

    {client, session} =
      request!(client, :put, "/session/organization", %{organization_id: org_id})

    client = %{client | csrf: session["csrf_token"]}
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

  defp spacecraft_op(index) do
    name = "EARENDIL-#{String.pad_leading(Integer.to_string(index), 3, "0")}"

    %{
      kind: "spacecraft",
      action: "create",
      entity_id: "spacecraft-#{String.downcase(name)}",
      document: %{
        display_name: name,
        scid: index,
        spacecraft_type_id: "spacecraft_type_earendil_demo",
        spacecraft_type_version: 1,
        metadata: %{
          "synthetic" => true,
          "fixture" => "reflect-orbital-v1",
          "plane" => div(index - 1, 25) + 1,
          "slot" => rem(index - 1, 25) + 1
        }
      }
    }
  end

  defp request!(client, method, path, body \\ nil, opts \\ []) do
    url = client.base <> if(Keyword.get(opts, :api?, true), do: @api_base, else: "") <> path
    accept = if Keyword.get(opts, :api?, true), do: "application/json", else: "text/html"

    options = [
      method: method,
      url: url,
      headers: headers(client, accept),
      receive_timeout: 120_000,
      retry: false
    ]

    options = if body, do: Keyword.put(options, :json, body), else: options

    options =
      if opts[:multipart],
        do: Keyword.put(options, :form_multipart, opts[:multipart]),
        else: options

    case Req.request(options) do
      {:ok, response} -> response!(client, method, path, response)
      {:error, error} -> fail!("#{method} #{path}", Exception.message(error))
    end
  end

  defp headers(client, accept) do
    headers = [{"accept", accept}]
    headers = if client.csrf, do: [{"x-csrf-token", client.csrf} | headers], else: headers

    if map_size(client.cookies) == 0 do
      headers
    else
      cookie = Enum.map_join(client.cookies, "; ", fn {name, value} -> "#{name}=#{value}" end)
      [{"cookie", cookie} | headers]
    end
  end

  defp response!(client, method, path, response) do
    unless response.status in 200..299,
      do: fail!("#{method} #{path} (HTTP #{response.status})", response.body)

    cookies =
      Enum.reduce(Req.Response.get_header(response, "set-cookie"), client.cookies, &cookie/2)

    data =
      if is_map(response.body),
        do: Map.get(response.body, "data", response.body),
        else: response.body

    {%{client | cookies: cookies}, data}
  end

  defp cookie(line, cookies) do
    [pair | _] = String.split(line, ";", parts: 2)

    case String.split(pair, "=", parts: 2) do
      [name, value] -> Map.put(cookies, name, value)
      _ -> cookies
    end
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
