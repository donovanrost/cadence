defmodule Cadence.Repo.Migrations.AddGroundStationGeometry do
  use Ecto.Migration

  # Station geometry for pass prediction (#890, slice 2 of #732). Two sources are kept apart:
  # the mission's own location (set through the ground_station change-set kind) and the one a
  # provider reports in its inventory. A read uses the mission's when set, else the provider's;
  # a provider report never writes the mission's columns.
  def change do
    alter table(:comms_ground_stations) do
      add(:latitude_deg, :float)
      add(:longitude_deg, :float)
      add(:height_m, :float)
      add(:elevation_mask_deg, :float, null: false, default: 5.0)
      add(:provider_latitude_deg, :float)
      add(:provider_longitude_deg, :float)
      add(:provider_height_m, :float)
      add(:provider_location_provider_id, :text, collation: "C")
      add(:provider_location_reported_at, :utc_datetime_usec)
    end

    for prefix <- ["", "provider_"] do
      create(
        constraint(:comms_ground_stations, :"comms_ground_stations_#{prefix}location_range",
          check: """
          (#{prefix}latitude_deg IS NULL OR #{prefix}latitude_deg BETWEEN -90 AND 90) AND
          (#{prefix}longitude_deg IS NULL OR #{prefix}longitude_deg BETWEEN -180 AND 180) AND
          (#{prefix}height_m IS NULL OR #{prefix}height_m BETWEEN -1000 AND 10000)
          """
        )
      )
    end

    # A location is all three numbers or none.
    create(
      constraint(:comms_ground_stations, :comms_ground_stations_location_complete,
        check: """
        (latitude_deg IS NULL) = (longitude_deg IS NULL) AND
        (latitude_deg IS NULL) = (height_m IS NULL)
        """
      )
    )

    # A provider report is the three numbers with the provider that sent it and when, or nothing.
    create(
      constraint(:comms_ground_stations, :comms_ground_stations_provider_location_complete,
        check: """
        (provider_latitude_deg IS NULL) = (provider_longitude_deg IS NULL) AND
        (provider_latitude_deg IS NULL) = (provider_height_m IS NULL) AND
        (provider_latitude_deg IS NULL) = (provider_location_provider_id IS NULL) AND
        (provider_latitude_deg IS NULL) = (provider_location_reported_at IS NULL)
        """
      )
    )

    create(
      constraint(:comms_ground_stations, :comms_ground_stations_elevation_mask_range,
        check: "elevation_mask_deg >= 0 AND elevation_mask_deg <= 89.9"
      )
    )
  end
end
