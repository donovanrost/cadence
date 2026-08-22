defmodule Cadence.Applications.MissionBindingComposer do
  @moduledoc "Composes typed application contributions into one mission runtime basis."

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.MissionBindingContribution
  alias Cadence.Governance

  @spec binding_set_id(binary()) :: binary()
  def binding_set_id(mission_id) when is_binary(mission_id),
    do: "mission_applications:" <> mission_id

  @spec compose(binary(), binary(), [MissionBindingContribution.t()]) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def compose(organization_id, mission_id, contributions)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(contributions) do
    contribution_ids = Enum.map(contributions, &contribution_id/1)

    with true <- Enum.all?(contributions, &(MissionBindingContribution.validate(&1) == :ok)),
         true <- length(Enum.uniq(contribution_ids)) == length(contribution_ids),
         {:ok, capability_instances} <- unique_capability_instances(contributions),
         {:ok, rules} <- unique_rules(contributions) do
      {:ok,
       BindingSet.new(%{
         binding_set_id: binding_set_id(mission_id),
         organization_id: organization_id,
         mission_id: mission_id,
         version: next_version(organization_id, mission_id),
         capability_instances: Enum.sort_by(capability_instances, & &1.capability_instance_id),
         rules: Enum.sort_by(rules, & &1.binding_rule_id)
       })}
    else
      false -> {:error, :invalid_mission_binding_contributions}
      {:error, reason} -> {:error, reason}
    end
  end

  defp unique_capability_instances(contributions) do
    instances = Enum.flat_map(contributions, & &1.capability_instances)
    ids = Enum.map(instances, & &1.capability_instance_id)

    if length(Enum.uniq(ids)) == length(ids),
      do: {:ok, instances},
      else: {:error, :duplicate_mission_capability_instance}
  end

  defp unique_rules(contributions) do
    rules = Enum.flat_map(contributions, & &1.rules)
    ids = Enum.map(rules, & &1.binding_rule_id)

    if length(Enum.uniq(ids)) == length(ids),
      do: {:ok, rules},
      else: {:error, :duplicate_mission_binding_rule}
  end

  defp next_version(organization_id, mission_id) do
    case Governance.fetch_latest_binding_set(
           organization_id,
           mission_id,
           binding_set_id(mission_id)
         ) do
      {:ok, %{version: version}} -> version + 1
      {:error, :binding_set_not_found} -> 1
    end
  end

  defp contribution_id(%MissionBindingContribution{contribution_id: id}), do: id
  defp contribution_id(_contribution), do: nil
end
