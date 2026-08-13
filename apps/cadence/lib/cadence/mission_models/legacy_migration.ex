defmodule Cadence.MissionModels.LegacyMigration do
  @moduledoc """
  Transitional adapter that reads the legacy semantic stores and composes their
  definitions into an immutable Mission Model revision.
  """

  alias Cadence.Catalog.MissionModel.{CompilerResult, Revision}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.LegacyConverter

  @spec convert(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, CompilerResult.t()} | {:error, term()}
  def convert(organization_id, mission_id, base_revision_id, actor, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(base_revision_id) and is_map(actor) and is_list(opts) do
    with {:ok, %Revision{} = revision} <-
           MissionModels.fetch_revision(organization_id, mission_id, base_revision_id),
         {:ok, base_layers} <- fetch_base_layers(organization_id, mission_id, revision.layer_ids),
         derived_definitions <- Cadence.Governance.list_derived_definitions(mission_id),
         limit_definitions <- Cadence.Limits.list_limit_definitions(mission_id),
         {:ok, authored_layer, diagnostics} <-
           LegacyConverter.convert(revision, derived_definitions, limit_definitions,
             actor: actor,
             name: Keyword.get(opts, :name, "Legacy semantic definitions conversion")
           ),
         :ok <- require_success(diagnostics) do
      MissionModels.compile_layers(base_layers ++ [authored_layer],
        metadata: %{
          "conversion" => "cadence_legacy_semantics_v1",
          "base_revision_id" => base_revision_id
        }
      )
    end
  end

  defp fetch_base_layers(organization_id, mission_id, layer_ids) do
    Enum.reduce_while(layer_ids, {:ok, []}, fn layer_id, {:ok, layers} ->
      case MissionModels.fetch_layer(organization_id, mission_id, layer_id) do
        {:ok, layer} -> {:cont, {:ok, layers ++ [layer]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp require_success(diagnostics) do
    case Enum.filter(diagnostics, &(&1.severity == :error)) do
      [] -> :ok
      errors -> {:error, {:legacy_semantic_conversion_failed, errors}}
    end
  end
end
