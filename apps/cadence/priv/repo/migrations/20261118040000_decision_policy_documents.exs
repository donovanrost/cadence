defmodule Cadence.Repo.Migrations.DecisionPolicyDocuments do
  use Ecto.Migration

  # M2 (director 11-18): a contact plan approval, a plan submission and a fleet planning policy
  # approval record the approval policy in force at decision time, so per-kind approval policies
  # (DECISIONS #111) carry over from what each decision was made under. Additive and nullable:
  # rows decided before this keep NULL (policy not recorded). P3's append-only triggers don't
  # block DDL; nothing updates existing rows.
  def change do
    for table <- [
          :contact_plan_approvals,
          :contact_plan_submissions,
          :fleet_planning_policy_approvals
        ] do
      alter table(table) do
        add(:policy_document, :map)
      end
    end
  end
end
