defmodule Cadence.Repo.Migrations.ServiceIdentityAccountables do
  use Ecto.Migration

  # #280 (director 11-19): a service identity's act counts, for separation of duties, as the act of
  # every person accountable for it: whoever issued it, whoever rotated its credential, and whoever
  # an organization admin later records as accountable (that admin included). Each row is one such
  # actor, written by the server in the same transaction as the issue, rotation or attribution.
  # An actor is a person (user_id) or another service (by_service_identity_id), resolved
  # transitively. Additive: a new table, no backfill (DECISIONS #112: the dev reset recreates the
  # identities).
  def change do
    create table(:service_identity_accountables, primary_key: false) do
      add(:accountable_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)

      add(
        :service_identity_id,
        references(:service_identities, column: :service_identity_id, type: :string),
        null: false
      )

      add(:event, :string, null: false)
      add(:actor_kind, :string, null: false)
      add(:user_id, :string)
      add(:by_service_identity_id, :string)
      add(:recorded_by_user_id, :string)
      add(:recorded_at, :utc_datetime_usec, null: false)
    end

    create(index(:service_identity_accountables, [:organization_id, :service_identity_id]))

    create(
      constraint(:service_identity_accountables, :service_identity_accountables_event,
        check: "event IN ('issued', 'rotated', 'attributed')"
      )
    )

    create(
      constraint(:service_identity_accountables, :service_identity_accountables_actor,
        check:
          "(actor_kind = 'user' AND user_id IS NOT NULL AND by_service_identity_id IS NULL) OR " <>
            "(actor_kind = 'service' AND by_service_identity_id IS NOT NULL AND user_id IS NULL)"
      )
    )
  end
end
