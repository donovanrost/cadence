defmodule Cadence.Repo.Migrations.AddSelectorDocumentsToBindingRules do
  use Ecto.Migration

  def change do
    alter table(:governed_binding_rules) do
      add(:selector_scope, :map, null: false, default: %{})
      add(:selector_match, :map, null: false, default: %{})
    end
  end
end
