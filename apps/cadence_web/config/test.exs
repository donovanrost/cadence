import Config

config :cadence_web, CadenceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4101],
  server: false,
  secret_key_base: String.duplicate("1", 64)

config :cadence_web, CadenceWeb.Mailer, adapter: Swoosh.Adapters.Test

config :cadence_web,
  provider_account_live_opts: [
    manage_backend?: false,
    secret_backend: {Cadence.TestSupport.FakeProviderClient, :secret_backend}
  ],
  ground_network_provider_live_opts: [
    client: Cadence.TestSupport.FakeProviderClient,
    credential_resolver: {Cadence.TestSupport.FakeProviderClient, :resolve_credential}
  ]

config :cadence_web, dashboard_live_refresh_ms: 60_000

config :cadence_web,
  dashboard_engine_source_execution: [
    source_execution_max_concurrency: 1,
    source_execution_timeout_ms: :infinity
  ]
