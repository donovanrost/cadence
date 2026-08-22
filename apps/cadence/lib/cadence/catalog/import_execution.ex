defmodule Cadence.Catalog.ImportExecution do
  @moduledoc """
  Cadence-owned persistence and runtime projection for portable catalog import
  results.
  """

  alias Cadence.Catalog.ImportResult

  alias Cadence.Catalog.Diagnostic
  alias Cadence.Catalog.MissionModel.CompilerResult, as: MissionModelCompilerResult
  alias Cadence.MissionModels

  @type outcome :: %{
          imported_definition_count: non_neg_integer(),
          diagnostics: list(),
          result_document: map()
        }

  @spec persist(binary(), binary(), ImportResult.t()) :: {:ok, outcome()} | {:error, term()}
  def persist(organization_id, import_run_id, %ImportResult{} = import_result)
      when is_binary(organization_id) and is_binary(import_run_id) do
    with :ok <- require_declaration_layers(import_result),
         {:ok, mission_model_result} <-
           MissionModels.compile_layers(import_result.bundle.declaration_layers) do
      {:ok,
       %{
         imported_definition_count: import_result.imported_definition_count,
         diagnostics:
           import_result.diagnostics ++ mission_model_diagnostics(mission_model_result),
         result_document:
           import_result.metadata
           |> Map.put("import_run_id", import_run_id)
           |> Map.put("mission_model", mission_model_document(mission_model_result))
       }}
    end
  end

  defp require_declaration_layers(%ImportResult{bundle: %{declaration_layers: [_ | _]}}), do: :ok

  defp require_declaration_layers(%ImportResult{}),
    do: {:error, :mission_model_declaration_layer_required}

  defp mission_model_diagnostics(%MissionModelCompilerResult{} = result) do
    result
    |> all_mission_model_diagnostics()
    |> Enum.map(fn diagnostic ->
      Diagnostic.new(%{
        severity: diagnostic.severity,
        code: diagnostic.code,
        message: diagnostic.message,
        path: [],
        metadata: %{
          "stage" => Atom.to_string(diagnostic.stage),
          "target" => atom_string(diagnostic.target),
          "semantic_id" => diagnostic.semantic_id,
          "support" => atom_string(diagnostic.support)
        }
      })
    end)
  end

  defp all_mission_model_diagnostics(%MissionModelCompilerResult{} = result) do
    target_diagnostics =
      result.plans
      |> Enum.sort_by(fn {target, _plan} -> target end)
      |> Enum.flat_map(fn {_target, plan} -> plan.diagnostics end)

    Enum.uniq_by(result.revision.diagnostics ++ target_diagnostics, fn diagnostic ->
      {diagnostic.code, diagnostic.stage, diagnostic.target, diagnostic.semantic_id,
       diagnostic.message}
    end)
  end

  defp mission_model_document(%MissionModelCompilerResult{} = result) do
    %{
      "revision_id" => result.revision.revision_id,
      "content_sha256" => result.revision.content_sha256,
      "layer_ids" => result.revision.layer_ids,
      "declaration_count" => map_size(result.revision.declarations),
      "diagnostic_count" => length(all_mission_model_diagnostics(result)),
      "plans" =>
        Map.new(result.plans, fn {target, plan} ->
          {Atom.to_string(target),
           %{
             "plan_id" => plan.plan_id,
             "status" => Atom.to_string(plan.status),
             "target_contract_version" => plan.target_contract_version,
             "content_sha256" => plan.content_sha256
           }}
        end)
    }
  end

  defp atom_string(nil), do: nil
  defp atom_string(value), do: Atom.to_string(value)
end
