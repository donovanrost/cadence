defmodule Cadence.Repo.Migrations.CreateDashboardLayouts do
  use Ecto.Migration

  def change do
    create table(:dashboard_layouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :is_default, :boolean, default: false, null: false

      # Golden Layout state (panel positions, sizes)
      add :frame_layout, :map

      # gridstack widget positions and configs
      add :widgets, {:array, :map}, default: [], null: false

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :mission_id, references(:missions, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:dashboard_layouts, [:user_id])
    create index(:dashboard_layouts, [:mission_id])
    create unique_index(:dashboard_layouts, [:user_id, :mission_id, :name])
  end
end
