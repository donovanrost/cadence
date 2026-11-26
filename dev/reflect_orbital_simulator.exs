# Run from apps/cadence_simulator with mix run --no-start --no-halt.
if Mix.env() != :dev, do: raise("The Earendil simulator is a local development demo")

# EARENDIL_SIMULATOR_PORT lets a second worktree run its own simulator; seed that worktree
# with EARENDIL_PROVIDER_URL pointing at the same port.
port = String.to_integer(System.get_env("EARENDIL_SIMULATOR_PORT", "4101"))

Application.put_env(:cadence_simulator, :provider_http,
  enabled: true,
  ip: {127, 0, 0, 1},
  port: port
)

Application.put_env(:cadence_simulator, :provider_store,
  path: Path.expand("../var/reflect_orbital/provider.dets", __DIR__)
)

Application.put_env(:cadence_simulator, :provider_defaults,
  definitions_path: Path.expand("../dev/catalogs/demo_spacecraft.yaml", __DIR__)
)

# Public, loopback-only demo credentials; never use these for a deployed service.
Application.put_env(:cadence_simulator, :provider_admin_api_token, "earendil-local-admin")
Application.put_env(:cadence_simulator, :provider_api_token, "earendil-local-provider")

{:ok, _apps} = Application.ensure_all_started(:cadence_simulator)
IO.puts("Earendil demo simulator listening on http://127.0.0.1:#{port}")
