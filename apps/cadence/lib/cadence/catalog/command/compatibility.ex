defmodule Cadence.Catalog.Command.Compatibility do
  @moduledoc "Exact command semantics used to admit shared preparation across spacecraft models."
  alias Cadence.Platform.ContentHash

  def fingerprint(catalog, command_id, argument_choices \\ %{}) do
    definition = Enum.find(catalog.runtime_definitions, &(&1.command_id == command_id))
    binding = Enum.find(catalog.operational_bindings, &(&1.command_id == command_id))

    if definition && binding do
      # The model identity differs by spacecraft; every encoding, argument,
      # operational policy, constraint and verifier still has to match.
      {:ok,
       ContentHash.term_sha256(
         {definition
          |> Map.delete(:mission_model_revision_id)
          |> Map.update!(:metadata, &Map.delete(&1, "mission_model_revision_id")), binding,
          Enum.filter(catalog.constraint_plans, &(&1.command_id == command_id)),
          Enum.filter(catalog.verifier_plans, &(&1.command_id == command_id)), argument_choices}
       )}
    else
      {:error, :command_not_in_spacecraft_catalog}
    end
  end
end
