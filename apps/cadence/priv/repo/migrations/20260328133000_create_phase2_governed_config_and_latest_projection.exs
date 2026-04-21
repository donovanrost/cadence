defmodule Cadence.Repo.Migrations.CreatePhase2GovernedConfigAndLatestProjection do
  use Ecto.Migration

  def change do
    create table(:governed_packet_definitions) do
      add(:mission_id, :string, null: false)
      add(:packet_definition_id, :string, null: false)
      add(:packet_name, :string, null: false)
      add(:apid, :integer, null: false)
      add(:version, :integer, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :governed_packet_definitions,
        [:mission_id, :packet_definition_id, :version],
        name: :governed_packet_definitions_scope_idx
      )
    )

    create table(:governed_packet_definition_fields) do
      add(
        :packet_definition_row_id,
        references(:governed_packet_definitions, on_delete: :delete_all),
        null: false
      )

      add(:field_id, :string, null: false)
      add(:name, :string, null: false)
      add(:offset_bits, :integer, null: false)
      add(:size_bits, :integer, null: false)
      add(:data_type, :string, null: false)
      add(:byte_order, :string, null: false)
      add(:engineering_unit, :string)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :governed_packet_definition_fields,
        [:packet_definition_row_id, :field_id],
        name: :governed_packet_definition_fields_scope_idx
      )
    )

    create table(:governed_binding_sets) do
      add(:mission_id, :string, null: false)
      add(:binding_set_id, :string, null: false)
      add(:version, :integer, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :governed_binding_sets,
        [:mission_id, :binding_set_id, :version],
        name: :governed_binding_sets_scope_idx
      )
    )

    create table(:governed_binding_rules) do
      add(:binding_set_row_id, references(:governed_binding_sets, on_delete: :delete_all),
        null: false
      )

      add(:binding_rule_id, :string, null: false)
      add(:handler_key, :string, null: false)
      add(:packet_kind, :string)
      add(:apid, :integer)
      add(:priority, :integer, null: false)
      add(:fanout_mode, :string, null: false)
      add(:handler_configuration_type, :string)
      add(:handler_configuration_ref, :map)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:governed_binding_rules, [:binding_rule_id]))
    create(index(:governed_binding_rules, [:binding_set_row_id, :priority]))

    create table(:telemetry_latest_values) do
      add(:mission_id, :string, null: false)
      add(:spacecraft_scope_id, :string, null: false, default: "")
      add(:spacecraft_id, :string)
      add(:point_id, :string, null: false)
      add(:point_name, :string, null: false)
      add(:sample_id, :string, null: false)

      add(
        :packet_id,
        references(:protocol_packet_records,
          column: :packet_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(
        :evidence_id,
        references(:ingress_raw_evidence,
          column: :evidence_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:packet_definition_id, :string, null: false)
      add(:packet_definition_version, :integer, null: false)
      add(:raw_value, :map, null: false)
      add(:engineering_value, :map, null: false)
      add(:quality_state, :string, null: false)
      add(:generation_time, :utc_datetime_usec)
      add(:receipt_time, :utc_datetime_usec, null: false)
      add(:provenance, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :telemetry_latest_values,
        [:mission_id, :spacecraft_scope_id, :point_id],
        name: :telemetry_latest_values_scope_idx
      )
    )

    create(index(:telemetry_latest_values, [:mission_id, :point_name]))
  end
end
