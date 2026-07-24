defmodule CadenceWeb.API.CatalogJSON do
  @moduledoc "Catalog and governed activation response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON, as: LegacyJSON

  defdelegate packet_definition(value), to: LegacyJSON
  defdelegate catalog_importer(value), to: LegacyJSON
  defdelegate catalog_artifact(value), to: LegacyJSON
  defdelegate catalog_import_run(value), to: LegacyJSON
  defdelegate catalog_telemetry_snapshot_summary(value), to: LegacyJSON
  defdelegate catalog_telemetry_snapshot(value), to: LegacyJSON
  defdelegate catalog_command_snapshot_summary(value), to: LegacyJSON
  defdelegate catalog_command_snapshot(value), to: LegacyJSON
  defdelegate catalog_telemetry_recompile_result(value), to: LegacyJSON
  defdelegate catalog_telemetry_runtime_diff(value), to: LegacyJSON
  defdelegate catalog_telemetry_materialization_result(value), to: LegacyJSON
  defdelegate catalog_command_compile_result(snapshot, result), to: LegacyJSON
  defdelegate binding_set(value), to: LegacyJSON
end
