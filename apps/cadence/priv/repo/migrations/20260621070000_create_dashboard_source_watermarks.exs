defmodule Cadence.Repo.Migrations.CreateDashboardSourceWatermarks do
  use Ecto.Migration

  def change do
    create table(:dashboard_source_watermark_events, primary_key: false) do
      add(:source_watermark_event_id, :string, primary_key: true)
      add(:source_watermark_key, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:logical_source, :string, null: false)
      add(:data_source_id, :string, null: false)
      add(:source_binding_id, :string)
      add(:realm, :string)
      add(:replay_run_id, :string)
      add(:dataset, :string)
      add(:event_type, :string, null: false)
      add(:complete_through, :utc_datetime_usec)
      add(:previous_complete_through, :utc_datetime_usec)
      add(:latest_receipt_time, :utc_datetime_usec)
      add(:previous_latest_receipt_time, :utc_datetime_usec)
      add(:retention_starts_at, :utc_datetime_usec)
      add(:previous_retention_starts_at, :utc_datetime_usec)
      add(:sample_count, :integer)
      add(:confidence, :string, null: false)
      add(:reason, :string)
      add(:observed_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:dashboard_source_watermark_events, [:source_watermark_key, :observed_at],
        name: :dashboard_source_watermark_events_key_observed_idx
      )
    )

    create(
      index(:dashboard_source_watermark_events, [:organization_id, :mission_id, :logical_source],
        name: :dashboard_source_watermark_events_scope_idx
      )
    )

    create(
      index(:dashboard_source_watermark_events, [:data_source_id],
        name: :dashboard_source_watermark_events_data_source_idx
      )
    )

    create table(:dashboard_source_watermark_statuses, primary_key: false) do
      add(:source_watermark_key, :string, primary_key: true)
      add(:source_watermark_event_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:logical_source, :string, null: false)
      add(:data_source_id, :string, null: false)
      add(:source_binding_id, :string)
      add(:realm, :string)
      add(:replay_run_id, :string)
      add(:dataset, :string)
      add(:event_type, :string, null: false)
      add(:complete_through, :utc_datetime_usec)
      add(:previous_complete_through, :utc_datetime_usec)
      add(:latest_receipt_time, :utc_datetime_usec)
      add(:previous_latest_receipt_time, :utc_datetime_usec)
      add(:retention_starts_at, :utc_datetime_usec)
      add(:previous_retention_starts_at, :utc_datetime_usec)
      add(:sample_count, :integer)
      add(:confidence, :string, null: false)
      add(:reason, :string)
      add(:observed_at, :utc_datetime_usec, null: false)
      add(:last_seen_at, :utc_datetime_usec, null: false)
      add(:transition_count, :integer, null: false, default: 1)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(
        :dashboard_source_watermark_statuses,
        [:organization_id, :mission_id, :logical_source],
        name: :dashboard_source_watermark_statuses_scope_idx
      )
    )

    create(
      index(:dashboard_source_watermark_statuses, [:data_source_id],
        name: :dashboard_source_watermark_statuses_data_source_idx
      )
    )
  end
end
