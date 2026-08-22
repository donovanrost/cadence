defmodule Cadence.Repo.Migrations.CreateChannelActiveSelections do
  use Ecto.Migration

  def change do
    create table(:channel_active_selections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :binding_id, references(:bindings, type: :binary_id, on_delete: :nilify_all)
      add :direction, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_active_selections, [:channel_id, :direction],
             name: :channel_active_selections_channel_direction_index
           )

    create index(:channel_active_selections, [:mission_id])
  end
end
