defmodule Cadence.Applications.SpacecraftConfiguration.TelemetryDecomProjection do
  @moduledoc "Projects desired decom configuration and applied evidence without copying either."

  alias Cadence.Applications.SpacecraftConfiguration.Assignments
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Reads.MissionModels.ActiveBasis

  @doc "Reads the requested spacecraft configurations, or all configured heads in scope."
  @spec list(binary(), binary(), [binary()] | nil) :: [Config.t()]
  def list(org, mission, ids \\ nil) do
    rows =
      org
      |> heads(mission, ids)
      |> Enum.filter(&is_binary(&1.catalog_revision_id))
      |> Enum.sort_by(& &1.spacecraft_id)

    project(org, mission, rows)
  end

  defp heads(org, mission, nil), do: Assignments.list_latest(org, mission)

  defp heads(org, mission, ids),
    do: org |> Assignments.latest_many(mission, ids) |> Map.values()

  defp project(_org, _mission, []), do: []

  defp project(org, mission, rows) do
    fleet = ActiveBasis.applied_fleet(org, mission, Enum.map(rows, & &1.spacecraft_id))

    Enum.map(rows, &configuration(&1, fleet))
  end

  defp configuration(row, fleet) do
    attrs = %{
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      spacecraft_id: row.spacecraft_id,
      configuration_version: row.version,
      catalog_revision_id: row.catalog_revision_id,
      handled_apids: row.document["handled_apids"] || [],
      source_endpoint_id: row.source_endpoint_id,
      enabled: row.document["telemetry_enabled"] == true,
      updated_at: row.inserted_at
    }

    attrs
    |> Map.merge(applied(attrs, row.configuration_revision_id, fleet))
    |> Config.new()
  end

  defp applied(%{enabled: true, spacecraft_id: id}, revision, %{entries: entries} = fleet) do
    case entries[id] do
      %{"configuration_revision_id" => ^revision, "document" => %{"telemetry_enabled" => true}} ->
        %{
          applied_binding_set_id: fleet.activation.binding_set_id,
          applied_binding_set_version: fleet.activation.binding_set_version,
          applied_generation: fleet.activation.generation,
          applied_at: fleet.applied_at
        }

      _missing_or_different ->
        %{}
    end
  end

  defp applied(_attrs, _revision, _fleet), do: %{}
end
