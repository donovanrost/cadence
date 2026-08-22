defmodule Cadence.Repo.Migrations.AddTagsToProcedures do
  use Ecto.Migration

  def change do
    alter table(:procedures) do
      add :tags, {:array, :string}, default: []
    end

    # GIN index for efficient tag containment queries
    create index(:procedures, [:tags], using: :gin, name: :procedures_tags_gin_idx)
  end
end
