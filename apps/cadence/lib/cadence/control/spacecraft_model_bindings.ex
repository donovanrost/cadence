defmodule Cadence.Control.SpacecraftModelBindings do
  @moduledoc "Admits the exact model assigned to each spacecraft in an activation generation."

  alias Cadence.Catalog
  alias Cadence.Catalog.SpacecraftModelBindings, as: ModelBindings
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.MissionModels
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  def validate(organization_id, mission_id, metadata) do
    with {:ok, entries} <- ModelBindings.entries(metadata) do
      Enum.reduce_while(entries, :ok, fn {spacecraft_id, entry}, :ok ->
        validate_entry(organization_id, mission_id, spacecraft_id, entry)
      end)
    end
  end

  defp validate_entry(organization_id, mission_id, spacecraft_id, entry) do
    with {:ok, _spacecraft} <-
           SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id),
         {:ok, catalog} <-
           Catalog.fetch_revision(organization_id, mission_id, entry["catalog_revision_id"]),
         true <- catalog.mission_model_revision_id == entry["mission_model"]["revision_id"],
         :ok <- validate_endpoints(organization_id, mission_id, spacecraft_id, entry),
         {:ok, _basis} <-
           MissionModelPromotion.runtime_basis(
             organization_id,
             mission_id,
             entry["mission_model"]
           ) do
      {:cont, :ok}
    else
      false -> {:halt, {:error, :spacecraft_catalog_model_mismatch}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  def runtime_basis(activation) do
    with {:ok, entries} <- ModelBindings.entries(activation.metadata),
         {:ok, bases} <- resolve_entries(activation, entries) do
      # The complete source map is part of the receiver's runtime identity. A
      # partition must select its own entry before executing any model plan.
      [{_endpoint, first} | _] = Enum.sort(bases)
      {:ok, Map.put(first, :source_runtime_bases, bases)}
    end
  end

  def runtime_basis(activation, source_endpoint_id) do
    with {:ok, entry} <- ModelBindings.entry_for_source(activation.metadata, source_endpoint_id) do
      MissionModelPromotion.runtime_basis(%{activation | metadata: entry})
    end
  end

  def command_basis(activation, source_endpoint_id) do
    with {:ok, entry} <- command_entry(activation.metadata, source_endpoint_id),
         true <- entry["commanding_enabled"] do
      MissionModels.command_authoring_basis(
        activation.organization_id,
        activation.mission_id,
        entry["mission_model"]
      )
    else
      false -> {:error, :spacecraft_commanding_not_active}
      {:error, reason} -> {:error, reason}
    end
  end

  defp commanding_entry?({_id, entry}), do: entry["commanding_enabled"]

  defp command_entry(metadata, nil) do
    with {:ok, entries} <- ModelBindings.entries(metadata) do
      case entries
           |> Enum.sort()
           |> Enum.find(&commanding_entry?/1) do
        {_id, entry} -> {:ok, entry}
        nil -> {:error, :spacecraft_commanding_not_active}
      end
    end
  end

  defp command_entry(metadata, source), do: ModelBindings.entry_for_source(metadata, source)

  defp resolve_entries(activation, entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {_id, entry}, {:ok, bases} ->
      case MissionModelPromotion.runtime_basis(%{activation | metadata: entry}) do
        {:ok, basis} ->
          additions = Map.new(entry["source_endpoint_ids"], &{&1, basis})
          {:cont, {:ok, Map.merge(bases, additions)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_endpoints(organization_id, mission_id, spacecraft_id, entry) do
    Enum.reduce_while(entry["source_endpoint_ids"], :ok, fn id, :ok ->
      case SourceEndpoints.fetch_source_endpoint(organization_id, mission_id, id) do
        {:ok, %{spacecraft_id: ^spacecraft_id}} -> {:cont, :ok}
        _ -> {:halt, {:error, :spacecraft_model_source_mismatch}}
      end
    end)
  end
end
