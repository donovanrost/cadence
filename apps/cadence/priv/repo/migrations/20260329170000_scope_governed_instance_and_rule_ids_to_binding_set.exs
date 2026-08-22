defmodule Cadence.Repo.Migrations.ScopeGovernedInstanceAndRuleIdsToBindingSet do
  use Ecto.Migration

  def change do
    drop_if_exists index(:governed_capability_instances, [:capability_instance_id])
    drop_if_exists index(:governed_binding_rules, [:binding_rule_id])

    create unique_index(
             :governed_capability_instances,
             [:binding_set_row_id, :capability_instance_id],
             name: :governed_capability_instances_binding_set_instance_idx
           )

    create unique_index(
             :governed_binding_rules,
             [:binding_set_row_id, :binding_rule_id],
             name: :governed_binding_rules_binding_set_rule_idx
           )
  end
end
