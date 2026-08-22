defmodule Cadence.Repo.Migrations.CreateGovernedCapabilityInstances do
  use Ecto.Migration

  def change do
    create table(:governed_capability_instances) do
      add :binding_set_row_id, references(:governed_binding_sets, on_delete: :delete_all), null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :target_scope, :string, null: false
      add :source_endpoint_ref, :string
      add :lifecycle_state, :string, null: false, default: "active"
      add :capability_config_type, :string, null: false, default: "none"
      add :capability_config_document, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:governed_capability_instances, [:capability_instance_id])
    create index(:governed_capability_instances, [:binding_set_row_id])

    alter table(:governed_binding_rules) do
      add :capability_instance_id, :string, null: false, default: ""
    end

    create index(
             :governed_binding_rules,
             [:binding_set_row_id, :capability_instance_id],
             name: :governed_binding_rules_instance_idx
           )
  end
end
