defmodule Cadence.Repo.Migrations.AddDurableUserMembershipsAndInvitations do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:confirmed_at, :utc_datetime_usec)
    end

    create(index(:users, [:confirmed_at]))

    create table(:organization_memberships, primary_key: false) do
      add(:organization_membership_id, :string, primary_key: true)

      add(:user_id, references(:users, column: :user_id, type: :string, on_delete: :delete_all),
        null: false
      )

      add(
        :organization_id,
        references(:organizations,
          column: :organization_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:role, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:organization_memberships, [:user_id, :organization_id]))
    create(index(:organization_memberships, [:organization_id, :lifecycle_state]))
    create(index(:organization_memberships, [:user_id, :lifecycle_state]))

    create table(:organization_invitations, primary_key: false) do
      add(:organization_invitation_id, :string, primary_key: true)

      add(
        :organization_id,
        references(:organizations,
          column: :organization_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:email, :string, null: false)
      add(:display_name, :string)
      add(:membership_role, :string, null: false)
      add(:grant_platform_admin, :boolean, null: false, default: false)
      add(:status, :string, null: false)
      add(:token_digest, :string, null: false)
      add(:token_hint, :string, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)

      add(
        :invited_by_user_id,
        references(:users, column: :user_id, type: :string, on_delete: :nilify_all),
        null: false
      )

      add(
        :accepted_by_user_id,
        references(:users, column: :user_id, type: :string, on_delete: :nilify_all)
      )

      add(:accepted_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:organization_invitations, [:token_digest],
        name: :organization_invitations_token_digest_index
      )
    )

    create(index(:organization_invitations, [:organization_id, :status]))
    create(index(:organization_invitations, [:email, :status]))
    create(index(:organization_invitations, [:expires_at]))
  end
end
