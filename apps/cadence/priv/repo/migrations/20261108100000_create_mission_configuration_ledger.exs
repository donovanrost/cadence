defmodule Cadence.Repo.Migrations.CreateMissionConfigurationLedger do
  use Ecto.Migration

  @mission_tables [
    :mission_config_heads,
    :mission_config_revisions,
    :mission_config_revision_entries,
    :mission_config_change_sets,
    :mission_config_changes,
    :mission_config_ops,
    :mission_config_reviews
  ]

  def up do
    create table(:mission_config_heads, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:revision_number, :integer, null: false)
      add(:revision_id, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create table(:mission_config_revisions, primary_key: false) do
      add(:revision_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:revision_number, :integer, null: false)
      add(:kind, :string, null: false)
      add(:change_set_id, :string)
      add(:rolls_back_to, :integer)
      add(:applied_by, :map, null: false, default: %{})
      add(:applied_at, :utc_datetime_usec, null: false)
      add(:reason, :text, null: false)
      add(:approvals, {:array, :map}, null: false, default: [])
      add(:summary, :text, null: false)
      add(:entry_count, :integer, null: false, default: 0)
      add(:activation_id, :string)
      add(:generation, :bigint)
      add(:content_sha256, :string)
    end

    create(
      unique_index(:mission_config_revisions, [:mission_id, :revision_number],
        name: :mission_config_revisions_number_idx
      )
    )

    create table(:mission_config_revision_entries, primary_key: false) do
      add(:entry_id, :string, primary_key: true)

      add(
        :revision_id,
        references(:mission_config_revisions,
          column: :revision_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:revision_number, :integer, null: false)
      add(:position, :integer, null: false)
      add(:kind, :string, null: false)
      add(:entity_id, :string, null: false)
      add(:op, :string, null: false)
      add(:before, :map)
      add(:after, :map)
      add(:paths, {:array, :string}, null: false, default: [])
    end

    create(index(:mission_config_revision_entries, [:revision_id]))

    create(
      index(:mission_config_revision_entries, [:mission_id, :kind, :entity_id, :revision_number],
        name: :mission_config_revision_entries_entity_idx
      )
    )

    create table(:mission_config_change_sets, primary_key: false) do
      add(:change_set_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:state, :string, null: false)
      add(:version, :integer, null: false, default: 1)
      add(:base_revision_number, :integer, null: false)
      add(:opened_by, :map, null: false, default: %{})
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:submitted_by, :map)
      add(:submitted_at, :utc_datetime_usec)
      add(:reason, :text)
      add(:policy_document, :map)
      add(:failure_document, :map)
      add(:applied_revision_number, :integer)
      add(:closed_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:mission_config_change_sets, [:mission_id],
        where: "state IN ('open', 'in_review')",
        name: :mission_config_change_sets_one_open_idx
      )
    )

    create(index(:mission_config_change_sets, [:mission_id, :state]))

    create table(:mission_config_changes, primary_key: false) do
      add(:change_id, :string, primary_key: true)

      add(
        :change_set_id,
        references(:mission_config_change_sets,
          column: :change_set_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:author, :map, null: false)
      add(:author_key, :string, null: false)
      add(:staged_at, :utc_datetime_usec, null: false)
      add(:summary, :text, null: false)
      add(:source, :map, null: false, default: %{})
      add(:state, :string, null: false)
      add(:position, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:mission_config_changes, [:change_set_id, :position]))

    create table(:mission_config_ops, primary_key: false) do
      add(:op_id, :string, primary_key: true)

      add(
        :change_id,
        references(:mission_config_changes,
          column: :change_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:change_set_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:position, :integer, null: false)
      add(:kind, :string, null: false)
      add(:entity_id, :string, null: false)
      add(:action, :string, null: false)
      add(:payload, :map, null: false, default: %{})
      add(:base, :map, null: false, default: %{})
      add(:touched_paths, {:array, :string}, null: false, default: [])
    end

    create(index(:mission_config_ops, [:change_id, :position]))
    create(index(:mission_config_ops, [:change_set_id, :kind, :entity_id]))

    create table(:mission_config_reviews, primary_key: false) do
      add(:review_id, :string, primary_key: true)

      add(
        :change_set_id,
        references(:mission_config_change_sets,
          column: :change_set_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:decision, :string, null: false)
      add(:actor, :map, null: false)
      add(:comment, :text, null: false)
      add(:decided_at, :utc_datetime_usec, null: false)
    end

    create(index(:mission_config_reviews, [:change_set_id]))

    for table <- @mission_tables do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_org_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      """)
    end
  end

  def down do
    drop(table(:mission_config_reviews))
    drop(table(:mission_config_ops))
    drop(table(:mission_config_changes))
    drop(table(:mission_config_change_sets))
    drop(table(:mission_config_revision_entries))
    drop(table(:mission_config_revisions))
    drop(table(:mission_config_heads))
  end
end
