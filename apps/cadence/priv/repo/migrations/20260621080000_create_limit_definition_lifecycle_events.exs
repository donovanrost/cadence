defmodule Cadence.Repo.Migrations.CreateLimitDefinitionLifecycleEvents do
  use Ecto.Migration

  def change do
    create table(:limit_definition_lifecycle_events, primary_key: false) do
      add(:limit_definition_lifecycle_event_id, :string, primary_key: true)
      add(:definition_activation_key, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:point_id, :string, null: false)
      add(:limit_set_name, :string, null: false)
      add(:scope_type, :string)
      add(:scope_ref, :string)
      add(:realm, :string)
      add(:event_type, :string, null: false)
      add(:limit_definition_id, :string, null: false)
      add(:limit_definition_version, :integer, null: false)
      add(:previous_limit_definition_id, :string)
      add(:previous_limit_definition_version, :integer)
      add(:active_from, :utc_datetime_usec, null: false)
      add(:active_to, :utc_datetime_usec)
      add(:reason, :string)
      add(:observed_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(
        :limit_definition_lifecycle_events,
        [:organization_id, :mission_id, :point_id, :limit_set_name],
        name: :limit_definition_lifecycle_events_scope_idx
      )
    )

    create(
      index(
        :limit_definition_lifecycle_events,
        [:mission_id, :limit_definition_id, :limit_definition_version],
        name: :limit_definition_lifecycle_events_definition_idx
      )
    )

    create table(:active_limit_definitions, primary_key: false) do
      add(:definition_activation_key, :string, primary_key: true)
      add(:limit_definition_lifecycle_event_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:point_id, :string, null: false)
      add(:limit_set_name, :string, null: false)
      add(:scope_type, :string)
      add(:scope_ref, :string)
      add(:realm, :string)
      add(:event_type, :string, null: false)
      add(:limit_definition_id, :string, null: false)
      add(:limit_definition_version, :integer, null: false)
      add(:previous_limit_definition_id, :string)
      add(:previous_limit_definition_version, :integer)
      add(:active_from, :utc_datetime_usec, null: false)
      add(:active_to, :utc_datetime_usec)
      add(:reason, :string)
      add(:last_seen_at, :utc_datetime_usec, null: false)
      add(:transition_count, :integer, null: false, default: 1)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(
        :active_limit_definitions,
        [:organization_id, :mission_id, :point_id, :limit_set_name],
        name: :active_limit_definitions_scope_idx
      )
    )

    create(
      index(
        :active_limit_definitions,
        [:mission_id, :limit_definition_id, :limit_definition_version],
        name: :active_limit_definitions_definition_idx
      )
    )
  end
end
