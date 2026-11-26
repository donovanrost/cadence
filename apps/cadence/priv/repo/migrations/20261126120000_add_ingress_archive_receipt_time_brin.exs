defmodule Cadence.Repo.Migrations.AddIngressArchiveReceiptTimeBrin do
  use Ecto.Migration

  # Retention (#694) finds the expired end of the index by age alone, and every other index leads
  # with the mission. Rows arrive in time order, so a BRIN index is tiny and enough.
  def change do
    create index(:ingress_archive_evidence_entries, [:receipt_time], using: :brin)
  end
end
