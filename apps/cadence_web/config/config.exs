import Config

# The web application is the Cadence server composition root. Load the core
# application's owned defaults before applying web and release-specific policy.
import_config "../../cadence/config/config.exs"

config :phoenix, :json_library, Jason
config :swoosh, :api_client, false

config :cadence_web, CadenceWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CadenceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CadenceWeb.PubSub,
  secret_key_base: String.duplicate("0", 64),
  live_view: [signing_salt: "cadence-live-view"]

config :cadence_web, CadenceWeb.Mailer, adapter: Swoosh.Adapters.Local

config :cadence_web, dashboard_live_refresh_ms: 1_000
config :cadence_web, :admin_mode_ttl_seconds, 3_600

config :tailwind,
  version: "4.1.12",
  cadence_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :esbuild,
  version: "0.21.5",
  cadence_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

import_config "#{config_env()}.exs"
