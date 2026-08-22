defmodule Cadence.Repo.Migrations.CreateContactPlanningEvidence do
  use Ecto.Migration

  def up do
    create table(:contact_planning_runs, primary_key: false) do
      add(:contact_planning_run_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_requirement_id, :string, null: false)
      add(:contact_requirement_version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:requested_by, :string, null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)
      add(:summary_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(
        :contact_planning_runs,
        [:organization_id, :mission_id, :contact_requirement_id, :started_at],
        name: :contact_planning_runs_requirement_idx
      )
    )

    create(
      constraint(:contact_planning_runs, :contact_planning_runs_state_check,
        check: "lifecycle_state IN ('running', 'completed', 'partial', 'failed')"
      )
    )

    execute("""
    ALTER TABLE contact_planning_runs
    ADD CONSTRAINT contact_planning_runs_requirement_version_fk
    FOREIGN KEY (
      organization_id, mission_id, contact_requirement_id, contact_requirement_version
    )
    REFERENCES contact_requirement_versions (
      organization_id, mission_id, contact_requirement_id, version
    )
    """)

    create table(:contact_planning_searches, primary_key: false) do
      add(:contact_planning_search_id, :string, primary_key: true)
      add(:contact_planning_run_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:route_key, :text, null: false)
      add(:route_order, :integer, null: false)
      add(:provider_id, :string)
      add(:provider_version, :integer)
      add(:provider_account_id, :string)
      add(:provider_account_version, :integer)
      add(:provider_account_grant_id, :string)
      add(:provider_account_grant_version, :integer)
      add(:provider_display_name, :string)
      add(:outcome, :string, null: false)
      add(:opportunity_count, :integer, null: false, default: 0)
      add(:route_binding_document, :map, null: false, default: %{})
      add(:readiness_document, :map, null: false, default: %{})
      add(:error_document, :map, null: false, default: %{})
      add(:content_sha256, :string, null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:contact_planning_searches, [:contact_planning_run_id, :route_key],
        name: :contact_planning_searches_route_idx
      )
    )

    create(
      index(:contact_planning_searches, [:organization_id, :mission_id, :outcome],
        name: :contact_planning_searches_mission_outcome_idx
      )
    )

    create(
      constraint(:contact_planning_searches, :contact_planning_searches_outcome_check,
        check:
          "outcome IN ('succeeded_with_results', 'succeeded_without_results', " <>
            "'not_ready', 'excluded_by_requirement', 'failed')"
      )
    )

    create(
      constraint(:contact_planning_searches, :contact_planning_searches_counts_check,
        check: "route_order >= 0 AND opportunity_count >= 0"
      )
    )

    execute("""
    ALTER TABLE contact_planning_searches
    ADD CONSTRAINT contact_planning_searches_run_fk
    FOREIGN KEY (contact_planning_run_id)
    REFERENCES contact_planning_runs (contact_planning_run_id)
    """)

    create table(:contact_opportunity_snapshots, primary_key: false) do
      add(:contact_opportunity_snapshot_id, :string, primary_key: true)
      add(:contact_planning_run_id, :string, null: false)
      add(:contact_planning_search_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_requirement_id, :string, null: false)
      add(:contact_requirement_version, :integer, null: false)
      add(:provider_opportunity_ref, :string, null: false)
      add(:starts_at, :utc_datetime_usec, null: false)
      add(:ends_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:availability, :string, null: false)
      add(:estimated_capacity_document, :map, null: false, default: %{})
      add(:synthetic, :boolean, null: false, default: false)
      add(:route_binding_document, :map, null: false)
      add(:normalized_opportunity_document, :map, null: false)
      add(:provider_evidence_document, :map, null: false)
      add(:evaluation_document, :map, null: false)
      add(:eligible, :boolean, null: false)
      add(:content_sha256, :string, null: false)
      add(:captured_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :contact_opportunity_snapshots,
        [:contact_planning_search_id, :provider_opportunity_ref, :content_sha256],
        name: :contact_opportunity_snapshots_content_idx
      )
    )

    create(
      index(
        :contact_opportunity_snapshots,
        [:organization_id, :mission_id, :contact_requirement_id, :starts_at],
        name: :contact_opportunity_snapshots_requirement_idx
      )
    )

    create(
      constraint(:contact_opportunity_snapshots, :contact_opportunity_snapshots_time_check,
        check: "starts_at < ends_at"
      )
    )

    execute("""
    ALTER TABLE contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_run_fk
    FOREIGN KEY (contact_planning_run_id)
    REFERENCES contact_planning_runs (contact_planning_run_id)
    """)

    execute("""
    ALTER TABLE contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_search_fk
    FOREIGN KEY (contact_planning_search_id)
    REFERENCES contact_planning_searches (contact_planning_search_id)
    """)

    execute("""
    ALTER TABLE contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_requirement_version_fk
    FOREIGN KEY (
      organization_id, mission_id, contact_requirement_id, contact_requirement_version
    )
    REFERENCES contact_requirement_versions (
      organization_id, mission_id, contact_requirement_id, version
    )
    """)
  end

  def down do
    drop(table(:contact_opportunity_snapshots))
    drop(table(:contact_planning_searches))
    drop(table(:contact_planning_runs))
  end
end
