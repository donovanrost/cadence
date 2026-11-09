defmodule Cadence.Repo.Migrations.CreateContactPassResults do
  use Ecto.Migration

  # S9 (DECISIONS #47/#48): one persisted result per booked pass, keyed by its provider
  # reservation. Provider-reported times and volume, a derived outcome with cause and owner.
  # Cadence-received volume (from the archives at close-out) is kept separate from the provider's.
  def change do
    create table(:contact_pass_results, primary_key: false) do
      add(:provider_reservation_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:provider_id, :string, null: false)
      add(:scheduled_contact_id, :string)
      add(:realized_contact_id, :string)
      add(:spacecraft_id, :string, null: false)
      add(:ground_station_ref, :string)
      add(:antenna_ref, :string)
      add(:contact_plan_id, :string)
      add(:contact_plan_version, :integer)
      add(:planned_aos, :utc_datetime_usec, null: false)
      add(:planned_los, :utc_datetime_usec, null: false)
      add(:actual_aos, :utc_datetime_usec)
      add(:actual_los, :utc_datetime_usec)
      add(:planned_seconds, :integer, null: false)
      add(:flown_seconds, :integer)
      add(:planned_bytes, :bigint)
      add(:provider_bytes, :bigint)
      add(:provider_frames, :bigint)
      add(:provider_packets, :bigint)
      add(:received_bytes, :bigint)
      add(:received_frames, :bigint)
      add(:observations, :map, null: false, default: %{})
      add(:outcome, :string, null: false)
      add(:cause, :string)
      add(:cause_source, :string)
      add(:owner, :string, null: false, default: "unknown")
      add(:disputable, :boolean, null: false, default: false)
      add(:provider_reported_at, :utc_datetime_usec)
      add(:provider_revision, :integer)
      add(:closed_at, :utc_datetime_usec)
      add(:result_document, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:contact_pass_results, [:organization_id, :mission_id, :planned_aos]))

    create(
      index(:contact_pass_results, [
        :organization_id,
        :mission_id,
        :ground_station_ref,
        :planned_aos
      ])
    )

    create(index(:contact_pass_results, [:organization_id, :mission_id, :contact_plan_id]))
    create(index(:contact_pass_results, [:organization_id, :provider_id, :closed_at]))

    create(
      constraint(:contact_pass_results, :contact_pass_results_outcome_check,
        check: "outcome IN ('realized','partial','missed','failed','canceled','pending_report')"
      )
    )

    create(
      constraint(:contact_pass_results, :contact_pass_results_owner_check,
        check: "owner IN ('provider','us','weather','unknown')"
      )
    )
  end
end
