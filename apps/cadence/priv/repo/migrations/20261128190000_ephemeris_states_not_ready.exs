defmodule Cadence.Repo.Migrations.EphemerisStatesNotReady do
  use Ecto.Migration

  # #974: a pair bound by an active routing rule but with no ready route is recorded as
  # `not_ready` (with the scheduling refusal as its reason) instead of being staged again on every
  # reconcile, and is re-checked from `next_retry_at`. `bound_provider_version` is the version the
  # routing rules pin (what the reconcile query reads), kept apart from `provider_version`, the
  # version the run actually used (a lower one whose route is ready, when the highest isn't).
  # Any status may now carry a re-check time; the two lookup ones only when they were reached
  # through a lower version than the rules bind (re-checked until the bound version is ready).
  # The due index covers every row that has one.
  def up do
    alter table(:provider_ephemeris_states) do
      add(:bound_provider_version, :integer)
    end

    execute("UPDATE provider_ephemeris_states SET bound_provider_version = provider_version")

    drop(constraint(:provider_ephemeris_states, :provider_ephemeris_states_status))
    drop(constraint(:provider_ephemeris_states, :provider_ephemeris_states_retry))

    drop(
      index(:provider_ephemeris_states, [:next_retry_at],
        name: :provider_ephemeris_states_due_idx
      )
    )

    create(
      constraint(:provider_ephemeris_states, :provider_ephemeris_states_status,
        check: "status IN ('uploaded', 'failed', 'not_ready', 'lookup', 'norad_id_missing')"
      )
    )

    create(
      constraint(:provider_ephemeris_states, :provider_ephemeris_states_retry,
        check: """
        (status NOT IN ('failed', 'not_ready') OR next_retry_at IS NOT NULL) AND
        (status NOT IN ('lookup', 'norad_id_missing') OR next_retry_at IS NULL
          OR provider_version < bound_provider_version)
        """
      )
    )

    create(
      index(:provider_ephemeris_states, [:next_retry_at],
        where: "next_retry_at IS NOT NULL",
        name: :provider_ephemeris_states_due_idx
      )
    )
  end

  def down do
    execute("DELETE FROM provider_ephemeris_states WHERE status = 'not_ready'")
    execute("UPDATE provider_ephemeris_states SET next_retry_at = NULL WHERE status <> 'failed'")

    drop(
      index(:provider_ephemeris_states, [:next_retry_at],
        name: :provider_ephemeris_states_due_idx
      )
    )

    drop(constraint(:provider_ephemeris_states, :provider_ephemeris_states_retry))
    drop(constraint(:provider_ephemeris_states, :provider_ephemeris_states_status))

    create(
      constraint(:provider_ephemeris_states, :provider_ephemeris_states_status,
        check: "status IN ('uploaded', 'failed', 'lookup', 'norad_id_missing')"
      )
    )

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

    alter table(:provider_ephemeris_states) do
      remove(:bound_provider_version)
    end
  end
end
