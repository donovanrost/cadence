defmodule Cadence.Repo.Migrations.CreateInterfaceProtocols do
  use Ecto.Migration

  def change do
    create table(:interface_protocols, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :interface_id, references(:interfaces, on_delete: :delete_all, type: :binary_id),
        null: false

      add :protocol_type, :string, null: false
      add :protocol_config, :map, default: %{}, null: false
      add :protocol_direction, :string, null: false, default: "read_write"
      add :order, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:interface_protocols, [:interface_id])
    create unique_index(:interface_protocols, [:interface_id, :order])

    # Add check constraint for valid protocol types
    create constraint(:interface_protocols, :valid_protocol_type,
             check: "protocol_type IN ('length', 'template', 'terminated', 'fixed')"
           )

    # Add check constraint for valid protocol directions
    create constraint(:interface_protocols, :valid_protocol_direction,
             check: "protocol_direction IN ('read', 'write', 'read_write')"
           )

    # Add check constraint for non-negative order
    create constraint(:interface_protocols, :non_negative_order, check: "\"order\" >= 0")
  end
end
