defmodule Cadence.Repo.Migrations.WidenCommandApprovalReason do
  use Ecto.Migration

  def change do
    alter table(:command_approvals) do
      modify(:reason, :text, from: :string)
    end
  end
end
