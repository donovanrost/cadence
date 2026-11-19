defmodule Cadence.Repo.Migrations.AddIdentityToGovernedPacketDefinitionFields do
  use Ecto.Migration

  # DECISIONS #73: a telemetry field's semantic identity from the mission-model plan, so the
  # stored binding set carries it (PointCatalog, verifier subject lookup). Nullable: rows written
  # before this have none and fill on their next re-persist. Not part of the binding-set hash.
  def change do
    alter table(:governed_packet_definition_fields) do
      add(:parameter_id, :text)
      add(:qualified_name, :text)
    end
  end
end
