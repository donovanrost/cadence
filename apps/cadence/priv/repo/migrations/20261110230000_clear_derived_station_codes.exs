defmodule Cadence.Repo.Migrations.ClearDerivedStationCodes do
  use Ecto.Migration

  # U25: station codes are display only, and 20261109200000 stored codes it derived from names.
  # Clear every code that still equals that derivation (same stem and de-dup); the UI offers
  # the derivation again as a computed suggestion. Seeds re-assert real codes on their next run.
  def up do
    execute("""
    WITH base AS (
      SELECT ground_station_id, mission_id,
             upper(left(regexp_replace(display_name, '[^A-Za-z]', '', 'g'), 3)) AS stem
      FROM comms_ground_stations
    ), numbered AS (
      SELECT ground_station_id, mission_id, stem,
             row_number() OVER (PARTITION BY mission_id, stem ORDER BY ground_station_id) AS n
      FROM base
    )
    UPDATE comms_ground_stations s
    SET code = NULL
    FROM numbered
    WHERE s.ground_station_id = numbered.ground_station_id AND s.mission_id = numbered.mission_id
      AND numbered.stem <> ''
      AND s.code = CASE WHEN numbered.n = 1 THEN numbered.stem ELSE numbered.stem || numbered.n END
    """)
  end

  # Cleared codes were never confirmed by anyone; there is nothing to restore.
  def down, do: :ok
end
