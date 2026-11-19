defmodule Cadence.Reads.PlanRepairHeader do
  @moduledoc """
  The Re-plan screen's header for a plan (ux U76; console K2): what a repair started now would
  cover and how many attempts the planning policy has left, before anything starts.

  `nil` when the plan has no source run to repair from. Otherwise `%{window: %{from, to},
  horizon_seconds, attempts: %{used, max}, available, cause}`: the window a repair POSTed without
  one covers (now to the source run's horizon end); the policy's `repair_horizon_seconds` and
  `max_repair_attempts`; `used`, the repairs already made on the plan's chain; `available`, false
  when none are left or nothing is lost to repair. `cause` is nil for now (U76 words that case).
  """

  alias Cadence.ContactPlanning.{FleetPlanningPolicies, FleetRepairs, RepairChain}

  @spec for_plan(binary(), binary(), binary(), DateTime.t()) :: map() | nil
  def for_plan(organization_id, mission_id, plan_id, %DateTime{} = now) do
    with {:ok, run} <- RepairChain.head_run(organization_id, mission_id, plan_id),
         {:ok, chain} <- RepairChain.load(organization_id, mission_id, plan_id),
         {:ok, next} <- FleetRepairs.next_attempt(organization_id, mission_id, run),
         {:ok, _policy, policy} <- FleetPlanningPolicies.fetch_active(organization_id, mission_id) do
      document = policy.automation_repair_document
      max = document["max_repair_attempts"]

      %{
        window: %{from: now, to: run.horizon_end},
        horizon_seconds: document["repair_horizon_seconds"],
        attempts: %{used: next - 1, max: max},
        available: next <= max and RepairChain.lost_bookings(chain) != [],
        cause: nil
      }
    else
      _not_repairable -> nil
    end
  end
end
