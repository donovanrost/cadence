defmodule Cadence.Repo.Migrations.EphemerisOutcomeSince do
  use Ecto.Migration

  # #972: `outcome_since` is when the pair entered its current outcome. The run keeps it while the
  # status, reason code, element set, bound version and ref are unchanged, so Now and the member
  # list show how long a pair has been stuck, not its last re-check. Existing rows start at their
  # last update.
  #
  # `reason` now holds only a closed code (`Cadence.GroundNetworks.EphemerisReasons`). A failed
  # row written before this could hold a provider's own text, which may carry evidence: it is
  # replaced by `other`, and a not_ready code outside the vocabulary by `no_ready_route`.
  @not_ready ~w(mission_provider_not_validated mission_provider_not_active
    mission_provider_not_found mission_provider_profiles_not_synced
    provider_service_profile_not_active provider_delivery_profile_not_ready
    provider_profile_version_not_available provider_profile_direction_not_supported
    provider_profiles_not_compatible provider_route_not_ready invalid_provider_profile_reference
    transport_not_found transport_not_active transport_provider_snapshot_mismatch
    transport_runtime_profile_mismatch transport_runtime_profile_not_materialized
    direct_transport_not_provider_schedulable contact_link_assignment_not_found
    contact_path_template_not_found source_endpoint_not_found
    missing_provider_spacecraft_reference spacecraft_not_found no_ready_route)

  def up do
    alter table(:provider_ephemeris_states) do
      add(:outcome_since, :utc_datetime_usec)
    end

    execute("UPDATE provider_ephemeris_states SET outcome_since = updated_at")
    execute("ALTER TABLE provider_ephemeris_states ALTER COLUMN outcome_since SET NOT NULL")
    execute("UPDATE provider_ephemeris_states SET reason = 'other' WHERE status = 'failed'")

    execute("""
    UPDATE provider_ephemeris_states SET reason = 'no_ready_route'
    WHERE status = 'not_ready'
      AND (reason IS NULL OR reason <> ALL(ARRAY[#{Enum.map_join(@not_ready, ", ", &"'#{&1}'")}]))
    """)
  end

  def down do
    alter table(:provider_ephemeris_states) do
      remove(:outcome_since)
    end
  end
end
