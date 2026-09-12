defmodule Cadence.Repo.Migrations.WidenDerivedDefinitionExpression do
  use Ecto.Migration

  def change do
    alter table(:governed_derived_telemetry_definitions) do
      modify(:expression, :text, from: :string)
    end
  end
end
