defmodule Cadence.Management.Commanding.SpacecraftCatalogs do
  @moduledoc "Target-specific model evidence and command compatibility for fleet authoring."
  alias Cadence.Catalog.Command.Compatibility, as: CommandCompatibility
  alias Cadence.Catalog.SpacecraftModelBindings
  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModels.ActiveBasis

  def load(
        %{activation: %{metadata: %{"spacecraft_configurations" => _} = metadata}} = snapshot,
        command_id
      ) do
    reference =
      if command_id == "",
        do: nil,
        else: fingerprint(snapshot, command_id)

    with {:ok, entries} <- SpacecraftModelBindings.entries(metadata) do
      entries
      |> Enum.sort()
      |> Enum.reduce_while({:ok, []}, fn {_id, entry}, {:ok, bases} ->
        append_target_basis(entry, bases, snapshot, command_id, reference)
      end)
    end
  end

  def load(_snapshot, _command_id), do: {:ok, nil}

  defp append_target_basis(entry, bases, snapshot, command_id, reference) do
    if entry["commanding_enabled"] do
      [source | _] = entry["source_endpoint_ids"]

      case ActiveBasis.for_target(snapshot, %{source_endpoint_id: source}) do
        {:ok, target} ->
          compatible =
            is_nil(reference) or
              (match?({:ok, _}, reference) and
                 reference == fingerprint(target, command_id))

          basis = %{
            "sources" => entry["source_endpoint_ids"],
            "revision_id" => target.basis.mission_model_revision_id,
            "plan_id" => target.catalog.plan_id,
            "compatible" => compatible
          }

          {:cont, {:ok, [basis | bases]}}

        error ->
          {:halt, error}
      end
    else
      {:cont, {:ok, bases}}
    end
  end

  defp fingerprint(snapshot, command_id) do
    case Enum.find(snapshot.catalog.runtime_definitions, &(&1.command_id == command_id)) do
      nil ->
        {:error, :command_not_in_spacecraft_catalog}

      definition ->
        ids =
          definition.argument_specs
          |> Enum.filter(&(&1.base_type == :enumerated))
          |> Enum.map(& &1.argument_id)

        with {:ok, choices} <-
               MissionModels.command_argument_choices(
                 snapshot.activation.organization_id,
                 snapshot.activation.mission_id,
                 definition.mission_model_revision_id,
                 ids
               ) do
          CommandCompatibility.fingerprint(snapshot.catalog, command_id, choices)
        end
    end
  end
end
