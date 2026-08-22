defmodule Cadence.Repo.Migrations.DecoupleProtocolAnomaliesFromRawEvidence do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE protocol_anomalies
    DROP CONSTRAINT IF EXISTS protocol_anomalies_evidence_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE protocol_anomalies
    ADD CONSTRAINT protocol_anomalies_evidence_id_fkey
    FOREIGN KEY (evidence_id)
    REFERENCES ingress_raw_evidence (evidence_id)
    """)
  end
end
