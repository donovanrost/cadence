defmodule Cadence.Repo.Migrations.ReservationNextDueAt do
  @moduledoc """
  The reconciler polls by distance to the pass (domain 11-15, api-ops' review): `next_due_at`
  decides when a reservation is read next and is in no index, so a poll's write can be HOT.
  `last_reconciled_at` leaves the reconciliation index for the same reason; the index keeps the
  (organization, mission, lifecycle_state) prefix the lists use. fillfactor 85 leaves room on
  each page for HOT updates (existing pages get it from a VACUUM FULL in qa's slot).
  """
  use Ecto.Migration

  def up do
    alter table(:provider_reservations) do
      add(:next_due_at, :utc_datetime_usec)
    end

    drop(index(:provider_reservations, [], name: :provider_reservations_reconciliation_idx))

    create(
      index(:provider_reservations, [:organization_id, :mission_id, :lifecycle_state],
        name: :provider_reservations_reconciliation_idx
      )
    )

    execute("ALTER TABLE provider_reservations SET (fillfactor = 85)")
  end

  def down do
    execute("ALTER TABLE provider_reservations RESET (fillfactor)")
    drop(index(:provider_reservations, [], name: :provider_reservations_reconciliation_idx))

    create(
      index(
        :provider_reservations,
        [:organization_id, :mission_id, :lifecycle_state, :last_reconciled_at],
        name: :provider_reservations_reconciliation_idx
      )
    )

    alter table(:provider_reservations) do
      remove(:next_due_at)
    end
  end
end
