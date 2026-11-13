import Config

if config_env() != :test do
  enabled? =
    System.get_env("CADENCE_SIMULATOR_HTTP_ENABLED", "false")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))

  admin_api_token = System.get_env("CADENCE_SIMULATOR_ADMIN_API_TOKEN")
  provider_api_token = System.get_env("CADENCE_SIMULATOR_PROVIDER_API_TOKEN")

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
    ],
    provider_admin_api_token: admin_api_token,
    provider_api_token: provider_api_token
end

# #50: test values that change between runs (the partition, the OS pid) are runtime config, so the
# compile-time config stays stable and switching MIX_TEST_PARTITION doesn't recompile everything.
# The same block is in each project's runtime.exs (root, cadence, cadence_web, cadence_simulator),
# because each project reads only its own.
if config_env() == :test do
  partition = System.get_env("MIX_TEST_PARTITION", "")

  config :cadence, Cadence.Repo, database: "cadence_test#{partition}"

  config :cadence, :ingress_journal,
    base_path:
      Path.join(
        System.tmp_dir!(),
        "cadence-ingress-journal-test-#{System.pid()}-#{System.get_env("MIX_TEST_PARTITION", "0")}"
      )
end

if config_env() == :test do
  config :cadence_simulator, :provider_store,
    path:
      Path.join(
        System.tmp_dir!(),
        "cadence_simulator_provider_test_#{System.get_env("MIX_TEST_PARTITION", "0")}.dets"
      )
end
