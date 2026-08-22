defmodule Cadence.Repo.Migrations.CreateChannelProtocolConfigs do
  use Ecto.Migration

  def change do
    create table(:channel_protocol_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :overrides, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_protocol_configs, [:channel_id],
             name: :channel_protocol_configs_channel_index
           )

    create index(:channel_protocol_configs, [:mission_id])
  end
end
