defmodule Cadence.ContactPlanning.ContactPlanExecutionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.Transport

  alias Cadence.ContactPlanning.{
    ContactPlanApprovals,
    ContactPlanExecutions,
    ContactPlans,
    ContactRequirements,
    Planner
  }

  alias Cadence.Contacts.{PathTemplate, ProviderBooking, ProviderReservations}
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{MissionProvider, ProviderError}
  alias Cadence.Spacecraft
  alias Cadence.TestSupport.FakeProviderClient

  @now ~U[2026-07-16 20:00:00.000000Z]

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-contact-plan-execution-#{suffix}"
    mission_id = "mission-contact-plan-execution-#{suffix}"
    spacecraft_id = "spacecraft-contact-plan-execution-#{suffix}"

    %{organization: organization} = persist_mission_scope(organization_id, mission_id)

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               organization_id,
               Spacecraft.new(%{
                 spacecraft_id: spacecraft_id,
                 mission_id: mission_id,
                 display_name: "Asteria"
               })
             )

    provider = persist_provider!(organization_id, mission_id, suffix)

    assert {:ok, transport} =
             Cadence.persist_transport(
               organization_id,
               Transport.new(%{
                 transport_id: "provider-transport-#{suffix}",
                 mission_id: mission_id,
                 display_name: "Simulator telemetry ingress",
                 origin: :provider_managed,
                 mission_provider_id: provider.provider_id,
                 mission_provider_version: provider.version,
                 service_profile_ref: %{
                   "id" => "service-realtime-ttc-downlink",
                   "version" => 3
                 },
                 delivery_profile_ref: %{
                   "id" => "delivery-cadence-primary",
                   "version" => 7
                 }
               })
             )

    assert {:ok, runtime_profile} =
             Cadence.fetch_provider_profile(
               organization_id,
               mission_id,
               transport.materialized_provider_profile_id
             )

    assert {:ok, path_template} =
             Cadence.persist_path_template(
               organization_id,
               PathTemplate.new(%{
                 path_template_id: "simulator-downlink-#{suffix}",
                 mission_id: mission_id,
                 path_id: "simulator-downlink-path-#{suffix}",
                 direction: :downlink,
                 selection_role: :selected,
                 source_endpoint_ref: "source-endpoint-#{suffix}",
                 provider_profile_refs: [
                   %{
                     "provider_profile_id" => runtime_profile.provider_profile_id,
                     "version" => runtime_profile.version
                   }
                 ]
               })
             )

    member_scope = scope(organization, :member, suffix)
    admin_scope = scope(organization, :organization_admin, suffix)

    route =
      route(%{
        suffix: suffix,
        spacecraft_id: spacecraft_id,
        provider: provider,
        transport: transport,
        runtime_profile: runtime_profile,
        path_template: path_template
      })

    assert {:ok, requirement, requirement_version} =
             ContactRequirements.create(
               member_scope,
               mission_id,
               requirement_attrs(spacecraft_id),
               now: @now
             )

    assert {:ok, planning} =
             Planner.run(
               member_scope,
               mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: @now,
               list_routes: fn _, _, _ -> {:ok, %{routes: [route], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok,
                  %{
                    opportunities: [
                      opportunity("primary", 3_600, 4_500),
                      opportunity("backup", 7_200, 8_100)
                    ]
                  }}
               end
             )

    assert {:ok, plan, plan_version} =
             ContactPlans.create(member_scope, mission_id, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids:
                 Enum.map(planning.snapshots, & &1.contact_opportunity_snapshot_id),
               rationale: "Reserve both passes for recorder relief"
             })

    assert {:ok, _pending} =
             ContactPlans.submit(
               member_scope,
               mission_id,
               plan.contact_plan_id,
               1,
               "Ready for review"
             )

    resolve_route = fn _, _, _, _ -> {:ok, route} end

    assert {:ok, approved_plan, _version, _approval} =
             ContactPlanApprovals.approve(
               admin_scope,
               mission_id,
               plan.contact_plan_id,
               1,
               plan_version.content_sha256,
               "Approved both provider commitments",
               now: DateTime.add(@now, 1, :second),
               resolve_route: resolve_route
             )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      member_scope: member_scope,
      plan: approved_plan,
      route: route,
      resolve_route: resolve_route
    }
  end

  test "approval creates durable items and execution links exact Plan evidence to reservations",
       context do
    pending_items =
      ContactPlanExecutions.list(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id,
        1
      )

    assert length(pending_items) == 2
    assert Enum.all?(pending_items, &(&1.lifecycle_state == :pending))
    assert Enum.uniq_by(pending_items, & &1.idempotency_key) == pending_items

    test_pid = self()
    reserve = successful_reserver(test_pid)

    assert {:ok, result} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert result.plan.lifecycle_state == :reserved
    assert Enum.all?(result.items, &(&1.lifecycle_state == :reserved))
    assert Enum.all?(result.items, &is_binary(&1.provider_reservation_id))
    assert_received {:provider_mutation, _first}
    assert_received {:provider_mutation, _second}

    Enum.each(result.items, fn item ->
      assert {:ok, reservation} =
               ProviderReservations.fetch(
                 context.organization_id,
                 context.mission_id,
                 item.provider_reservation_id
               )

      assert reservation.contact_plan_id == context.plan.contact_plan_id
      assert reservation.contact_plan_version == 1

      assert reservation.contact_opportunity_snapshot_id ==
               item.contact_opportunity_snapshot_id

      assert reservation.idempotency_key == item.idempotency_key
      assert is_binary(reservation.contact_requirement_id)
      assert reservation.contact_requirement_version == 1
    end)

    assert {:ok, replay} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 3, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert replay.plan.lifecycle_state == :reserved
    refute_received {:provider_mutation, _opportunity_ref}
  end

  test "mixed provider outcomes preserve committed capacity and project partial success",
       context do
    reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
      if attrs["opportunity_ref"] == "opportunity-primary" do
        reserve_with_response(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          {:ok, provider_response(attrs, "confirmed")}
        )
      else
        reserve_with_response(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          {:error,
           ProviderError.from_response(409, %{
             "error" => %{"code" => "no_capacity", "detail" => "antenna unavailable"}
           })}
        )
      end
    end

    assert {:ok, result} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert result.plan.lifecycle_state == :partially_reserved
    assert Enum.sort(Enum.map(result.items, & &1.lifecycle_state)) == [:rejected, :reserved]

    assert length(Cadence.list_scheduled_contacts(context.organization_id, context.mission_id)) ==
             1
  end

  test "ambiguous writes remain uncertain and are not blindly retried", context do
    test_pid = self()

    reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
      send(test_pid, {:provider_mutation, attrs["opportunity_ref"]})

      reserve_with_response(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        {:error, ProviderError.ambiguous(%{"reason" => "connection_closed"})}
      )
    end

    assert {:ok, first} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert first.plan.lifecycle_state == :executing
    assert Enum.all?(first.items, &(&1.lifecycle_state == :uncertain))
    assert_received {:provider_mutation, _first}
    assert_received {:provider_mutation, _second}

    assert {:ok, second} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 3, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert Enum.all?(second.items, &(&1.lifecycle_state == :uncertain))
    refute_received {:provider_mutation, _opportunity_ref}
  end

  defp successful_reserver(test_pid) do
    fn organization_id, mission_id, provider_id, attrs, _opts ->
      send(test_pid, {:provider_mutation, attrs["opportunity_ref"]})

      reserve_with_response(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        {:ok, provider_response(attrs, "confirmed")}
      )
    end
  end

  defp reserve_with_response(organization_id, mission_id, provider_id, attrs, response) do
    ProviderBooking.reserve(
      organization_id,
      mission_id,
      provider_id,
      attrs,
      client: FakeProviderClient,
      reserve_response: response
    )
  end

  defp provider_response(attrs, status) do
    %{
      "id" => "external-#{attrs["opportunity_ref"]}",
      "provider_contact_ref" => "provider-contact-#{attrs["opportunity_ref"]}",
      "status" => status,
      "provider_status" => status,
      "pass_phase" => "scheduled",
      "delivery_state" => "ready",
      "client_reference" => attrs["idempotency_key"],
      "opportunity_ref" => attrs["opportunity_ref"],
      "spacecraft_ref" => attrs["provider_spacecraft_ref"],
      "service_profile_ref" => attrs["service_profile_ref"]["id"],
      "delivery_profile_ref" => attrs["delivery_profile_ref"]["id"],
      "delivery_descriptor" => delivery_descriptor(attrs),
      "starts_at" => iso(attrs["starts_at"]),
      "ends_at" => iso(attrs["ends_at"]),
      "provider_evidence" => %{"ground_station_ref" => attrs["ground_station_ref"]}
    }
  end

  defp delivery_descriptor(attrs) do
    %{
      "status" => "ready",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "protocol" => "tcp",
      "endpoint_ref" => attrs["delivery_profile_ref"]["id"],
      "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
      "allowed_source_refs" => [attrs["provider_spacecraft_ref"]],
      "activation_window" => %{
        "starts_at" => iso(attrs["starts_at"]),
        "ends_at" => iso(attrs["ends_at"])
      },
      "credential_ref" => nil,
      "diagnostics" => %{}
    }
  end

  defp route(context) do
    %{
      route_key: "route-#{context.suffix}",
      spacecraft_id: context.spacecraft_id,
      provider_spacecraft_ref: "SC-#{context.suffix}",
      source_endpoint_id: "source-endpoint-#{context.suffix}",
      routing_rule_id: "routing-#{context.suffix}",
      link_assignment_id: "link-#{context.suffix}",
      path_template_id: context.path_template.path_template_id,
      path_template_version: context.path_template.version,
      transport_id: context.transport.transport_id,
      transport_version: context.transport.version,
      transport_display_name: context.transport.display_name,
      provider_id: context.provider.provider_id,
      provider_version: context.provider.version,
      provider_account_id: context.provider.provider_account_id,
      provider_account_version: context.provider.provider_account_version,
      provider_account_grant_id: context.provider.provider_account_grant_id,
      provider_account_grant_version: context.provider.provider_account_grant_version,
      provider_profile_id: context.runtime_profile.provider_profile_id,
      provider_profile_version: context.runtime_profile.version,
      service_profile_ref: context.transport.service_profile_ref,
      delivery_profile_ref: context.transport.delivery_profile_ref,
      delivery_policy_document: context.provider.delivery_policy_document,
      provider_display_name: context.provider.display_name,
      service_display_name: "Realtime TT&C downlink",
      delivery_display_name: "Cadence primary ingress",
      delivery_operator_summary: "Streaming to Cadence",
      route_display_name: "Primary simulator route",
      client: FakeProviderClient
    }
  end

  defp opportunity(suffix, starts_offset, ends_offset) do
    %{
      "id" => "opportunity-#{suffix}",
      "spacecraft_ref" => "SC-#{suffix}",
      "ground_station_ref" => "station-#{suffix}",
      "antenna_or_service_pool_ref" => "pool-#{suffix}",
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => @now |> DateTime.add(starts_offset, :second) |> DateTime.to_iso8601(),
      "ends_at" => @now |> DateTime.add(ends_offset, :second) |> DateTime.to_iso8601(),
      "expires_at" => @now |> DateTime.add(18_000, :second) |> DateTime.to_iso8601(),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{"status" => "current", "valid_until" => DateTime.to_iso8601(@now)}
      }
    }
  end

  defp requirement_attrs(spacecraft_id) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(@now, 3_600, :second),
      latest_end: DateTime.add(@now, 28_800, :second),
      success_measure: :contact_count,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: nil,
      contact_count: 2,
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

  defp persist_provider!(organization_id, mission_id, suffix) do
    provider =
      MissionProvider.new(%{
        provider_id: "simulator-provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Ground Network Simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator-test",
        environment_ref: "run-alpha",
        last_validated_at: @now,
        last_synced_at: @now,
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: provider_inventory()
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-realtime-ttc-downlink",
            "version" => 3,
            "display_name" => "Realtime TT&C downlink",
            "direction" => "downlink",
            "state" => "active"
          }
        ]
      },
      "delivery_profiles" => %{
        "items" => [
          %{
            "id" => "delivery-cadence-primary",
            "version" => 7,
            "display_name" => "Cadence primary ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-realtime-ttc-downlink"],
            "state" => "ready",
            "operator_summary" => "Streaming to Cadence",
            "diagnostics" => %{
              "protocol" => "tcp",
              "mode" => "provider_connects",
              "host" => "127.0.0.1",
              "port" => 5100,
              "framing_family" => "ccsds_tm",
              "frame_bytes" => 1115
            }
          }
        ]
      }
    }
  end

  defp scope(organization, role, suffix) do
    user =
      User.new(%{
        user_id: "contact-plan-execution-user-#{role}-#{suffix}",
        email: "contact-plan-execution-#{role}-#{suffix}@example.test",
        display_name: "Contact Plan #{role}"
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

  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso(datetime) when is_binary(datetime), do: datetime
end
