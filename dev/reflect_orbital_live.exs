# Run with mise run earendil-live. This process owns the ten TCP simulator feeds.
if Mix.env() != :dev, do: raise("Earendil live telemetry is a local development demo")

{:ok, hostname} = :inet.gethostname()
peer = :"cadence@#{hostname}"
unless Node.connect(peer), do: raise("Start mise run cadence before the live demo")

# Per-packet SQL debug output overwhelms an interactive development terminal.
# Keep normal operational messages and every warning/error during the rehearsal.
:ok = :rpc.call(peer, Logger, :configure, [[level: :info]])

for file <- ["fixture.exs", "dashboards.exs", "live_contacts.exs"] do
  case :rpc.call(
         peer,
         Code,
         :compile_file,
         [Path.join([__DIR__, "reflect_orbital", file])],
         120_000
       ) do
    {:badrpc, reason} -> raise "Could not load #{file}: #{inspect(reason)}"
    _ -> :ok
  end
end

duration = String.to_integer(System.get_env("EARENDIL_DEMO_CONTACT_SECONDS") || "7200")
unless duration in 60..28_800, do: raise("Demo duration must be 60–28800 seconds")

IO.puts("Preparing ten rehearsal contacts and recovering their telemetry decoders…")

contacts =
  case :rpc.call(peer, Cadence.Dev.ReflectOrbital.LiveContacts, :run, [duration], 1_800_000) do
    contacts when is_list(contacts) and length(contacts) == 10 -> contacts
    error -> raise "Contact setup failed: #{inspect(error, limit: 20)}"
  end

IO.puts("Checking telemetry history and saving the dashboard suite…")

case :rpc.call(
       peer,
       Cadence.Dev.ReflectOrbital.Dashboards,
       :run,
       [[replace?: System.get_env("EARENDIL_REBUILD_DASHBOARDS") == "1"]],
       120_000
     ) do
  %{dashboards: dashboards, playlist: playlist} ->
    IO.puts("Earendil: ten live spacecraft, 1 Hz per packet family, local TCP ingress")

    Enum.each(
      dashboards,
      &IO.puts(
        "#{&1.name}: http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/#{&1.id}"
      )
    )

    IO.puts("Playlist: #{playlist}")

  error ->
    raise "Dashboard setup failed: #{inspect(error, limit: 30)}"
end

Application.put_env(:cadence_simulator, :provider_http, enabled: false)

Application.put_env(:cadence_simulator, :provider_store,
  path: Path.expand("../var/reflect_orbital/dashboard_feed.dets", __DIR__)
)

{:ok, _} = Application.ensure_all_started(:cadence_simulator)

feeds =
  Enum.map(contacts, fn contact ->
    {:ok, pid} =
      CadenceSimulator.start_simulator(
        target_id: contact.source_endpoint_id,
        rate_hz: 1.0,
        output: {:tcp, "127.0.0.1", contact.port},
        definitions_path:
          Path.expand("../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml", __DIR__),
        provider: CadenceSimulator.Providers.DatabaseDynamics,
        provider_opts: [noise_amplitude: 0.05],
        parallel_mode: :sequential,
        generator_count: 1,
        frame: %{format: :tm, frame_size: 1115, scid: contact.scid, vcid: 0}
      )

    Process.sleep(100)
    {pid, contact}
  end)

Process.sleep(3_000)

Enum.each(feeds, fn {pid, contact} ->
  IO.inspect(%{
    spacecraft: contact.spacecraft_id,
    site: contact.ground_site,
    expires_at: contact.ends_at,
    stats: Map.take(CadenceSimulator.simulator_stats(pid), [:rate_hz, :packet_count, :step])
  })
end)

remaining_ms =
  contacts
  |> Enum.map(&DateTime.diff(&1.ends_at, DateTime.utc_now(), :millisecond))
  |> Enum.min()
  |> max(0)

Process.sleep(remaining_ms)
Enum.each(feeds, fn {pid, _} -> CadenceSimulator.stop_simulator(pid) end)
IO.puts("Earendil rehearsal complete; telemetry feeds stopped.")
System.halt(0)
