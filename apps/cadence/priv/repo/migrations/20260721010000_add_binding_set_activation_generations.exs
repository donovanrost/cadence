defmodule Cadence.Repo.Migrations.AddBindingSetActivationGenerations do
  use Ecto.Migration

  def up do
    alter table(:mission_binding_set_activations) do
      add(:generation, :bigint)
      add(:binding_set_content_sha256, :string)
    end

    alter table(:mission_active_binding_sets) do
      add(:generation, :bigint)
      add(:binding_set_content_sha256, :string)
    end

    flush()

    execute("""
    WITH ranked AS (
      SELECT
        activation_id,
        ROW_NUMBER() OVER (
          PARTITION BY mission_id
          ORDER BY activated_at, activation_id
        ) AS generation
      FROM mission_binding_set_activations
    )
    UPDATE mission_binding_set_activations AS activation
    SET generation = ranked.generation
    FROM ranked
    WHERE activation.activation_id = ranked.activation_id
    """)

    execute("""
    UPDATE mission_active_binding_sets AS active
    SET generation = activation.generation
    FROM mission_binding_set_activations AS activation
    WHERE active.activation_id = activation.activation_id
    """)

    alter table(:mission_binding_set_activations) do
      modify(:generation, :bigint, null: false)
    end

    alter table(:mission_active_binding_sets) do
      modify(:generation, :bigint, null: false)
    end

    create(
      unique_index(:mission_binding_set_activations, [:mission_id, :generation],
        name: :mission_binding_set_activations_generation_idx
      )
    )
  end

  def down do
    drop_if_exists(
      index(:mission_binding_set_activations, [:mission_id, :generation],
        name: :mission_binding_set_activations_generation_idx
      )
    )

    alter table(:mission_active_binding_sets) do
      remove(:binding_set_content_sha256)
      remove(:generation)
    end

    alter table(:mission_binding_set_activations) do
      remove(:binding_set_content_sha256)
      remove(:generation)
    end
  end
end
