defmodule Cadence.ContactPlanning.FleetAutomationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Comms.Transport

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactPlanApprovals,
    ContactRequirements,
    FleetAutomation,
    FleetAutomationActions,
    FleetPlanningPolicies
  }

  alias Cadence.Contacts.{ProviderReservation, ProviderReservations}
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Spacecraft

  @organization_id "org-fleet-automation"
  @mission_id "mission-fleet-automation"
  @spacecraft_id "spacecraft-fleet-automation"
  @now ~U[2026-07-17 12:00:00.000000Z]

  setup do
    %{organization: organization} =
      persist_mission_scope(@organization_id, @mission_id)

    assert {:ok, _spacecraft} =
             Cadence.persist_spacecraft(
               @organization_id,
               Spacecraft.new(%{
                 spacecraft_id: @spacecraft_id,
                 mission_id: @mission_id,
                 display_name: "Fleet Automation Test"
               })
             )

    assert {:ok, _provider} =
             GroundNetworks.persist_provider(
               @organization_id,
               MissionProvider.new(%{
                 provider_id: "provider-fleet-automation",
                 mission_id: @mission_id,
                 version: 1,
                 display_name: "Fleet automation provider",
                 provider_type: :simulator,
                 base_url: "http://simulator.test",
                 credential_ref: "config://fleet-automation-test",
                 environment_ref: "run-fleet-automation",
                 delivery_policy_document: %{"mode" => "approval_required", "version" => 1}
               })
             )

    assert {:ok, transport} =
             Cadence.persist_transport(
               @organization_id,
               Transport.new(%{
                 transport_id: "transport-fleet-automation",
                 mission_id: @mission_id,
                 version: 1,
                 display_name: "Fleet automation TCP ingress",
                 origin: :direct,
                 direction_capability: :inbound,
                 configuration: %{
                   "mode" => "listen",
                   "direction_capability" => "inbound",
                   "host" => "127.0.0.1",
                   "port" => 5101,
                   "framing_mode" => "raw",
                   "reconnect_policy" => "none",
                   "tls_enabled" => false
                 }
               })
             )

    admin_scope = scope(organization, :organization_admin)
    member_scope = scope(organization, :member)

    assert {:ok, policy, policy_version} =
             FleetPlanningPolicies.create(admin_scope, @mission_id, policy_attrs())

    assert {:ok, _active, ^policy_version, _approval} =
             FleetPlanningPolicies.approve(
               admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               policy_version.version,
               policy_version.content_sha256,
               "Enable exact bounded fleet automation",
               now: @now
             )

    service_identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-stage-5-fleet-automation",
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "Stage 5 fleet automation",
        capabilities: [:mission_admin]
      })

    assert {:ok, issued} = Auth.issue_service_identity(service_identity)
    assert {:ok, service_scope} = Auth.authenticate_api_token(issued.api_token)

    assert {:ok, grant} =
             AutomationGrants.issue(
               admin_scope,
               @mission_id,
               grant_attrs(issued.service_identity),
               now: @now
             )

    assert {:ok, requirement, _version} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(),
               now: @now
             )

    %{
      admin_scope: admin_scope,
      member_scope: member_scope,
      service_scope: service_scope,
      grant: grant,
      transport: transport,
      requirement: requirement
    }
  end

  test "an exact grant plans, approves, and executes once without impersonating an admin",
       context do
    test_pid = self()

    reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
      send(test_pid, {:provider_reserve, attrs["idempotency_key"]})

      reservation =
        ProviderReservation.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          provider_id: provider_id,
          provider_version: attrs["provider_version"],
          provider_account_id: nil,
          provider_account_version: nil,
          provider_account_grant_id: nil,
          provider_account_grant_version: nil,
          contact_requirement_id: attrs["contact_requirement_id"],
          contact_requirement_version: attrs["contact_requirement_version"],
          contact_plan_id: attrs["contact_plan_id"],
          contact_plan_version: attrs["contact_plan_version"],
          contact_opportunity_snapshot_id: attrs["contact_opportunity_snapshot_id"],
          transport_id: attrs["transport_id"],
          transport_version: attrs["transport_version"],
          service_profile_ref: attrs["service_profile_ref"],
          delivery_profile_ref: attrs["delivery_profile_ref"],
          provider_profile_id: attrs["provider_profile_id"],
          provider_profile_version: attrs["provider_profile_version"],
          provider_opportunity_ref: attrs["opportunity_ref"],
          provider_contact_ref: "provider-contact-automation",
          idempotency_key: attrs["idempotency_key"],
          lifecycle_state: :confirmed,
          provider_status: "confirmed",
          pass_phase: :scheduled,
          delivery_state: :ready,
          spacecraft_id: attrs["spacecraft_id"],
          provider_spacecraft_ref: attrs["provider_spacecraft_ref"],
          source_endpoint_refs: attrs["source_endpoint_refs"],
          path_template_ids: attrs["path_template_ids"],
          starts_at: attrs["starts_at"],
          ends_at: attrs["ends_at"],
          request_document: %{"provider_request" => %{"source" => "automation-test"}},
          response_document: %{"status" => "confirmed"}
        })

      with {:ok, persisted} <-
             ProviderReservations.create_attempt(organization_id, reservation) do
        {:ok, %{provider_reservation: persisted}}
      end
    end

    route = route(context.transport)

    opts = [
      now: @now,
      materialize_templates: false,
      list_routes: fn _, _, _ -> {:ok, %{routes: [route], findings: []}} end,
      search_opportunities: fn _, _, _, _, _ ->
        {:ok, %{opportunities: [opportunity()]}}
      end,
      resolve_route: fn _, _, _, _ -> {:ok, route} end,
      reserve: reserve
    ]

    assert {:ok, result} =
             FleetAutomation.plan(
               context.service_scope,
               @mission_id,
               run_attrs(),
               context.grant.automation_grant_id,
               opts
             )

    assert result.planning.run.lifecycle_state == :completed
    assert result.execution.execution.plan.lifecycle_state == :reserved
    assert_received {:provider_reserve, idempotency_key}
    assert is_binary(idempotency_key)

    [approval] =
      ContactPlanApprovals.list(
        @organization_id,
        @mission_id,
        result.planning.plan.contact_plan_id
      )

    assert approval.actor_kind == :service
    assert approval.actor_id == context.service_scope.service_identity.service_identity_id
    assert approval.automation_grant_id == context.grant.automation_grant_id
    assert approval.automation_grant_content_sha256 == context.grant.content_sha256

    assert approval.actor_document["automation_grant"]["approved_by"] ==
             context.admin_scope.user.user_id

    assert Enum.map(result.actions, &{&1.action, &1.lifecycle_state}) == [
             {:plan, :succeeded},
             {:submit, :succeeded},
             {:approve, :succeeded},
             {:execute, :succeeded}
           ]

    assert {:ok, replay} =
             FleetAutomation.run(
               context.service_scope,
               @mission_id,
               result.planning.run.fleet_planning_run_id,
               context.grant.automation_grant_id,
               opts
             )

    assert replay.execution.execution.plan.lifecycle_state == :reserved
    assert length(replay.actions) == 4
    refute_received {:provider_reserve, _idempotency_key}

    plan_action = Enum.find(replay.actions, &(&1.action == :plan))

    assert {:error, :fleet_automation_action_already_complete} =
             FleetAutomationActions.complete(
               context.service_scope,
               plan_action.fleet_automation_action_id,
               :failed,
               %{},
               %{"code" => "must_not_overwrite_success"},
               now: DateTime.add(@now, 1, :second)
             )

    [persisted_plan_action] =
      FleetAutomationActions.list(
        @organization_id,
        @mission_id,
        result.planning.run.fleet_planning_run_id
      )
      |> Enum.filter(&(&1.action == :plan))

    assert persisted_plan_action.lifecycle_state == :succeeded
    assert persisted_plan_action.result_document == plan_action.result_document
  end

  test "a non-contiguous grant stops at the last permitted boundary", context do
    assert {:ok, _revoked} =
             AutomationGrants.revoke(
               context.admin_scope,
               @mission_id,
               context.grant.automation_grant_id,
               context.grant.content_sha256,
               "Replace with a deliberately non-contiguous grant",
               now: @now
             )

    assert {:ok, advisory_grant} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_scope.service_identity, %{
                 allowed_actions: [:plan, :execute]
               }),
               now: @now
             )

    route = route(context.transport)

    assert {:ok, result} =
             FleetAutomation.plan(
               context.service_scope,
               @mission_id,
               run_attrs(),
               advisory_grant.automation_grant_id,
               now: @now,
               materialize_templates: false,
               list_routes: fn _, _, _ -> {:ok, %{routes: [route], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    assert result.planning.plan.lifecycle_state == :draft
    assert result.submission == nil
    assert result.approval == nil
    assert result.execution == nil

    assert Enum.map(
             FleetAutomationActions.list(
               @organization_id,
               @mission_id,
               result.planning.run.fleet_planning_run_id
             ),
             & &1.action
           ) == [:plan]
  end

  defp run_attrs do
    %{
      horizon_start: @now,
      horizon_end: DateTime.add(@now, 14_400, :second),
      trigger_kind: :scheduled
    }
  end

  defp requirement_attrs do
    %{
      spacecraft_id: @spacecraft_id,
      service_direction: :downlink,
      contact_intent: "bounded_automatic_payload_downlink",
      earliest_start: DateTime.add(@now, 3_600, :second),
      latest_end: DateTime.add(@now, 10_800, :second),
      success_measure: :minimum_duration,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: nil,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "bounded_automatic"},
      rationale: "Prove exact-grant service execution",
      metadata: %{}
    }
  end

  defp route(transport) do
    %{
      route_key: "route-fleet-automation",
      spacecraft_id: @spacecraft_id,
      provider_spacecraft_ref: "SC-FLEET-AUTOMATION",
      source_endpoint_id: "source-fleet-automation",
      routing_rule_id: "routing-fleet-automation",
      link_assignment_id: "link-fleet-automation",
      path_template_id: "path-fleet-automation",
      path_template_version: 1,
      transport_id: "transport-fleet-automation",
      transport_version: 1,
      provider_id: "provider-fleet-automation",
      provider_version: 1,
      provider_account_id: "provider-account-automation",
      provider_account_version: 1,
      provider_account_grant_id: "provider-grant-automation",
      provider_account_grant_version: 1,
      provider_profile_id: transport.materialized_provider_profile_id,
      provider_profile_version: 1,
      service_profile_ref: %{"id" => "service-downlink", "version" => 1},
      delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 1},
      delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
      provider_display_name: "Fleet provider",
      service_display_name: "Realtime downlink",
      delivery_display_name: "Cadence primary",
      route_display_name: "Fleet automation route",
      client: __MODULE__.FakeClient
    }
  end

  defp opportunity do
    %{
      "id" => "opportunity-fleet-automation",
      "spacecraft_ref" => "SC-FLEET-AUTOMATION",
      "ground_station_ref" => "station-fleet-automation",
      "antenna_or_service_pool_ref" => "pool-fleet-automation",
      "service_profile_ref" => "service-downlink",
      "starts_at" => @now |> DateTime.add(3_600, :second) |> DateTime.to_iso8601(),
      "ends_at" => @now |> DateTime.add(4_500, :second) |> DateTime.to_iso8601(),
      "expires_at" => @now |> DateTime.add(1_800, :second) |> DateTime.to_iso8601(),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 1_000_000_000},
      "estimated_cost" => %{"amount_micros" => 100, "currency" => "USD"},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{
          "status" => "current",
          "valid_until" => @now |> DateTime.add(10_800, :second) |> DateTime.to_iso8601()
        }
      }
    }
  end

  defp grant_attrs(service_identity, overrides \\ %{}) do
    Map.merge(
      %{
        service_identity_id: service_identity.service_identity_id,
        allowed_actions: [:plan, :repair, :submit, :approve, :execute],
        maximum_horizon_seconds: 14_400,
        maximum_contacts: 5,
        maximum_estimated_cost_micros: 500,
        currency: "USD",
        maximum_execution_concurrency: 2,
        valid_from: @now,
        valid_until: DateTime.add(@now, 86_400, :second),
        approval_reason: "Bound unattended Stage 5 operations"
      },
      overrides
    )
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 86_400,
        "requirement_concurrency" => 4,
        "provider_search_concurrency" => 2,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{},
      resource_policy_document: %{},
      budget_quota_document: %{
        "max_contacts" => 10,
        "max_estimated_cost_micros" => 1_000,
        "currency" => "USD",
        "per_provider" => %{},
        "critical_contact_reserve" => 0,
        "critical_cost_reserve_micros" => 0
      },
      redundancy_document: %{},
      automation_repair_document: %{
        "mode" => "bounded_automatic",
        "execution_concurrency" => 4,
        "max_repair_attempts" => 3,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => true
      }
    }
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "fleet-automation-user-#{role}",
        email: "fleet-automation-#{role}@example.test",
        display_name: "Fleet Automation #{role}"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
