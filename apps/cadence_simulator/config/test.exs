import Config

# Simulator integration tests intentionally exercise a real Cadence runtime.
# Production and development simulator configuration remain independent.
import_config "../../../config/job_handlers.exs"
import_config "../../../config/test.exs"

# The root test config contains overrides only. Keep the catalog importer
# registration required by simulator-to-Cadence integration tests explicit.
config :cadence_catalog,
  catalog_importers: [Cadence.Catalog.Importers.CadenceYamlDatabase]

config :cadence_simulator,
  provider_http: [enabled: false],
  provider_store: [
    path:
      Path.join(
        System.tmp_dir!(),
        "cadence_simulator_provider_test_#{System.get_env("MIX_TEST_PARTITION", "0")}.dets"
      )
  ]
