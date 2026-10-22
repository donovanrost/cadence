unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
         System.get_env("POD_NAMESPACE") == "cadence-chaos",
       do: raise("Not the isolated chaos lab")

Application.put_env(:cadence_simulator, :provider_http,
  enabled: true,
  ip: {0, 0, 0, 0},
  port: 4101
)

Application.put_env(:cadence_simulator, :provider_store, path: "/data/provider.dets")

Application.put_env(:cadence_simulator, :provider_defaults,
  definitions_path: "/lab/demo_spacecraft.yaml"
)

# Isolated synthetic provider only; never configured for a flight provider.
Application.put_env(:cadence_simulator, :provider_admin_api_token, "earendil-local-admin")
Application.put_env(:cadence_simulator, :provider_api_token, "earendil-local-provider")
Application.put_env(:cadence_simulator, :provider_auth_required, true)
{:ok, _} = Application.ensure_all_started(:cadence_simulator)
Process.sleep(:infinity)
