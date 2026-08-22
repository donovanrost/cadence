defmodule Cadence.Applications.OpsDock do
  @moduledoc "Resolves installed application surface declarations eligible for the Ops Dock."

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    OpsDockSurface,
    Registry,
    SurfaceDefinition
  }

  alias Cadence.Auth.Scope

  @spec list(Scope.t(), binary()) :: {:ok, [OpsDockSurface.t()]} | {:error, term()}
  def list(%Scope{} = current_scope, mission_id) when is_binary(mission_id) do
    with {:ok, installations} <-
           ApplicationInstallations.list_for_mission(current_scope, mission_id,
             lifecycle_state: :installed
           ) do
      surfaces =
        installations
        |> Enum.flat_map(&installation_surfaces/1)
        |> Enum.sort_by(&{&1.order, &1.application_name, &1.id})

      {:ok, surfaces}
    end
  end

  defp installation_surfaces(%ApplicationInstallation{} = installation) do
    case Registry.fetch_available(
           installation.application_key,
           installation.application_version
         ) do
      {:ok, %ApplicationDefinition{} = definition} ->
        definition
        |> Registry.ops_dock_surfaces(installation.scope_kind)
        |> Enum.map(&dock_surface(installation, definition, &1))

      {:error, _reason} ->
        []
    end
  end

  defp dock_surface(
         %ApplicationInstallation{} = installation,
         %ApplicationDefinition{} = definition,
         %SurfaceDefinition{} = surface
       ) do
    %OpsDockSurface{
      id: "#{installation.application_installation_id}:#{surface.surface_id}",
      application_key: definition.application_key,
      application_name: definition.display_name,
      application_installation: installation,
      surface_definition: surface,
      label: Map.get(surface.navigation, :label, definition.display_name),
      order: Map.get(surface.navigation, :order, 0)
    }
  end
end
