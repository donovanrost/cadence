defmodule Mix.Tasks.Cadence.Extensions.Check do
  @moduledoc """
  Validates the complete compiled extension catalog and the application status
  providers, and prints the composed inventory.

  Unlike tolerant runtime discovery, this check fails when any compiled package
  is structurally invalid, has an unresolved typed contribution, duplicates a
  package identifier, duplicates contribution ownership, or leaves a declared
  application status query without exactly one valid provider binding.

  ## Usage

      mix cadence.extensions.check
  """

  use Mix.Task

  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications, as: ApplicationReads

  @shortdoc "Validate the compiled extension host contract"

  @impl true
  def run(args) do
    validate_args!(args)
    Mix.Task.run("compile")

    with :ok <- ExtensionCatalog.validate(),
         :ok <- ApplicationReads.validate_providers() do
      Mix.shell().info(summary(ExtensionCatalog.inventory()))
    else
      {:error, reason} ->
        Mix.raise("Compiled extension host contract is invalid: #{reason}.")
    end
  end

  defp validate_args!([]), do: :ok
  defp validate_args!(args), do: Mix.raise("Unexpected arguments: #{inspect(args)}")

  defp summary(inventory) do
    "Extension host integrity: " <>
      counted(inventory.packages, "package") <>
      "; " <>
      counted(inventory.applications, "application") <>
      " " <>
      "(#{inventory.available_applications} available); " <>
      counted(inventory.capabilities, "capability", "capabilities") <>
      "; " <>
      counted(inventory.transport_kinds, "transport kind") <>
      "; " <>
      counted(inventory.provider_connectors, "provider connector") <>
      "; " <>
      counted(inventory.widget_types, "widget type") <>
      "; " <>
      counted(inventory.source_adapters, "source adapter") <>
      "; " <>
      counted(inventory.catalog_importers, "catalog importer") <>
      "; status providers valid."
  end

  defp counted(1, singular, _plural), do: "1 #{singular}"
  defp counted(count, singular, nil), do: "#{count} #{singular}s"
  defp counted(count, _singular, plural), do: "#{count} #{plural}"
  defp counted(count, singular), do: counted(count, singular, nil)
end
