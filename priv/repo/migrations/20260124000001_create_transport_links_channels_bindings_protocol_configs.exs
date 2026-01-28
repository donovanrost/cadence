defmodule Cadence.Repo.Migrations.CreateTransportLinksChannelsBindingsProtocolConfigs do
  use Ecto.Migration

  def change do
    create table(:transport_interfaces, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :type, :string, null: false
      add :endpoint, :map, default: %{}
      add :auth, :map, default: %{}
      add :tags, {:array, :string}, default: []
      add :allowed_directions, {:array, :string}, default: ["both"], null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:transport_interfaces, [:organization_id, :mission_id, :name],
             name: :transport_interfaces_org_mission_name_index
           )

    create index(:transport_interfaces, [:mission_id])

    create table(:links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :scid, :integer, null: false
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:links, [:organization_id, :mission_id, :scid],
             name: :links_org_mission_scid_index
           )

    create index(:links, [:mission_id])

    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :link_id, references(:links, type: :binary_id, on_delete: :delete_all), null: false
      add :scid, :integer, null: false
      add :vcid, :integer, null: false
      add :map_id, :integer
      add :direction, :string, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:organization_id, :mission_id, :scid, :vcid],
             where: "map_id IS NULL",
             name: :channels_org_mission_scid_vcid_null_map_index
           )

    create unique_index(:channels, [:organization_id, :mission_id, :scid, :vcid, :map_id],
             where: "map_id IS NOT NULL",
             name: :channels_org_mission_scid_vcid_map_index
           )

    create index(:channels, [:mission_id])
    create index(:channels, [:link_id])

    create table(:bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :interface_id,
          references(:transport_interfaces, type: :binary_id, on_delete: :delete_all),
          null: false

      add :direction, :string, null: false
      add :role, :string, null: false
      add :priority, :integer, default: 100, null: false
      add :desired_state, :string, default: "inactive", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :bindings,
             [:organization_id, :mission_id, :channel_id, :interface_id, :direction, :role],
             name: :bindings_org_mission_channel_interface_index
           )

    create index(:bindings, [:channel_id])
    create index(:bindings, [:interface_id])

    create table(:protocol_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :link_id, references(:links, type: :binary_id, on_delete: :delete_all), null: false
      add :config, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:protocol_configs, [:link_id], name: :protocol_configs_link_index)
  end
end
