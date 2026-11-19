defmodule Cadence.Repo.Migrations.ContactPlanOperations do
  use Ecto.Migration

  # #257 (director 11-19): every console submit and approve of a contact plan records its
  # operation, written in the same transaction as the action, so a retry of the same request
  # (same actor, same normalized body) gets the original answer back and a different request on
  # the same operation id is refused. Additive: a new table, no backfill. The plan row's own
  # operation_id is no longer written.
  def change do
    create table(:contact_plan_operations, primary_key: false) do
      add(:contact_plan_operation_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:operation_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:action, :string, null: false)
      add(:actor_id, :string, null: false)
      add(:request_sha256, :string, null: false)
      add(:response_status, :integer, null: false)
      add(:response_document, :map, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:contact_plan_operations, [:organization_id, :mission_id, :operation_id],
        name: :contact_plan_operations_scope_index
      )
    )
  end
end
