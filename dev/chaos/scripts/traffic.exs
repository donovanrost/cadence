unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
         System.get_env("POD_NAMESPACE") == "cadence-chaos",
       do: raise("Not the isolated chaos lab")

Application.put_env(:cadence_simulator, :provider_http, enabled: false)
Application.put_env(:cadence_simulator, :provider_store, path: "/data/traffic.dets")
{:ok, _} = Application.ensure_all_started(:cadence_simulator)

rate_hz = System.get_env("LAB_RATE_HZ", "1.0") |> String.to_float()

feeds =
  Enum.map(1..10, fn scid ->
    {:ok, pid} =
      CadenceSimulator.start_simulator(
        target_id:
          "spacecraft_runtime:spacecraft-earendil-#{String.pad_leading(to_string(scid), 3, "0")}",
        rate_hz: rate_hz,
        output: {:tcp, "cadence", 42100 + scid - 1},
        definitions_path: "/lab/demo_spacecraft.yaml",
        provider: CadenceSimulator.Providers.DatabaseDynamics,
        provider_opts: [noise_amplitude: 0.05],
        parallel_mode: :sequential,
        generator_count: 1,
        frame: %{format: :tm, frame_size: 1115, scid: scid, vcid: 0}
      )

    {scid, pid}
  end)

Stream.repeatedly(fn ->
  Process.sleep(5_000)

  Enum.each(feeds, fn {scid, pid} ->
    stats =
      pid
      |> CadenceSimulator.simulator_stats()
      |> Map.take([:rate_hz, :packet_count, :step, :send_buffer_stats])

    IO.puts(Jason.encode!(%{at: DateTime.utc_now(), spacecraft: scid, stats: stats}))
  end)
end)
|> Stream.run()
