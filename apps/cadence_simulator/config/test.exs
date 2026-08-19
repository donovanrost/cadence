import Config

# Simulator integration tests intentionally exercise a real Cadence runtime.
# Load its complete test configuration so Cadence dependencies are validated
# against the same compile-time environment as workspace-root invocations.
import_config "../../../config/config.exs"

config :cadence_simulator,
  provider_http: [enabled: false],
  provider_store: [
    path:
      Path.join(
        System.tmp_dir!(),
        "cadence_simulator_provider_test_#{System.get_env("MIX_TEST_PARTITION", "0")}.dets"
      )
  ]
