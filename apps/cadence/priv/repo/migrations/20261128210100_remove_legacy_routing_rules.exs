defmodule Cadence.Repo.Migrations.RemoveLegacyRoutingRules do
  use Ecto.Migration

  def up do
    execute("DELETE FROM comms_routing_rules WHERE origin = 'legacy'")
    execute("ALTER TABLE comms_routing_rules ALTER COLUMN origin SET DEFAULT 'spacecraft'")

    create(
      constraint(:comms_routing_rules, :comms_routing_rules_origin_check,
        check: "origin IN ('profile', 'spacecraft')"
      )
    )
  end

  def down do
    drop(constraint(:comms_routing_rules, :comms_routing_rules_origin_check))
    execute("ALTER TABLE comms_routing_rules ALTER COLUMN origin SET DEFAULT 'legacy'")
  end
end
