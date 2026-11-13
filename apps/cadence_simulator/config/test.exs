import Config

# Simulator integration tests intentionally exercise a real Cadence runtime.
# Load the core application's owned test configuration explicitly. Simulator
# production configuration remains independent from Cadence.
import_config "../../cadence/config/config.exs"

config :cadence_simulator,
  provider_http: [enabled: false],
  # provider_store.path is per partition: set in runtime.exs (#50).
  provider_store: []
