defmodule EarendilSimulator do
  @moduledoc """
  The Earendil seed's simulator run: its scenario (the fleet's sites as ground stations) and run,
  through the simulator's admin API. `EARENDIL_ORBIT_SOURCE=uploaded` makes the scenario offer
  real passes over the orbits Cadence uploads (#893); `synthetic`, the default, keeps the hash
  model until the fleet's orbits are applied and uploaded to its provider.
  """

  @run_id "run-earendil-demo-v1"
  @scenario_id "scenario-earendil-demo-v1"

  @doc """
  Resumes the Earendil simulator run, or creates its scenario and run. `admin_token` is the
  simulator's local admin token, which the seed owns.
  """
  def ensure(count, site_rows, admin_token) do
    case sim_request(admin_token, :get, "/admin/v1/runs/#{@run_id}") do
      {200, %{"state" => "running"}} ->
        :ok

      {200, %{"state" => "paused"}} ->
        {200, _run} = sim_request(admin_token, :post, "/admin/v1/runs/#{@run_id}/resume", %{})
        :ok

      {404, _missing} ->
        create_simulator_run(count, site_rows, admin_token)

      other ->
        fail!("simulator run", other)
    end
  end

  @doc "Creates the simulator's downlink and uplink delivery profiles for each site."
  def ensure_deliveries(site_rows) do
    ingress = System.fetch_env!("EARENDIL_INGRESS_BASE_PORT") |> String.to_integer()
    uplink = System.fetch_env!("EARENDIL_UPLINK_BASE_PORT") |> String.to_integer()
    host = System.get_env("EARENDIL_INGRESS_HOST", "127.0.0.1")
    token = System.fetch_env!("EARENDIL_DEMO_PROVIDER_TOKEN")
    {200, existing} = provider_request(token, :get, "/provider/v1/delivery-profiles")

    site_rows
    |> Enum.with_index()
    |> Map.new(fn {{slug, name, _region, _code, _lat, _lon, _antennas}, index} ->
      site_id = "earendil-#{slug}"

      deliveries =
        for {direction, suffix, port, family, size} <- [
              {"downlink", "", ingress + index, "ccsds_tm", 1115},
              {"uplink", ":uplink", uplink + index, "ccsds_tc", 32}
            ] do
          client_ref = site_id <> suffix

          profile =
            Enum.find(existing, &(&1["client_reference"] == client_ref)) ||
              create_delivery(token, %{
                display_name: "#{name} #{direction}",
                client_reference: client_ref,
                direction: direction,
                delivery_kind: "realtime_stream",
                target: %{
                  protocol: "tcp",
                  mode: "provider_connects",
                  host: host,
                  port: port
                },
                framing: %{family: family, mode: "fixed_size", frame_bytes: size}
              })

          {direction, profile}
        end

      {site_id, Map.new(deliveries)}
    end)
  end

  defp create_delivery(token, document) do
    {201, profile} = provider_request(token, :post, "/provider/v1/delivery-profiles", document)
    profile
  end

  defp provider_request(token, method, path, body \\ nil) do
    base = System.fetch_env!("EARENDIL_PROVIDER_URL")

    options = [
      method: method,
      url: base <> path,
      headers: [
        {"authorization", "Bearer #{token}"},
        {"x-simulator-environment-ref", @run_id}
      ],
      retry: false
    ]

    options = if body, do: Keyword.put(options, :json, body), else: options

    case Req.request(options) do
      {:ok, response} when response.status in 200..299 ->
        {response.status, Map.get(response.body, "data", response.body)}

      {:ok, response} ->
        fail!("simulator #{method} #{path}", {response.status, response.body})

      {:error, error} ->
        fail!("simulator #{method} #{path}", Exception.message(error))
    end
  end

  defp create_simulator_run(count, site_rows, admin_token) do
    case sim_request(admin_token, :get, "/admin/v1/scenarios/#{@scenario_id}") do
      {200, _scenario} ->
        :ok

      {404, _missing} ->
        scenario = %{
          id: @scenario_id,
          name: "Earendil synthetic rehearsal",
          spacecraft_count: count,
          spacecraft_prefix: "EARENDIL",
          ground_stations: site_maps(site_rows),
          pass_model: %{cadence_seconds: 5_820, duration_seconds: 480, jitter_seconds: 120},
          telemetry_profile: %{
            rate_hz: 1.0,
            noise_amplitude: 0.05,
            spacecraft_frames:
              Map.new(1..count, fn index ->
                name = "EARENDIL-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"
                {name, %{scid: index, vcid: 0}}
              end)
          },
          fault_profile: %{},
          orbit_readiness: %{
            status: "current",
            source_kind: orbit_source(),
            ephemeris_ref: "earendil-demo-orbits-v1",
            version: 1,
            validity_seconds: 604_800
          }
        }

        {201, _scenario} = sim_request(admin_token, :post, "/admin/v1/scenarios", scenario)
    end

    {201, _run} =
      sim_request(admin_token, :post, "/admin/v1/scenarios/#{@scenario_id}/runs", %{
        id: @run_id,
        seed: 20_261_019,
        speed: 1.0
      })

    :ok
  end

  defp orbit_source do
    case System.get_env("EARENDIL_ORBIT_SOURCE", "synthetic") do
      source when source in ["synthetic", "uploaded"] ->
        source

      other ->
        fail!("EARENDIL_ORBIT_SOURCE", "must be synthetic or uploaded, got #{inspect(other)}")
    end
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
        location: %{latitude_deg: latitude, longitude_deg: longitude},
        antenna_count: antennas,
        ingress_port: ingress + index,
        uplink_port: uplink + index,
        synthetic: true
      }
    end)
  end

  defp sim_request(admin_token, method, path, body \\ nil) do
    base = System.fetch_env!("EARENDIL_PROVIDER_URL")
    headers = [{"authorization", "Bearer #{admin_token}"}]
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

  defp fail!(phase, details),
    do: raise("#{phase}: #{inspect(details, limit: 12, printable_limit: 500)}")
end
