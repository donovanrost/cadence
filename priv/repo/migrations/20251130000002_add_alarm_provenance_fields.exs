defmodule Cadence.Repo.Migrations.AddAlarmProvenanceFields do
  use Ecto.Migration

  def change do
    alter table(:alarms) do
      # Source provenance - where did this alarm originate?
      # :rule - from an AlarmRule match
      # :mission_db - from Mission DB limits (implicit)
      # :manual - manually created by operator
      add :source_origin, :string, default: "rule"

      # Which DefinitionSet version's limits triggered this alarm?
      # Useful for understanding alarm behavior across C&T database versions
      add :source_definition_set_id,
        references(:mdb_definition_sets, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:alarms, [:source_origin])
    create index(:alarms, [:source_definition_set_id])
  end
end
