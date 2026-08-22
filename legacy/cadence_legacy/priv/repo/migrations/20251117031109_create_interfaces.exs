defmodule Cadence.Repo.Migrations.CreateInterfaces do
  use Ecto.Migration

  def change do
    create table(:interfaces, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :connection_type, :string, null: false

      # Connection parameters
      add :host, :string
      add :port, :integer
      add :bind_address, :string
      add :bind_port, :integer

      # Protocol configuration
      add :protocol_type, :string
      # length, template, terminated, fixed, or nil
      add :protocol_config, :map, default: %{}
      add :protocol_direction, :string, default: "read_write"
      # read, write, read_write

      # Connection state
      add :status, :string, null: false, default: "disconnected"
      # disconnected, connecting, connected, error

      # Additional configuration
      add :config, :map, default: %{}
      add :metadata, :map, default: %{}

      # Auto-reconnect settings
      add :auto_reconnect, :boolean, default: true
      add :reconnect_delay_ms, :integer, default: 5000

      timestamps(type: :utc_datetime)
    end

    create index(:interfaces, [:mission_id])
    create unique_index(:interfaces, [:mission_id, :name])
    create index(:interfaces, [:status])
    create index(:interfaces, [:connection_type])
    create index(:interfaces, [:protocol_type])
  end
end
