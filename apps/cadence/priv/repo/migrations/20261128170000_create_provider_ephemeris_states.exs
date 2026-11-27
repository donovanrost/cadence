defmodule Cadence.Repo.Migrations.CreateProviderEphemerisStates do
  use Ecto.Migration

  # Ephemeris upload (#968): per mission provider and spacecraft, what Cadence last did to give
  # the provider the spacecraft's current orbit. One row per pair, replaced on every attempt.
  #   uploaded          the provider accepted the current element set
  #   failed            the upload failed; retried with backoff from next_retry_at
  #   lookup            the provider looks orbits up by NORAD id, and the set carries one
  #   norad_id_missing  the provider looks orbits up by NORAD id, and the set has none
  def change do
    create table(:provider_ephemeris_states, primary_key: false) do
      add(:organization_id, :text, null: false, collation: "C")
      add(:mission_id, :text, null: false, primary_key: true, collation: "C")
      add(:provider_id, :text, null: false, primary_key: true, collation: "C")
      add(:spacecraft_id, :text, null: false, primary_key: true, collation: "C")
      add(:status, :text, null: false)
      add(:element_set_id, :text, collation: "C")
      add(:content_sha256, :text, collation: "C")
      add(:provider_spacecraft_ref, :text, collation: "C")
      # The mission provider version the pair was acted on with (the one the transport pins).
      add(:provider_version, :integer)
      add(:attempts, :integer, null: false, default: 0)
      add(:reason, :text)
      add(:next_retry_at, :utc_datetime_usec)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:provider_ephemeris_states, :provider_ephemeris_states_status,
        check: "status IN ('uploaded', 'failed', 'lookup', 'norad_id_missing')"
      )
    )

    # A failed row is the only one with a retry time; the retry sweep reads due ones.
    create(
      constraint(:provider_ephemeris_states, :provider_ephemeris_states_retry,
        check: "(status = 'failed') = (next_retry_at IS NOT NULL)"
      )
    )

    create(
      index(:provider_ephemeris_states, [:next_retry_at],
        where: "status = 'failed'",
        name: :provider_ephemeris_states_due_idx
      )
    )

    execute(
      """
      ALTER TABLE provider_ephemeris_states
      ADD CONSTRAINT provider_ephemeris_states_spacecraft_fk
      FOREIGN KEY (organization_id, mission_id, spacecraft_id)
      REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
      ON DELETE CASCADE
      """,
      "ALTER TABLE provider_ephemeris_states DROP CONSTRAINT provider_ephemeris_states_spacecraft_fk"
    )
  end
end
