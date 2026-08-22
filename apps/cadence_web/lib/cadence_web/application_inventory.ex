defmodule CadenceWeb.ApplicationInventory do
  @moduledoc """
  Application-host adapter that resolves package contributions before building
  the shared lifecycle and status inventory projection.
  """

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications.Inventory
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftTypeStore

  @spec catalog(Scope.t(), HostContext.t()) :: {:ok, list()} | {:error, term()}
  def catalog(%Scope{} = current_scope, %HostContext{placement: placement} = host_context) do
    definitions = ExtensionCatalog.available_applications_for_scope(placement)
    Inventory.catalog(current_scope, host_context, definitions)
  end

  @spec declared(Scope.t(), HostContext.t(), map()) :: {:ok, list()} | {:error, term()}
  def declared(
        %Scope{} = current_scope,
        %HostContext{placement: placement} = host_context,
        declarations
      )
      when is_map(declarations) do
    definitions = ExtensionCatalog.applications_for_scope(placement)
    Inventory.declared(current_scope, host_context, declarations, definitions)
  end

  def declared(%Scope{}, %HostContext{}, _declarations),
    do: {:error, :invalid_application_declarations}

  @doc """
  Builds the application inventory for a spacecraft from its exact pinned
  profile plus any retained application installations.
  """
  @spec spacecraft(Scope.t(), Spacecraft.t()) :: {:ok, list()} | {:error, term()}
  def spacecraft(%Scope{} = current_scope, %Spacecraft{} = spacecraft) do
    host_context = HostContext.spacecraft(spacecraft.mission_id, spacecraft.spacecraft_id)
    declarations = spacecraft_declarations(current_scope, spacecraft)

    declared(current_scope, host_context, declarations)
  end

  defp spacecraft_declarations(
         %Scope{organization_id: organization_id},
         %Spacecraft{
           mission_id: mission_id,
           spacecraft_type_id: spacecraft_type_id,
           spacecraft_type_version: spacecraft_type_version
         }
       )
       when is_binary(organization_id) and is_binary(spacecraft_type_id) and
              is_integer(spacecraft_type_version) and spacecraft_type_version > 0 do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           organization_id,
           mission_id,
           spacecraft_type_id,
           spacecraft_type_version
         ) do
      {:ok, spacecraft_type} -> spacecraft_type.applications
      {:error, _reason} -> %{}
    end
  end

  defp spacecraft_declarations(%Scope{}, %Spacecraft{}), do: %{}
end
