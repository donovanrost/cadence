defmodule CadenceWeb.API.CatalogParams do
  @moduledoc "Catalog and governed activation request parsing boundary."

  alias CadenceWeb.ControlPlaneParams, as: LegacyParams

  defdelegate packet_definition(organization_id, mission_id, params), to: LegacyParams
  defdelegate catalog_importer_filters(params), to: LegacyParams
  defdelegate catalog_artifact(organization_id, mission_id, params, opts \\ []), to: LegacyParams
  defdelegate catalog_artifact_filters(params), to: LegacyParams
  defdelegate catalog_import_run_request(params, opts \\ []), to: LegacyParams
  defdelegate catalog_import_run_filters(params), to: LegacyParams
  defdelegate catalog_telemetry_snapshot_filters(params), to: LegacyParams
  defdelegate catalog_command_snapshot_filters(params), to: LegacyParams
  defdelegate binding_set(organization_id, mission_id, params), to: LegacyParams
end
