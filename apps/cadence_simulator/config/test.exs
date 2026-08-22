import Config

# Simulator integration tests intentionally exercise a real Cadence runtime.
# Load the core application's owned test configuration explicitly. Simulator
# production configuration remains independent from Cadence.
import_config "../../cadence/config/config.exs"

config :cadence_simulator,
  provider_http: [enabled: false],
  provider_store: [
    path:
      Path.join(
        System.tmp_dir!(),
        "cadence_simulator_provider_test_#{System.get_env("MIX_TEST_PARTITION", "0")}.dets"
      )
  ]
