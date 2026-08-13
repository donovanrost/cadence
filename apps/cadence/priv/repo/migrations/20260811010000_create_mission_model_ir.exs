defmodule Cadence.Repo.Migrations.CreateMissionModelIr do
  use Ecto.Migration

  def change do
    create table(:mission_model_layers, primary_key: false) do
      add(:layer_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)
      add(:layer_kind, :string, null: false)
      add(:status, :string, null: false)
      add(:version, :integer, null: false)
      add(:name, :string, null: false)
      add(:content_sha256, :string, null: false)
      add(:declaration_count, :integer, null: false, default: 0)
      add(:source_document, :map, null: false, default: %{"value" => %{}})
      add(:layer_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:mission_model_layers, [:organization_id, :mission_id, :inserted_at]))
    create(unique_index(:mission_model_layers, [:mission_id, :content_sha256]))

    create table(:mission_model_revisions, primary_key: false) do
      add(:revision_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)
      add(:status, :string, null: false)
      add(:compiler_version, :string, null: false)
      add(:content_sha256, :string, null: false)
      add(:declaration_count, :integer, null: false, default: 0)
      add(:diagnostic_count, :integer, null: false, default: 0)
      add(:revision_document, :map, null: false, default: %{"value" => %{}})
      add(:approved_by, :map)
      add(:approved_at, :utc_datetime_usec)
      add(:rejected_by, :map)
      add(:rejected_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:mission_model_revisions, [:organization_id, :mission_id, :inserted_at]))
    create(unique_index(:mission_model_revisions, [:mission_id, :content_sha256]))

    create table(:mission_model_revision_layers, primary_key: false) do
      add(
        :revision_id,
        references(:mission_model_revisions,
          column: :revision_id,
          type: :string,
          on_delete: :delete_all
        ),
        primary_key: true
      )

      add(
        :layer_id,
        references(:mission_model_layers,
          column: :layer_id,
          type: :string,
          on_delete: :restrict
        ),
        primary_key: true
      )

      add(:position, :integer, null: false)
    end

    create(unique_index(:mission_model_revision_layers, [:revision_id, :position]))

    create table(:mission_model_diagnostics, primary_key: false) do
      add(:diagnostic_id, :string, primary_key: true)

      add(
        :revision_id,
        references(:mission_model_revisions,
          column: :revision_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:plan_id, :string)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:code, :string, null: false)
      add(:severity, :string, null: false)
      add(:stage, :string, null: false)
      add(:target, :string)
      add(:semantic_id, :string)
      add(:support, :string)
      add(:diagnostic_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:mission_model_diagnostics, [:revision_id, :severity]))
    create(index(:mission_model_diagnostics, [:organization_id, :mission_id, :code]))

    create table(:mission_model_runtime_plans, primary_key: false) do
      add(:plan_id, :string, primary_key: true)

      add(
        :revision_id,
        references(:mission_model_revisions,
          column: :revision_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:target, :string, null: false)
      add(:target_contract_version, :string, null: false)
      add(:compiler_version, :string, null: false)
      add(:status, :string, null: false)
      add(:content_sha256, :string, null: false)
      add(:plan_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:mission_model_runtime_plans, [:revision_id, :target]))
    create(index(:mission_model_runtime_plans, [:organization_id, :mission_id, :target]))

    alter table(:catalog_revisions) do
      add(
        :mission_model_layer_id,
        references(:mission_model_layers, column: :layer_id, type: :string)
      )

      add(
        :mission_model_revision_id,
        references(:mission_model_revisions, column: :revision_id, type: :string)
      )
    end

    create(index(:catalog_revisions, [:mission_model_revision_id]))
  end
end
