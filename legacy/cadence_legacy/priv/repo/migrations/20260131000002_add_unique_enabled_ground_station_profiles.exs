defmodule Cadence.Repo.Migrations.AddUniqueEnabledGroundStationProfiles do
  use Ecto.Migration

  def change do
    create unique_index(
             :ground_station_profiles,
             [:mission_id, :ground_station_target_id],
             where: "enabled = true",
             name: :uniq_enabled_gs_profile_per_station
           )
  end
end
