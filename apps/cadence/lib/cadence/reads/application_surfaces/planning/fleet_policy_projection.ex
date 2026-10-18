defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetPolicyProjection do
  @moduledoc "Semantic policy and grant evidence; presentation belongs to Planning's frontend."
  def values(nil),
    do: %{
      max_horizon_seconds: 86_400,
      requirement_concurrency: 8,
      provider_search_concurrency: 4,
      reuse_freshness_seconds: 300,
      max_contacts: 500,
      max_estimated_cost_micros: nil,
      currency: nil,
      critical_contact_reserve: 0,
      automation_mode: "advisory",
      execution_concurrency: 4,
      max_repair_attempts: 3,
      repair_horizon_seconds: 86_400,
      automatic_submission: false,
      distinct_provider_required: false,
      distinct_station_required: false,
      distinct_service_pool_required: false,
      default_exclusive_capacity: 1
    }

  def values(v),
    do: %{
      max_horizon_seconds: v.horizon_document["max_horizon_seconds"],
      requirement_concurrency: v.horizon_document["requirement_concurrency"],
      provider_search_concurrency: v.horizon_document["provider_search_concurrency"],
      reuse_freshness_seconds: v.horizon_document["reuse_freshness_seconds"],
      max_contacts: v.budget_quota_document["max_contacts"],
      max_estimated_cost_micros: v.budget_quota_document["max_estimated_cost_micros"],
      currency: v.budget_quota_document["currency"],
      critical_contact_reserve: v.budget_quota_document["critical_contact_reserve"],
      automation_mode: v.automation_repair_document["mode"],
      execution_concurrency: v.automation_repair_document["execution_concurrency"],
      max_repair_attempts: v.automation_repair_document["max_repair_attempts"],
      repair_horizon_seconds: v.automation_repair_document["repair_horizon_seconds"],
      automatic_submission: v.automation_repair_document["automatic_submission"],
      distinct_provider_required: v.redundancy_document["distinct_provider_required"],
      distinct_station_required: v.redundancy_document["distinct_station_required"],
      distinct_service_pool_required: v.redundancy_document["distinct_service_pool_required"],
      default_exclusive_capacity: v.resource_policy_document["default_exclusive_capacity"]
    }

  def reference(v),
    do: %{
      contract_version: 1,
      organization_id: v.organization_id,
      mission_id: v.mission_id,
      policy_id: v.fleet_planning_policy_id,
      policy_version: v.version,
      content_sha256: v.content_sha256
    }

  def version(nil), do: nil
  def version(v), do: %{reference: reference(v), values: values(v)}

  def grant(g),
    do: %{
      reference: %{
        contract_version: 1,
        organization_id: g.organization_id,
        mission_id: g.mission_id,
        grant_id: g.automation_grant_id,
        content_sha256: g.content_sha256
      },
      service_identity_id: g.service_identity_id,
      policy_id: g.fleet_planning_policy_id,
      policy_version: g.fleet_planning_policy_version,
      state: Atom.to_string(g.lifecycle_state),
      actions: Enum.map(g.allowed_actions, &Atom.to_string/1),
      maximum_horizon_seconds: g.maximum_horizon_seconds,
      maximum_contacts: g.maximum_contacts,
      maximum_execution_concurrency: g.maximum_execution_concurrency,
      maximum_estimated_cost_micros: g.maximum_estimated_cost_micros,
      currency: g.currency,
      valid_from: DateTime.to_iso8601(g.valid_from),
      valid_until: DateTime.to_iso8601(g.valid_until),
      approved_at: DateTime.to_iso8601(g.approved_at),
      approval_reason: g.approval_reason,
      revoked_at: g.revoked_at && DateTime.to_iso8601(g.revoked_at),
      revocation_reason: g.revocation_reason
    }
end
