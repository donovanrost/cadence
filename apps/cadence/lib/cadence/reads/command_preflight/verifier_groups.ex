defmodule Cadence.Reads.CommandPreflight.VerifierGroups do
  @moduledoc """
  U51 (ux, fe-ops): where a group's targets differ in what verifies a command. Each target's
  member is validated against its own pinned model (per-spacecraft basis), so targets on different
  catalog revisions can carry different verifiers for the same command (11-14: 001 on Revision 4
  has 'Mode applied' on SET_MODE, the other 499 on Revision 3 don't).

    * `catalog_revisions/3`: per target index, `%{number, label}` of the catalog revision its
      validated commands resolve to; nil when none validated (that target is a Catalog NO-GO).
    * `commands/3`: per stacked command, `verifier_groups`, one per distinct verifier definition
      set (compared without ids, which differ between revisions), largest first.
  """

  alias Cadence.Catalog

  @compared [
    :name,
    :phase,
    :timeout_ms,
    :delay_ms,
    :severity,
    :success_criteria,
    :failure_criteria
  ]

  @spec catalog_revisions(binary(), binary(), [map()]) :: %{non_neg_integer() => map() | nil}
  def catalog_revisions(org, mission, members) do
    labels = revision_labels(org, mission)

    members
    |> Enum.group_by(& &1.target_index, & &1.request.mission_model_revision_id)
    |> Map.new(fn {index, [revision | _]} -> {index, Map.get(labels, revision)} end)
  end

  @spec commands([map()], [map()], map(), map()) :: [map()]
  def commands(draft_commands, members, targets_by_index, revisions_by_index) do
    by_position = Enum.group_by(members, & &1.position)

    draft_commands
    |> Enum.with_index()
    |> Enum.map(fn {command, position} ->
      %{
        position: position,
        command_id: command.command_id,
        verifier_groups:
          by_position
          |> Map.get(position, [])
          |> groups(targets_by_index, revisions_by_index)
      }
    end)
  end

  defp groups(members, targets_by_index, revisions_by_index) do
    members
    |> Enum.group_by(&canonical(&1.verifier_plans))
    |> Enum.map(fn {_set, [first | _] = same} ->
      indexes = same |> Enum.map(& &1.target_index) |> Enum.uniq()

      %{
        verifiers: Enum.map(first.verifier_plans, &verifier/1),
        catalog_revisions:
          indexes
          |> Enum.map(&Map.get(revisions_by_index, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort_by(&{&1.number || 0, &1.label || ""}),
        spacecraft_ids:
          indexes
          |> Enum.map(&get_in(targets_by_index, [&1, :spacecraft_id]))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.sort()
      }
    end)
    |> Enum.sort_by(&{-length(&1.spacecraft_ids), List.first(&1.spacecraft_ids) || ""})
  end

  # The same verifiers on two revisions have different ids; compare what they check.
  defp canonical(plans), do: plans |> Enum.map(&Map.take(&1, @compared)) |> Enum.sort()

  defp verifier(plan) do
    %{
      id: plan.verifier_id,
      name: plan.name,
      description: plan.description,
      phase: plan.phase,
      timeout_ms: plan.timeout_ms,
      delay_ms: plan.delay_ms,
      severity: plan.severity
    }
  end

  defp revision_labels(org, mission) do
    org
    |> Catalog.list_revisions(mission)
    |> Enum.reject(&is_nil(&1.mission_model_revision_id))
    |> Map.new(fn revision ->
      {revision.mission_model_revision_id,
       %{number: revision.revision_number, label: revision.revision_label}}
    end)
  end
end
