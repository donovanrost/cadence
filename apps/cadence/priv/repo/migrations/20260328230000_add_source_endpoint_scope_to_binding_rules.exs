defmodule Cadence.Repo.Migrations.AddSourceEndpointScopeToBindingRules do
  use Ecto.Migration

  def change do
    alter table(:governed_binding_rules) do
      add(:source_endpoint_ref, :string)
    end

    create(index(:governed_binding_rules, [:binding_set_row_id, :source_endpoint_ref],
             name: :governed_binding_rules_source_endpoint_idx
           ))
  end
end
