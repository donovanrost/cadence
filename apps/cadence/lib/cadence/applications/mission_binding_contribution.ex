defmodule Cadence.Applications.MissionBindingContribution do
  @moduledoc "Typed runtime contribution from installed application packet bindings."

  alias Cadence.ApplicationDispatch.{BindingRule, CapabilityInstance}

  @type t :: %__MODULE__{
          contribution_id: binary(),
          application_key: binary(),
          capability_instances: [CapabilityInstance.t()],
          rules: [BindingRule.t()],
          metadata: map()
        }

  @enforce_keys [:contribution_id, :application_key]
  defstruct [
    :contribution_id,
    :application_key,
    capability_instances: [],
    rules: [],
    metadata: %{}
  ]

  @spec validate(t()) :: :ok | {:error, :invalid_mission_binding_contribution}
  def validate(%__MODULE__{} = contribution) do
    capability_ids = Enum.map(contribution.capability_instances, &capability_id/1)
    rule_ids = Enum.map(contribution.rules, &rule_id/1)

    if valid_identity?(contribution) and
         valid_capability_instances?(contribution.capability_instances, capability_ids) and
         valid_rules?(contribution.rules, rule_ids) and is_map(contribution.metadata) do
      :ok
    else
      {:error, :invalid_mission_binding_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_mission_binding_contribution}

  defp valid_identity?(contribution),
    do: valid_text?(contribution.contribution_id) and valid_text?(contribution.application_key)

  defp valid_capability_instances?(instances, ids),
    do:
      is_list(instances) and Enum.all?(instances, &match?(%CapabilityInstance{}, &1)) and
        length(Enum.uniq(ids)) == length(ids)

  defp valid_rules?(rules, ids),
    do:
      is_list(rules) and Enum.all?(rules, &match?(%BindingRule{}, &1)) and
        length(Enum.uniq(ids)) == length(ids)

  defp capability_id(%CapabilityInstance{capability_instance_id: id}), do: id
  defp capability_id(_instance), do: nil
  defp rule_id(%BindingRule{binding_rule_id: id}), do: id
  defp rule_id(_rule), do: nil
  defp valid_text?(value), do: is_binary(value) and value != ""
end
