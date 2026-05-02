defmodule Cadence.Repo.Migrations.AddLinkAssignmentRefsToScheduledContacts do
  use Ecto.Migration

  def change do
    alter table(:scheduled_contacts) do
      add(:link_assignment_ref_documents, :map, null: false, default: %{"items" => []})
    end
  end
end
