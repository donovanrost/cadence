defmodule Cadence.Management.Contacts do
  @moduledoc """
  Management-plane boundary for Contact requirements, plans, and approvals.

  The underlying domain-first contexts remain in place while migration is in
  progress, but callers cross the plane through this API.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlanApprovals,
    ContactPlans,
    ContactRequirements
  }

  alias Cadence.Management.Contacts.ApprovedContactPlan

  defdelegate create_plan(current_scope, mission_id, attrs, opts \\ []),
    to: ContactPlans,
    as: :create

  defdelegate version_plan(current_scope, mission_id, plan_id, version, attrs, opts \\ []),
    to: ContactPlans,
    as: :version

  defdelegate submit_plan(current_scope, mission_id, plan_id, version, reason, opts \\ []),
    to: ContactPlans,
    as: :submit

  defdelegate fetch_plan(organization_id, mission_id, plan_id), to: ContactPlans, as: :fetch
  defdelegate list_plans(organization_id, mission_id, opts \\ []), to: ContactPlans, as: :list

  defdelegate selected_opportunities(organization_id, mission_id, plan_id, version),
    to: ContactPlans,
    as: :selected_snapshots

  defdelegate fetch_requirement_version(organization_id, mission_id, requirement_id, version),
    to: ContactRequirements,
    as: :fetch_version

  defdelegate list_approvals(organization_id, mission_id, plan_id),
    to: ContactPlanApprovals,
    as: :list

  @spec fetch_approved_plan(binary(), binary(), binary()) ::
          {:ok, ApprovedContactPlan.t()} | {:error, term()}
  def fetch_approved_plan(organization_id, mission_id, plan_id) do
    with {:ok, plan, _current_version} <- ContactPlans.fetch(organization_id, mission_id, plan_id),
         version when is_integer(version) <- plan.approved_version,
         {:ok, approved_version} <-
           ContactPlans.fetch_version(organization_id, mission_id, plan_id, version),
         %{} = approval <-
           approved_decision(
             ContactPlanApprovals.list(organization_id, mission_id, plan_id),
             approved_version
           ) do
      snapshot_ids =
        ContactPlans.bookable_snapshots(organization_id, mission_id, plan_id, version)
        |> Enum.map(& &1.contact_opportunity_snapshot_id)

      ApprovedContactPlan.new(plan, approved_version, approval, snapshot_ids)
    else
      nil -> {:error, :approved_contact_plan_not_found}
      _not_approved -> {:error, :contact_plan_not_approved}
    end
  end

  @spec approve_plan(
          Scope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) :: {:ok, ApprovedContactPlan.t()} | {:error, term()}
  def approve_plan(
        %Scope{} = current_scope,
        mission_id,
        plan_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    with {:ok, plan, version, approval} <-
           ContactPlanApprovals.approve(
             current_scope,
             mission_id,
             plan_id,
             expected_version,
             expected_hash,
             reason,
             opts
           ) do
      snapshot_ids =
        ContactPlans.bookable_snapshots(
          plan.organization_id,
          plan.mission_id,
          plan.contact_plan_id,
          version.version
        )
        |> Enum.map(& &1.contact_opportunity_snapshot_id)

      ApprovedContactPlan.new(plan, version, approval, snapshot_ids)
    end
  end

  defdelegate reject_plan(
                current_scope,
                mission_id,
                plan_id,
                expected_version,
                expected_hash,
                reason,
                opts \\ []
              ),
              to: ContactPlanApprovals,
              as: :reject

  defp approved_decision(approvals, version) do
    Enum.find(approvals, fn approval ->
      approval.decision == :approved and approval.contact_plan_version == version.version and
        approval.content_sha256 == version.content_sha256
    end)
  end
end
