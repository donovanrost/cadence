defmodule Cadence.Repo.Migrations.CompositionPins do
  use Ecto.Migration

  alias Cadence.MissionModels.PinBackfill

  # D3 (#544; design docs/apogee/domain/mission-composition-design.md §3): profiles and per-craft
  # overrides pin a mission composition. Profiles gain `composition_id`; a per-craft pin is the
  # override path `composition_id`. Then, in this transaction, every catalog pin gets its
  # one-layer composition (PinBackfill), which raises rather than leave a pin without one.
  # `catalog_revision_id` stays, as provenance. A profile change staged before this landing reads
  # stale at apply and must be re-staged (#108, ca-security and domain on #544).
  def up do
    alter table(:mission_spacecraft_types) do
      add(:composition_id, :string)
    end

    # What the submit's preview selected per pinned composition (%{composition_id => revision_id
    # or the reason none is selectable}); the apply selects again under the activation lock and
    # refuses restage_needed on any difference.
    alter table(:mission_config_change_sets) do
      add(:selections, :map)
    end

    flush()
    PinBackfill.run(repo())
  end

  def down do
    execute("DELETE FROM spacecraft_config_overrides WHERE path = 'composition_id'")

    alter table(:mission_config_change_sets) do
      remove(:selections)
    end

    alter table(:mission_spacecraft_types) do
      remove(:composition_id)
    end
  end
end
