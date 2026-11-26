defmodule Cadence.Repo.Migrations.IndexSpacecraftNameCursor do
  use Ecto.Migration

  # The names read (#847) and the Setup directory (#796) page a mission's spacecraft by name,
  # then id: this is their keyset, so a page is an index range scan, not a sort of the fleet.
  def change do
    create(
      index(:mission_spacecraft, [:organization_id, :mission_id, :display_name, :spacecraft_id],
        name: :mission_spacecraft_name_cursor_idx
      )
    )
  end
end
