defmodule Cadence.Repo.Migrations.CreateActivationAndRuntimeFoundationTables do
  use Ecto.Migration

  def change do
    create table(:mission_binding_set_activations, primary_key: false) do
      add(:activation_id, :string, primary_key: true)
      add(:mission_id, :string, null: false)
      add(:binding_set_id, :string, null: false)
      add(:binding_set_version, :integer, null: false)
      add(:metadata, :map, null: false, default: %{})
      add(:activated_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:mission_binding_set_activations, [:mission_id, :activated_at],
             name: :mission_binding_set_activations_scope_idx
           ))

    create table(:mission_active_binding_sets, primary_key: false) do
      add(:mission_id, :string, primary_key: true)

      add(
        :activation_id,
        references(:mission_binding_set_activations, column: :activation_id, type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:binding_set_id, :string, null: false)
      add(:binding_set_version, :integer, null: false)
      add(:metadata, :map, null: false, default: %{})
      add(:activated_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
