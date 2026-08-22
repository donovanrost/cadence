defmodule Cadence.Repo.Migrations.CreateSourceEndpointsAndAddSourceEndpointRefs do
  use Ecto.Migration

  def change do
    create table(:mission_source_endpoints, primary_key: false) do
      add(:source_endpoint_id, :string, primary_key: true)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:source_ref, :string)
      add(:scid, :integer)
      add(:display_name, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:mission_source_endpoints, [:mission_id, :source_endpoint_id],
             name: :mission_source_endpoints_scope_idx
           ))

    create(index(:mission_source_endpoints, [:mission_id, :source_ref],
             name: :mission_source_endpoints_source_ref_idx
           ))

    create(index(:mission_source_endpoints, [:mission_id, :spacecraft_id],
             name: :mission_source_endpoints_spacecraft_idx
           ))

    alter table(:ingress_raw_evidence) do
      add(:source_endpoint_ref, :string)
    end

    create(index(:ingress_raw_evidence, [:mission_id, :source_endpoint_ref],
             name: :ingress_raw_evidence_source_endpoint_idx
           ))

    alter table(:protocol_packet_records) do
      add(:source_endpoint_ref, :string)
    end

    create(index(:protocol_packet_records, [:mission_id, :source_endpoint_ref],
             name: :protocol_packet_records_source_endpoint_idx
           ))
  end
end
