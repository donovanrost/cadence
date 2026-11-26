defmodule Cadence.Repo.Migrations.CompositionPins do
  use Ecto.Migration

  # D3 (#544; design docs/apogee/domain/mission-composition-design.md §3): profiles and per-craft
  # overrides pin a mission composition. Profiles gain `composition_id`; a per-craft pin is the
  # override path `composition_id`. `catalog_revision_id` stays, derived by Cadence from the
  # composition at staging, until phase 4 (#448–#450) re-keys its runtime readers. No backfill:
  # dev data is disposable, so drop and reseed.
  def change do
    alter table(:mission_spacecraft_types) do
      add(:composition_id, :string)
    end

    # What the submit's preview selected per pinned composition (%{composition_id => revision_id
    # or the reason none is selectable}); the apply selects again under the activation lock and
    # refuses restage_needed on any difference.
    alter table(:mission_config_change_sets) do
      add(:selections, :map)
    end
  end
end
