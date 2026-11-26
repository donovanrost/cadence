Mix.install([:req, :jason])

defmodule EarendilSeed do
  @moduledoc false

  # Change this one prefix when the console routes move in #757.
  @api_base "/api/console/v1"
  @batch_size 100

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

    seed_fleet(client, mission_id, count)

    IO.puts("Earendil: organization #{organization_id}, mission #{mission_id}")

    IO.puts("  orbit elements wait on #732; dashboard import waits on #746")
    IO.puts("  #{sites} requested sites, provider and profile configuration review wait on #734")
    IO.puts("  second-person invitations and approval wait on #745")
    IO.puts("total: #{elapsed(started)}")
  end

  defp seed_fleet(client, mission_id, count) do
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
        stage_fleet(client, mission_id, missing)
    end
  end

  defp stage_fleet(client, mission_id, missing) do
    {client, staged} =
      phase("stage #{length(missing)} spacecraft", fn ->
        Enum.reduce(Enum.chunk_every(missing, @batch_size), {client, nil}, fn batch,
                                                                              {client, _last} ->
          stage_batch(client, mission_id, batch)
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

  defp stage_batch(client, mission_id, batch) do
    ops = Enum.map(batch, &spacecraft_op/1)

    {client, preview} =
      request!(client, :post, "/missions/#{mission_id}/config/preview", %{ops: ops})

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
      document: %{
        display_name: name,
        scid: index,
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
