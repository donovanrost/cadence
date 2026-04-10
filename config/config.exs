import Config

config :phoenix, :json_library, Jason
config :swoosh, :api_client, false

config :cadence,
  ecto_repos: [Cadence.Repo],
  start_background_jobs: true,
  ingress_archive: [
    module: Cadence.IngressArchive.FileSystem,
    base_path: Path.expand("../var/ingress_archive", __DIR__),
    flush_interval_ms: 250,
    flush_count: 100
  ],
  protocol_record_archive: [
    module: Cadence.Protocol.RecordArchive.FileSystem,
    base_path: Path.expand("../var/protocol_record_archive", __DIR__),
    flush_interval_ms: 250,
    flush_count: 250
  ],
  telemetry_current_value_store: [module: Cadence.Telemetry.CurrentValueStore.ETS],
  telemetry_history_store: [module: Cadence.Telemetry.HistoryStore.Noop],
  contact_scheduler: [enabled: true, poll_interval_ms: 1_000],
  command_dispatcher: [
    enabled: true,
    poll_interval_ms: 1_000,
    lane_poll_interval_ms: 250
  ],
  bootstrap_admin: [enabled: false],
  command_verifier_scheduler: [enabled: true, poll_interval_ms: 1_000],
  catalog_importers: [Cadence.Catalog.Importers.CadenceYamlDatabase],
  generators: [timestamp_type: :utc_datetime_usec]

config :cadence_web, CadenceWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CadenceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CadenceWeb.PubSub,
  secret_key_base: String.duplicate("0", 64)

config :cadence_web, CadenceWeb.Mailer, adapter: Swoosh.Adapters.Local

config :tailwind,
  version: "4.0.9",
  cadence_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/cadence_web", __DIR__)
  ]

config :esbuild,
  version: "0.21.5",
  cadence_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/cadence_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../apps/cadence_web/deps", __DIR__)}
  ]

import_config "#{config_env()}.exs"
