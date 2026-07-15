import Config

config :cadence_simulator,
  provider_http: [enabled: false, ip: {127, 0, 0, 1}, port: 4101],
  provider_admin_api_token: nil,
  provider_api_token: nil,
  provider_auth_required: false,
  provider_store: [
    path: Path.expand("../../../var/cadence_simulator_provider.dets", __DIR__)
  ],
  provider_defaults: [definitions_path: nil]

import_config Path.expand("#{config_env()}.exs", __DIR__)
