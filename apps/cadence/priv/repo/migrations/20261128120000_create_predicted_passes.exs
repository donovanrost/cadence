defmodule Cadence.Repo.Migrations.CreatePredictedPasses do
  use Ecto.Migration

  # Predicted passes (#891, slice 3 of #732; docs/pass-prediction-design.md). Derived rows,
  # recomputed from element sets and station geometry by supervised jobs, so they carry no
  # organization trigger (the code writes organization_id with the mission's) and only the
  # spacecraft foreign key: deleting a spacecraft deletes its passes. Stations are archived, not
  # deleted; the station job removes an archived station's passes.
  def up do
    create table(:predicted_passes, primary_key: false) do
      add(:predicted_pass_id, :text, primary_key: true, collation: "C")
      add(:organization_id, :text, null: false, collation: "C")
      add(:mission_id, :text, null: false, collation: "C")
      add(:spacecraft_id, :text, null: false, collation: "C")
      add(:ground_station_id, :text, null: false, collation: "C")
      add(:element_set_id, :text, null: false, collation: "C")
      add(:aos, :utc_datetime_usec, null: false)
      add(:tca, :utc_datetime_usec, null: false)
      add(:los, :utc_datetime_usec, null: false)
      add(:max_elevation_deg, :float, null: false)
      add(:aos_azimuth_deg, :float)
      add(:los_azimuth_deg, :float)
      add(:computed_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:predicted_passes, :predicted_passes_order_check,
        check: "aos <= tca AND tca <= los"
      )
    )

    # Reads by station, by spacecraft and by mission window, each in AOS-then-id order. The prune
    # uses the mission index too (a pass that ended before a time also started before it).
    execute("""
    CREATE INDEX predicted_passes_station_aos_idx
    ON predicted_passes (mission_id, ground_station_id, aos, predicted_pass_id)
    """)

    execute("""
    CREATE INDEX predicted_passes_spacecraft_aos_idx
    ON predicted_passes (mission_id, spacecraft_id, aos, predicted_pass_id)
    """)

    execute("""
    CREATE INDEX predicted_passes_mission_aos_idx
    ON predicted_passes (mission_id, aos, predicted_pass_id)
    """)

    execute("""
    ALTER TABLE predicted_passes
    ADD CONSTRAINT predicted_passes_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    ON DELETE CASCADE
    """)

    # One row per mission: how far passes are computed and what the runs could not predict.
    create table(:pass_prediction_states, primary_key: false) do
      add(:mission_id, :text, primary_key: true, collation: "C")
      add(:organization_id, :text, null: false, collation: "C")
      add(:horizon_end, :utc_datetime_usec, null: false)
      add(:computed_at, :utc_datetime_usec, null: false)
      # spacecraft_id => reason the current element set could not be propagated.
      add(:unpropagated, :map, null: false, default: %{})
      # "spacecraft_id|ground_station_id" => passes with no horizon crossing inside the bound.
      add(:not_bracketed, :map, null: false, default: %{})
    end

    execute("""
    ALTER TABLE pass_prediction_states
    ADD CONSTRAINT pass_prediction_states_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    ON DELETE CASCADE
    """)
  end

  def down do
    drop(table(:pass_prediction_states))
    drop(table(:predicted_passes))
  end
end
