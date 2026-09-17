defmodule Cadence.Reads.Applications.SpacecraftInventory do
  @moduledoc "Discovers spacecraft applications independently of optional protocol presets."

  alias Cadence.Applications.HostContext
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications.Inventory

  def load(scope, %HostContext{placement: :spacecraft} = host, declarations \\ %{}) do
    with {:ok, available} <-
           Inventory.catalog(
             scope,
             host,
             ExtensionCatalog.available_applications_for_scope(:spacecraft)
           ),
         {:ok, declared} <-
           Inventory.declared(
             scope,
             host,
             declarations,
             ExtensionCatalog.applications_for_scope(:spacecraft)
           ) do
      # Preserve unavailable declarations and retained installations so an operator
      # can still understand and repair them when a package is absent.
      {:ok,
       (available ++ declared)
       |> Map.new(&{&1.application_key, &1})
       |> Map.values()
       |> Enum.sort_by(&{&1.display_name, &1.application_key})}
    end
  end
end
