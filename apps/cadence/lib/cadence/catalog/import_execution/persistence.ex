defmodule Cadence.Catalog.ImportExecution.Persistence do
  @moduledoc false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.Telemetry.RuntimeArtifacts
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot
  alias Cadence.Governance

  def maybe_persist_telemetry_snapshot(_organization_id, nil), do: {:ok, nil}

  def maybe_persist_telemetry_snapshot(organization_id, %TelemetrySnapshot{} = snapshot) do
    Catalog.persist_telemetry_snapshot(organization_id, snapshot)
  end

  def maybe_persist_command_snapshot(_organization_id, nil), do: {:ok, nil}

  def maybe_persist_command_snapshot(organization_id, %CommandSnapshot{} = snapshot) do
    Catalog.persist_command_snapshot(organization_id, snapshot)
  end

  def maybe_persist_runtime_artifacts(_snapshot, _import_run_id, nil), do: {:ok, nil}

  def maybe_persist_runtime_artifacts(
        %TelemetrySnapshot{} = snapshot,
        import_run_id,
        %{compiler_result: compiler_result}
      ) do
    persist_runtime_artifacts(snapshot, import_run_id, compiler_result)
  end

  defp persist_runtime_artifacts(
         %TelemetrySnapshot{organization_id: organization_id, mission_id: mission_id},
         _import_run_id,
         %{selector_inputs: [], packet_definitions: []}
       ) do
    if is_binary(organization_id) and is_binary(mission_id) do
      {:ok, nil}
    else
      {:error, :catalog_import_missing_scope}
    end
  end

  defp persist_runtime_artifacts(
         %TelemetrySnapshot{organization_id: organization_id, mission_id: mission_id} = snapshot,
         _import_run_id,
         compiler_result
       ) do
    if is_binary(organization_id) and is_binary(mission_id) do
      binding_set = compiled_binding_set(snapshot, compiler_result)

      case Governance.persist_binding_set(organization_id, binding_set) do
        {:ok, %BindingSet{} = persisted_binding_set} -> {:ok, persisted_binding_set}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :catalog_import_missing_scope}
    end
  end

  defp compiled_binding_set(%TelemetrySnapshot{} = snapshot, compiler_result) do
    RuntimeArtifacts.build_binding_set(snapshot, compiler_result)
  end
end
