defmodule Cadence.Repo.Migrations.AddPreparedSendReconciliation do
  use Ecto.Migration

  def change do
    alter table(:transport_action_requests) do
      add(:reconciliation_evidence, :map, null: false, default: %{})
    end
  end
end
