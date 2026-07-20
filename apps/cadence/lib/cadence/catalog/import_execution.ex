defmodule Cadence.Catalog.ImportExecution do
  @moduledoc """
  Cadence-owned persistence and runtime projection for portable catalog import
  results.
  """

  alias Cadence.Catalog.Command.Compiler, as: CommandCompiler
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult

  alias Cadence.Catalog.{
    ImportExecution.Persistence,
    ImportExecution.ResultBuilder,
    ImportResult
  }

  alias Cadence.Catalog.Telemetry.RuntimeArtifacts
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot

  @type outcome :: %{
          snapshot_id: binary() | nil,
          imported_definition_count: non_neg_integer(),
          diagnostics: list(),
          result_document: map()
        }

  @spec persist(binary(), binary(), ImportResult.t()) :: {:ok, outcome()} | {:error, term()}
  def persist(organization_id, import_run_id, %ImportResult{} = import_result)
      when is_binary(organization_id) and is_binary(import_run_id) do
    telemetry_snapshot = import_result.bundle.telemetry_snapshot
    command_snapshot = import_result.bundle.command_snapshot

    telemetry_runtime_artifacts = compile_telemetry(telemetry_snapshot)
    command_compiler_result = compile_commands(command_snapshot)

    with {:ok, persisted_telemetry_snapshot} <-
           Persistence.maybe_persist_telemetry_snapshot(organization_id, telemetry_snapshot),
         {:ok, binding_set} <-
           Persistence.maybe_persist_runtime_artifacts(
             persisted_telemetry_snapshot,
             import_run_id,
             telemetry_runtime_artifacts
           ),
         {:ok, persisted_command_snapshot} <-
           Persistence.maybe_persist_command_snapshot(organization_id, command_snapshot) do
      {:ok,
       %{
         snapshot_id:
           ResultBuilder.primary_snapshot_id(
             persisted_telemetry_snapshot,
             persisted_command_snapshot
           ),
         imported_definition_count: import_result.imported_definition_count,
         diagnostics:
           import_result.diagnostics ++
             ResultBuilder.telemetry_compiler_diagnostics(telemetry_runtime_artifacts) ++
             command_compiler_result.diagnostics,
         result_document:
           import_result.metadata
           |> Map.merge(
             ResultBuilder.build_document(
               import_run_id,
               persisted_telemetry_snapshot,
               telemetry_runtime_artifacts,
               binding_set,
               persisted_command_snapshot,
               command_compiler_result
             )
           )
       }}
    end
  end

  defp compile_telemetry(%TelemetrySnapshot{} = snapshot) do
    RuntimeArtifacts.compile(snapshot,
      packet_definition_version: 1,
      capability_family_key: :definition_bound_telemetry
    )
  end

  defp compile_telemetry(nil), do: nil

  defp compile_commands(%Cadence.Catalog.Command.Snapshot{} = snapshot),
    do: CommandCompiler.compile(snapshot)

  defp compile_commands(nil), do: CommandCompilerResult.new()
end
