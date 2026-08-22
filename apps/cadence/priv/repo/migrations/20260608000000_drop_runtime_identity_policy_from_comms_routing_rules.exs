defmodule Cadence.Repo.Migrations.DropRuntimeIdentityPolicyFromCommsRoutingRules do
  use Ecto.Migration

  def change do
    alter table(:comms_routing_rules) do
      remove_if_exists(:runtime_identity_policy, :string)
    end
  end
end
