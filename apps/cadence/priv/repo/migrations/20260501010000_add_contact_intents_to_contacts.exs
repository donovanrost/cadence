defmodule Cadence.Repo.Migrations.AddContactIntentsToContacts do
  use Ecto.Migration

  def change do
    alter table(:scheduled_contacts) do
      add(:contact_intents, {:array, :string}, null: false, default: [])
    end

    alter table(:realized_contacts) do
      add(:contact_intents, {:array, :string}, null: false, default: [])
    end
  end
end
