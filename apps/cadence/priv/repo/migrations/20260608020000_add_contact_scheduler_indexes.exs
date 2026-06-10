defmodule Cadence.Repo.Migrations.AddContactSchedulerIndexes do
  use Ecto.Migration

  def change do
    create(
      index(:scheduled_contacts, [:starts_at, :scheduled_contact_id],
        name: :scheduled_contacts_scheduler_due_idx,
        where: "lifecycle_state = 'scheduled'"
      )
    )

    create(
      index(:scheduled_contacts, [:ends_at, :scheduled_contact_id],
        name: :scheduled_contacts_scheduler_expired_idx,
        where: "lifecycle_state = 'scheduled' AND ends_at IS NOT NULL"
      )
    )

    create(
      index(:scheduled_contacts, [:ends_at, :scheduled_contact_id],
        name: :scheduled_contacts_scheduler_completed_idx,
        where: "lifecycle_state = 'realized' AND ends_at IS NOT NULL"
      )
    )

    create(
      index(:realized_contacts, [:realized_at, :realized_contact_id],
        name: :realized_contacts_scheduler_active_idx,
        where: "lifecycle_state = 'active'"
      )
    )

    create(
      index(:realized_contacts, [:mission_id, :scheduled_contact_id, :realized_contact_id],
        name: :realized_contacts_scheduler_active_schedule_idx,
        where: "lifecycle_state = 'active' AND scheduled_contact_id IS NOT NULL"
      )
    )
  end
end
