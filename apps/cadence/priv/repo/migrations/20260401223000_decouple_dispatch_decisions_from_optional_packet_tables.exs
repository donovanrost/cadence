defmodule Cadence.Repo.Migrations.DecoupleDispatchDecisionsFromOptionalPacketTables do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE application_dispatch_decisions
    DROP CONSTRAINT IF EXISTS application_dispatch_decisions_packet_id_fkey
    """)

    execute("""
    ALTER TABLE application_dispatch_decisions
    DROP CONSTRAINT IF EXISTS application_dispatch_decisions_evidence_id_fkey
    """)
  end

  def down do
    execute("""
    ALTER TABLE application_dispatch_decisions
    ADD CONSTRAINT application_dispatch_decisions_packet_id_fkey
    FOREIGN KEY (packet_id)
    REFERENCES protocol_packet_records(packet_id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE application_dispatch_decisions
    ADD CONSTRAINT application_dispatch_decisions_evidence_id_fkey
    FOREIGN KEY (evidence_id)
    REFERENCES ingress_raw_evidence(evidence_id)
    ON DELETE CASCADE
    """)
  end
end
