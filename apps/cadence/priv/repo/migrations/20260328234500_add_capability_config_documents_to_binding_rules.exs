defmodule Cadence.Repo.Migrations.AddCapabilityConfigDocumentsToBindingRules do
  use Ecto.Migration

  def change do
    alter table(:governed_binding_rules) do
      add(:capability_config_type, :string, null: false, default: "none")
      add(:capability_config_document, :map, null: false, default: %{})
    end
  end
end
