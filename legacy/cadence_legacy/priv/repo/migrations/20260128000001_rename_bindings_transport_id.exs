defmodule Cadence.Repo.Migrations.RenameBindingsTransportId do
  use Ecto.Migration

  def change do
    drop_if_exists index(:bindings, [:interface_id])

    drop_if_exists(
      unique_index(
        :bindings,
        [:organization_id, :mission_id, :channel_id, :interface_id, :direction, :role],
        name: :bindings_org_mission_channel_interface_index
      )
    )

    rename table(:bindings), :interface_id, to: :transport_id

    create index(:bindings, [:transport_id])

    create unique_index(
             :bindings,
             [:organization_id, :mission_id, :channel_id, :transport_id, :direction, :role],
             name: :bindings_org_mission_channel_transport_index
           )
  end
end
