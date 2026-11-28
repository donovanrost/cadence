import Config

config :cadence, :organization_invitation_delivery, CadenceWeb.UserNotifier

# The web application is the Cadence server composition root. Load the core
# application's owned defaults before applying web and release-specific policy.
import_config "../../cadence/config/config.exs"

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ~w(password secret token csr_pem certificate_pem private_key)
config :swoosh, :api_client, false

config :cadence_web, CadenceWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CadenceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CadenceWeb.PubSub,
  secret_key_base: String.duplicate("0", 64)

config :cadence_web, CadenceWeb.Mailer, adapter: Swoosh.Adapters.Local

config :cadence_web, :admin_mode_ttl_seconds, 3_600

config :cadence_web, :frontend_release_publication,
  trust_records: [],
  allowed_origins: []

config :cadence_web, :frontend_release_publisher, token_sha256: nil

import_config "#{config_env()}.exs"
