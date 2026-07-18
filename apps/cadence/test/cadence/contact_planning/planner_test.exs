defmodule Cadence.ContactPlanning.PlannerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, Planner}
  alias Cadence.GroundNetworks.ProviderError
  alias Cadence.Spacecraft

  @organization_id "org-contact-planner"
  @mission_id "mission-contact-planner"
  @spacecraft_id "spacecraft-contact-planner"
  @now ~U[2026-07-16 20:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    assert {:ok, _spacecraft} =
             Cadence.persist_spacecraft(
               @organization_id,
               Spacecraft.new(%{
                 spacecraft_id: @spacecraft_id,
                 mission_id: mission.mission_id,
                 display_name: "Asteria"
               })
             )

    member_scope = scope(organization, :member)

    assert {:ok, requirement, version} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(),
               now: @now
             )

    %{
      member_scope: member_scope,
      requirement: requirement,
      requirement_version: version
    }
  end

  test "persists mixed provider search outcomes and immutable eligible snapshots", context do
    test_pid = self()
    route_alpha = route("alpha")
    route_beta = route("beta")

    assert {:ok, result} =
             Planner.run(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               now: @now,
               list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
                 {:ok,
                  %{
                    routes: [route_beta, route_alpha],
                    findings: [
                      %{
                        code: :provider_route_not_ready,
                        message: "Backup route is not ready.",
                        resource_id: "routing-backup",
                        remediation: :comms
                      }
                    ]
                  }}
               end,
               search_opportunities: fn _organization_id,
                                        _mission_id,
                                        route_key,
                                        _window,
                                        _opts ->
                 send(test_pid, {:searched, route_key})

                 if route_key == route_alpha.route_key do
                   {:ok,
                    %{
                      route: route_alpha,
                      provider_evidence: %{
                        "orbit_readiness" => %{
                          "status" => "current",
                          "ephemeris_ref" => "ephemeris-alpha-v3"
                        }
                      },
                      opportunities: [opportunity("alpha", 3_600, 4_500)]
                    }}
                 else
                   {:ok,
                    %{
                      route: route_beta,
                      provider_evidence: %{
                        "orbit_readiness" => %{
                          "status" => "current",
                          "ephemeris_ref" => "ephemeris-beta-v7"
                        }
                      },
                      opportunities: []
                    }}
                 end
               end
             )

    assert result.run.lifecycle_state == :partial
    assert result.run.summary_document["search_count"] == 3
    assert result.run.summary_document["opportunity_count"] == 1
    assert length(result.searches) == 3
    assert [snapshot] = result.snapshots
    assert snapshot.eligible
    assert snapshot.route_binding_document["provider_id"] == route_alpha.provider_id
    assert snapshot.provider_evidence_document["id"] == "opportunity-alpha"
    refute Map.has_key?(snapshot.route_binding_document, "client")

    alpha_route_key = route_alpha.route_key
    beta_route_key = route_beta.route_key
    assert_received {:searched, ^alpha_route_key}
    assert_received {:searched, ^beta_route_key}

    assert Enum.map(result.searches, & &1.outcome) == [
             :not_ready,
             :succeeded_with_results,
             :succeeded_without_results
           ]

    assert Enum.at(result.searches, 1).readiness_document["orbit_readiness"]["ephemeris_ref"] ==
             "ephemeris-alpha-v3"

    assert Enum.at(result.searches, 2).readiness_document == %{
             "orbit_readiness" => %{
               "ephemeris_ref" => "ephemeris-beta-v7",
               "status" => "current"
             }
           }

    assert Planner.list_runs(
             @organization_id,
             @mission_id,
             context.requirement.contact_requirement_id
           ) == [result.run]

    assert Planner.list_searches(
             @organization_id,
             @mission_id,
             result.run.contact_planning_run_id
           ) ==
             result.searches

    assert Planner.list_snapshots(
             @organization_id,
             @mission_id,
             result.run.contact_planning_run_id
           ) == result.snapshots
  end

  test "identical duplicate opportunities converge but identity collisions fail the route",
       context do
    route = route("duplicate")
    opportunity = opportunity("same", 3_600, 4_500)

    assert {:ok, duplicate_result} =
             run_with(context, [route], fn -> [opportunity, opportunity] end)

    assert duplicate_result.run.lifecycle_state == :completed
    assert length(duplicate_result.snapshots) == 1
    assert hd(duplicate_result.searches).opportunity_count == 1

    collision = Map.put(opportunity, "ends_at", iso(4_800))

    assert {:ok, collision_result} =
             run_with(context, [route], fn -> [opportunity, collision] end)

    assert collision_result.run.lifecycle_state == :failed
    assert collision_result.snapshots == []
    assert hd(collision_result.searches).outcome == :failed

    assert hd(collision_result.searches).error_document == %{
             "code" => "provider_opportunity_identity_collision"
           }
  end

  test "all failed providers produce a failed run with bounded secret-free errors", context do
    route = route("failure")

    assert {:ok, result} =
             Planner.run(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               now: @now,
               list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
                 {:ok, %{routes: [route], findings: []}}
               end,
               search_opportunities: fn _organization_id,
                                        _mission_id,
                                        _route_key,
                                        _window,
                                        _opts ->
                 {:error,
                  ProviderError.invalid("credential invalid", %{
                    "api_token" => "should-never-persist"
                  })}
               end
             )

    assert result.run.lifecycle_state == :failed
    assert result.snapshots == []
    assert [search] = result.searches

    assert search.error_document == %{
             "category" => "invalid_request",
             "code" => "invalid_request",
             "provider_evidence" => %{"api_token" => "[REDACTED]"}
           }

    refute inspect(result) =~ "should-never-persist"
    refute inspect(result) =~ "credential invalid"
  end

  test "provider-owned expired orbit evidence is durable not-ready evidence", context do
    route = route("expired-orbit")

    assert {:ok, result} =
             Planner.run(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               now: @now,
               list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
                 {:ok, %{routes: [route], findings: []}}
               end,
               search_opportunities: fn _organization_id,
                                        _mission_id,
                                        _route_key,
                                        _window,
                                        _opts ->
                 {:error,
                  ProviderError.from_response(422, %{
                    "error" => %{
                      "code" => "orbit_not_ready",
                      "detail" => "provider orbit data is not ready",
                      "evidence" => %{
                        "orbit_readiness" => %{
                          "status" => "expired",
                          "ephemeris_ref" => "ephemeris-expired-v1",
                          "valid_until" => iso(-60),
                          "api_token" => "must-not-persist"
                        }
                      }
                    }
                  })}
               end
             )

    assert result.run.lifecycle_state == :failed
    assert result.snapshots == []
    assert [search] = result.searches
    assert search.outcome == :not_ready

    assert search.readiness_document == %{
             "orbit_readiness" => %{
               "api_token" => "[REDACTED]",
               "ephemeris_ref" => "ephemeris-expired-v1",
               "status" => "expired",
               "valid_until" => iso(-60)
             }
           }

    assert search.error_document["code"] == "provider_not_ready"
    refute inspect(search) =~ "must-not-persist"
  end

  test "provider constraints avoid external search and preserve an explicit outcome", context do
    assert {:ok, requirement, version} =
             ContactRequirements.version(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               %{
                 provider_constraints_document: %{
                   "allowed" => ["provider-alpha"],
                   "excluded" => []
                 }
               },
               now: DateTime.add(@now, 1, :second)
             )

    test_pid = self()

    assert {:ok, result} =
             Planner.run(
               context.member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               version.version,
               now: @now,
               list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
                 {:ok, %{routes: [route("alpha"), route("beta")], findings: []}}
               end,
               search_opportunities: fn _organization_id,
                                        _mission_id,
                                        route_key,
                                        _window,
                                        _opts ->
                 send(test_pid, {:searched, route_key})
                 {:ok, %{opportunities: []}}
               end
             )

    assert_received {:searched, "route-alpha"}
    refute_received {:searched, "route-beta"}

    assert Enum.map(result.searches, & &1.outcome) == [
             :succeeded_without_results,
             :excluded_by_requirement
           ]
  end

  test "route-resolution failure completes durable failed evidence instead of stranding a running run",
       context do
    assert {:ok, result} =
             Planner.run(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               now: @now,
               list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
                 {:error, :provider_route_store_unavailable}
               end
             )

    assert result.run.lifecycle_state == :failed
    assert result.run.completed_at == @now
    assert result.run.summary_document["search_count"] == 0

    assert result.run.summary_document["failure"] == %{
             "code" => "contact_planning_route_resolution_failed"
           }

    assert result.searches == []
    assert result.snapshots == []
  end

  test "closed and stale Requirements cannot start another planning run", context do
    assert {:ok, _closed} =
             ContactRequirements.close(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               "No longer needed",
               now: DateTime.add(@now, 2, :second)
             )

    assert {:error, :contact_requirement_not_active} =
             Planner.run(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               now: @now
             )

    assert Planner.list_runs(
             @organization_id,
             @mission_id,
             context.requirement.contact_requirement_id
           ) == []
  end

  defp run_with(context, routes, opportunities_fun) do
    Planner.run(
      context.member_scope,
      @mission_id,
      context.requirement.contact_requirement_id,
      1,
      now: @now,
      list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
        {:ok, %{routes: routes, findings: []}}
      end,
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window, _opts ->
        {:ok, %{opportunities: opportunities_fun.()}}
      end
    )
  end

  defp route(suffix) do
    %{
      route_key: "route-#{suffix}",
      spacecraft_id: @spacecraft_id,
      provider_spacecraft_ref: "SC-#{suffix}",
      source_endpoint_id: "source-#{suffix}",
      routing_rule_id: "routing-#{suffix}",
      link_assignment_id: "link-#{suffix}",
      path_template_id: "path-#{suffix}",
      path_template_version: 1,
      transport_id: "transport-#{suffix}",
      transport_version: 2,
      provider_id: "provider-#{suffix}",
      provider_version: 3,
      provider_account_id: "account-#{suffix}",
      provider_account_version: 4,
      provider_account_grant_id: "grant-#{suffix}",
      provider_account_grant_version: 5,
      provider_profile_id: "runtime-profile-#{suffix}",
      provider_profile_version: 6,
      service_profile_ref: %{"id" => "service-downlink", "version" => 7},
      delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 8},
      provider_display_name: "Provider #{suffix}",
      service_display_name: "Realtime downlink",
      delivery_display_name: "Cadence primary",
      route_display_name: "Route #{suffix}",
      client: Module.concat(["Client#{suffix}"])
    }
  end

  defp opportunity(suffix, starts_offset, ends_offset) do
    %{
      "id" => "opportunity-#{suffix}",
      "spacecraft_ref" => "SC-#{suffix}",
      "ground_station_ref" => "station-#{suffix}",
      "antenna_or_service_pool_ref" => "pool-#{suffix}",
      "service_profile_ref" => "service-downlink",
      "starts_at" => iso(starts_offset),
      "ends_at" => iso(ends_offset),
      "expires_at" => iso(3_000),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{
          "status" => "current",
          "valid_until" => iso(28_800)
        },
        "provider_api_token" => "must-be-redacted"
      }
    }
  end

  defp requirement_attrs do
    %{
      spacecraft_id: @spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(@now, 3_600, :second),
      latest_end: DateTime.add(@now, 28_800, :second),
      success_measure: :minimum_data_volume,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: 1_500_000_000,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "Downlink recorder",
      metadata: %{}
    }
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "contact-planner-user-#{role}",
        email: "contact-planner-#{role}@example.test",
        display_name: "Contact Planner #{role}"
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

  defp iso(offset), do: DateTime.add(@now, offset, :second) |> DateTime.to_iso8601()
end
