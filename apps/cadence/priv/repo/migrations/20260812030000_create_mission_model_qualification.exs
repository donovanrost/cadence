defmodule Cadence.Repo.Migrations.CreateMissionModelQualification do
  use Ecto.Migration

  def change do
    create table(:mission_model_qualification_cases, primary_key: false) do
      add(:qualification_case_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:name, :string, null: false)
      add(:status, :string, null: false)
      add(:input_term, :binary, null: false)
      add(:expected_result_sha256, :string)
      add(:approved_by, :map, null: false, default: %{"value" => %{}})
      add(:approved_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:mission_model_qualification_cases, [:organization_id, :mission_id, :status],
        name: :mission_model_qualification_cases_scope_idx
      )
    )

    create table(:mission_model_comparison_reports, primary_key: false) do
      add(:comparison_report_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:candidate_revision_id, :string, null: false)
      add(:baseline_revision_id, :string)
      add(:binding_set_id, :string, null: false)
      add(:binding_set_version, :integer, null: false)
      add(:status, :string, null: false)
      add(:risk, :string, null: false)
      add(:report_sha256, :string, null: false)
      add(:report, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :mission_model_comparison_reports,
        [
          :organization_id,
          :mission_id,
          :candidate_revision_id,
          :binding_set_id,
          :binding_set_version,
          :report_sha256
        ],
        name: :mission_model_comparison_reports_identity_idx
      )
    )
  end
end
