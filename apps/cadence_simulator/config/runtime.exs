import Config

if config_env() != :test do
  enabled? =
    System.get_env("CADENCE_SIMULATOR_HTTP_ENABLED", "false")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))

  config :cadence_simulator,
    provider_http: [
      enabled: enabled?,
      ip: {0, 0, 0, 0},
      port: System.get_env("CADENCE_SIMULATOR_PORT", "4101") |> String.to_integer()
    ],
    provider_store: [
      path:
        System.get_env(
          "CADENCE_SIMULATOR_STORE_PATH",
          Path.expand("../../../var/cadence_simulator_provider.dets", __DIR__)
        )
    ],
    provider_defaults: [
      definitions_path: System.get_env("CADENCE_SIMULATOR_DEFINITIONS_PATH")
    ]

  config :cadence_simulator,
    provider_api_token: System.get_env("CADENCE_SIMULATOR_API_TOKEN")
end
