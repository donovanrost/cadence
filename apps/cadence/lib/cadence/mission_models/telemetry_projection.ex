defmodule Cadence.MissionModels.TelemetryProjection do
  @moduledoc """
  Resolves an imported catalog revision to its native Mission Model telemetry plan.

  Catalog revisions are provenance for an import. The executable packet model is
  the immutable Mission Model revision and its telemetry target plan.
  """

  alias Cadence.Catalog.MissionModel.{Revision, RuntimePlan}
  alias Cadence.Catalog.Revision, as: CatalogRevision
  alias Cadence.MissionModels
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.Telemetry.PacketDefinition

  @type t :: %{
          catalog_revision: CatalogRevision.t(),
          mission_model_revision: Revision.t(),
          telemetry_plan: RuntimePlan.t(),
          packet_definitions: [PacketDefinition.t()]
        }

  @spec load(binary() | nil, binary(), CatalogRevision.t()) ::
          {:ok, t()} | {:error, term()}
  def load(organization_id, mission_id, %CatalogRevision{} = catalog_revision)
      when is_binary(mission_id) do
    with {:ok, revision_id} <- mission_model_revision_id(catalog_revision),
         {:ok, %Revision{} = revision} <-
           MissionModels.fetch_revision(organization_id, mission_id, revision_id),
         {:ok, plans} <-
           MissionModels.fetch_runtime_plans(organization_id, mission_id, revision_id),
         {:ok, packet_definitions} <-
           MissionModelPlanDecoder.telemetry_packet_definitions(plans) do
      {:ok,
       %{
         catalog_revision: catalog_revision,
         mission_model_revision: revision,
         telemetry_plan: Map.fetch!(plans, :telemetry),
         packet_definitions: packet_definitions
       }}
    end
  end

  @spec packet_definition(t(), binary()) ::
          {:ok, PacketDefinition.t()} | {:error, term()}
  def packet_definition(%{packet_definitions: definitions}, packet_definition_id)
      when is_binary(packet_definition_id) do
    case Enum.find(definitions, &(&1.packet_definition_id == packet_definition_id)) do
      %PacketDefinition{} = definition -> {:ok, definition}
      nil -> {:error, {:packet_binding_packets_not_in_revision, [packet_definition_id]}}
    end
  end

  defp mission_model_revision_id(%CatalogRevision{mission_model_revision_id: revision_id})
       when is_binary(revision_id) and revision_id != "",
       do: {:ok, revision_id}

  defp mission_model_revision_id(%CatalogRevision{}),
    do: {:error, :catalog_revision_missing_mission_model}
end
