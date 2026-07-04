defmodule Cadence.Repo.Migrations.CreateDashboardRuntimeInvalidationDecisionEvents do
  use Ecto.Migration

  def up do
    create table(:dashboard_runtime_invalidation_decision_events, primary_key: false) do
      add(:dashboard_runtime_invalidation_decision_event_id, :string, primary_key: true)
      add(:invalidation_event_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:boundary, :string, null: false)
      add(:domain_fact, :string)
      add(:decision_status, :string, null: false)
      add(:matches, :boolean)
      add(:dashboard_matches, :boolean)
      add(:context_matches, :boolean)
      add(:context_reason, :string)
      add(:refresh_allowed, :boolean)
      add(:refresh_reason, :string)
      add(:affected_placement_count, :integer)
      add(:affected_placement_ids, {:array, :string}, null: false, default: [])
      add(:affected_widget_type_ids, {:array, :string}, null: false, default: [])
      add(:affected_impact_reasons, {:array, :string}, null: false, default: [])
      add(:invalidated_artifacts, :integer, null: false, default: 0)
      add(:invalidation_occurred_at, :utc_datetime_usec)
      add(:decision_observed_at, :utc_datetime_usec, null: false)
      add(:filters, :map, null: false, default: %{})
      add(:measurements, :map, null: false, default: %{})
      add(:decision, :map, null: false, default: %{})
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(
        :dashboard_runtime_invalidation_decision_events,
        [:organization_id, :mission_id, :dashboard_id, :decision_observed_at],
        name: :dashboard_runtime_invalidation_decisions_dashboard_idx
      )
    )

    create(
      index(
        :dashboard_runtime_invalidation_decision_events,
        [:organization_id, :mission_id, :decision_status],
        name: :dashboard_runtime_invalidation_decisions_status_idx
      )
    )

    create(
      index(
        :dashboard_runtime_invalidation_decision_events,
        [:invalidation_event_id],
        name: :dashboard_runtime_invalidation_decisions_invalidation_idx
      )
    )

    execute("""
    ALTER TABLE dashboard_runtime_invalidation_decision_events
    ADD CONSTRAINT dashboard_runtime_invalidation_decisions_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE dashboard_runtime_invalidation_decision_events
    ADD CONSTRAINT dashboard_runtime_invalidation_decisions_dashboard_fk
    FOREIGN KEY (dashboard_id)
    REFERENCES ops_dashboards (dashboard_id)
    ON DELETE CASCADE
    """)
  end

  def down do
    execute("""
    ALTER TABLE dashboard_runtime_invalidation_decision_events
    DROP CONSTRAINT IF EXISTS dashboard_runtime_invalidation_decisions_dashboard_fk
    """)

    execute("""
    ALTER TABLE dashboard_runtime_invalidation_decision_events
    DROP CONSTRAINT IF EXISTS dashboard_runtime_invalidation_decisions_org_mission_fk
    """)

    drop_if_exists(
      index(
        :dashboard_runtime_invalidation_decision_events,
        [:invalidation_event_id],
        name: :dashboard_runtime_invalidation_decisions_invalidation_idx
      )
    )

    drop_if_exists(
      index(
        :dashboard_runtime_invalidation_decision_events,
        [:organization_id, :mission_id, :decision_status],
        name: :dashboard_runtime_invalidation_decisions_status_idx
      )
    )

    drop_if_exists(
      index(
        :dashboard_runtime_invalidation_decision_events,
        [:organization_id, :mission_id, :dashboard_id, :decision_observed_at],
        name: :dashboard_runtime_invalidation_decisions_dashboard_idx
      )
    )

    drop(table(:dashboard_runtime_invalidation_decision_events))
  end
end
