defmodule CadenceSimulator.ContactSchedulingFixtures do
  @moduledoc false

  import Ecto.Query
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised!: 1, stop_supervised: 1]

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{RoutingRule, Transport}

  alias Cadence.Contacts.{
    ProviderBooking,
    ProviderReservationChanges,
    ProviderReservationReconciler,
    ProviderReservations,
    ProviderScheduling
  }

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials,
    ProviderEventInbox,
    ProviderEventPoller,
    ProviderEventProcessor
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceSimulator.Provider.Orchestrator

  def prepare_confirmed_contact(context, opts \\ []) do
    scenario =
      admin_post!(context.base_url <> "/admin/v1/scenarios", %{
        "name" => "Stage 3 provider boundary #{System.unique_integer([:positive])}",
        "spacecraft_count" => 1,
        "spacecraft_prefix" => "SC",
        "fault_profile" => Keyword.get(opts, :fault_profile, %{}),
        "pass_model" => %{
          "cadence_seconds" => 30,
          "duration_seconds" => 15,
          "jitter_seconds" => 0
        }
      })

    run =
      admin_post!(context.base_url <> "/admin/v1/scenarios/#{scenario["id"]}/runs", %{
        "seed" => 3_000 + System.unique_integer([:positive]),
        "speed" => 1.0
      })

    setup =
      context
      |> persist_provider_setup(run, policy: Keyword.get(opts, :policy, %{}))
      |> provision_provider_transport(context.telemetry_port)
      |> persist_spacecraft_routing()

    starts_at = DateTime.utc_now() |> DateTime.add(30) |> DateTime.truncate(:second)

    assert {:ok, %{opportunities: [opportunity | _rest]}} =
             ProviderScheduling.search_opportunities(
               setup.organization_id,
               setup.mission_id,
               setup.route.route_key,
               %{
                 "spacecraft_id" => setup.spacecraft.spacecraft_id,
                 "starts_at" => DateTime.to_iso8601(starts_at),
                 "ends_at" => DateTime.to_iso8601(DateTime.add(starts_at, 180))
               },
               credential_resolver: &resolve_provider_credential/1
             )

    assert {:ok, booking} =
             ProviderBooking.reserve(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_id,
               booking_attrs(setup, opportunity, "stage-three-#{setup.suffix}"),
               credential_resolver: &resolve_provider_credential/1
             )

    :ok = Orchestrator.reconcile(DateTime.utc_now())
    assert {:ok, reservation} = reconcile_reservation(booking.provider_reservation)

    assert {:ok, scheduled_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               setup.organization_id,
               setup.mission_id,
               reservation.scheduled_contact_id
             )

    %{
      setup: setup,
      scenario: scenario,
      run: run,
      reservation: reservation,
      scheduled_contact: scheduled_contact
    }
  end

  def persist_provider_setup(context, run, opts \\ []) do
    suffix = System.unique_integer([:positive])
    organization_id = "org-simulator-scheduling-#{suffix}"
    mission_id = "mission-simulator-scheduling-#{suffix}"

    %{organization: organization} =
      Cadence.DataCase.persist_mission_scope(organization_id, mission_id)

    provider_account_id = "provider-account-#{suffix}"
    provider_credential_ref = "provider-credential-#{suffix}"

    assert {:ok, provider_credential} =
             ProviderCredentials.create(
               organization_id,
               provider_account_id,
               %{
                 provider_credential_ref: provider_credential_ref,
                 backend_type: :external,
                 backend_key: "simulator/#{suffix}/control-plane"
               },
               manage_backend?: false
             )

    assert {:ok, provider_account, provider_account_version} =
             ProviderAccounts.create_for_system(
               organization_id,
               %{
                 provider_account_id: provider_account_id,
                 display_name: "Ground Station Simulator",
                 provider_type: :simulator,
                 client_key: :simulator_http,
                 base_url: context.base_url,
                 environment_ref: run["provider_environment_ref"],
                 credential_ref: provider_credential_ref,
                 event_ingestion_mode: :polling,
                 guardrails: %{}
               },
               %{"kind" => "system", "id" => "simulator-integration-test"},
               validate_credential?: false
             )

    assert {:ok, provider_account_grant} =
             ProviderAccountGrants.grant_for_system(
               organization_id,
               mission_id,
               provider_account_id,
               %{
                 provider_account_grant_id: "provider-account-grant-#{suffix}",
                 restrictions: %{},
                 grant_reason: "Separate-application provider proof"
               },
               %{"kind" => "system", "id" => "simulator-integration-test"}
             )

    provider =
      MissionProvider.new(%{
        provider_id: "provider-#{suffix}",
        mission_id: mission_id,
        display_name: "External simulator",
        provider_account_id: provider_account.provider_account_id,
        provider_account_version: provider_account_version.version,
        provider_account_grant_id: provider_account_grant.provider_account_grant_id,
        provider_account_grant_version: provider_account_grant.version,
        provider_type: :simulator,
        base_url: context.base_url,
        credential_ref: provider_credential_ref,
        environment_ref: run["provider_environment_ref"],
        delivery_policy_document: Keyword.get(opts, :policy, %{})
      })

    assert {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)

    assert {:ok, validated_provider} =
             GroundNetworks.validate_provider(
               organization_id,
               mission_id,
               provider.provider_id,
               credential_resolver: &resolve_provider_credential/1
             )

    assert get_in(validated_provider.metadata, ["control_plane", "status"]) == "healthy"
    assert validated_provider.capabilities_document["operations"]["contact_reservation"]

    assert {:ok, synced_provider} =
             GroundNetworks.sync_provider(
               organization_id,
               mission_id,
               provider.provider_id,
               credential_resolver: &resolve_provider_credential/1
             )

    assert get_in(synced_provider.metadata, ["sync", "status"]) == "healthy"

    assert [service_profile | _rest] =
             get_in(synced_provider.inventory_sync_document, ["service_profiles", "items"])

    assert {:ok, provider_context} =
             GroundNetworks.provider_context(
               organization_id,
               mission_id,
               provider.provider_id
             )

    %{
      suffix: suffix,
      organization_id: organization_id,
      mission_id: mission_id,
      organization: organization,
      provider_account: provider_account,
      provider_account_version: provider_account_version,
      provider_account_grant: provider_account_grant,
      provider_credential: provider_credential,
      provider: synced_provider,
      provider_context: provider_context,
      service_profile: service_profile
    }
  end

  def provision_provider_transport(setup, telemetry_port) do
    assert {:ok, delivery_profile} =
             SimulatorHTTP.provision_delivery_profile(
               setup.provider_context,
               delivery_profile_request(telemetry_port, setup.suffix),
               credential_resolver: &resolve_provider_credential/1
             )

    assert {:ok, synced_provider} =
             GroundNetworks.sync_provider(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_id,
               credential_resolver: &resolve_provider_credential/1
             )

    assert Enum.any?(
             get_in(synced_provider.inventory_sync_document, ["delivery_profiles", "items"]),
             &(&1["id"] == delivery_profile.id and &1["version"] == delivery_profile.version)
           )

    transport =
      Transport.new(%{
        transport_id: "transport-#{setup.suffix}",
        mission_id: setup.mission_id,
        display_name: "Simulator telemetry ingress",
        origin: :provider_managed,
        mission_provider_id: synced_provider.provider_id,
        mission_provider_version: synced_provider.version,
        service_profile_ref: %{
          "id" => setup.service_profile["id"],
          "version" => setup.service_profile["version"]
        },
        delivery_profile_ref: %{
          "id" => delivery_profile.id,
          "version" => delivery_profile.version
        }
      })

    assert {:ok, transport} =
             TransportStore.persist_transport(setup.organization_id, transport)

    assert transport.origin == :provider_managed
    assert transport.configuration["port"] == telemetry_port

    assert {:ok, provider_context} =
             GroundNetworks.provider_context(
               setup.organization_id,
               setup.mission_id,
               synced_provider.provider_id
             )

    Map.merge(setup, %{
      provider: synced_provider,
      provider_context: provider_context,
      delivery_profile: delivery_profile,
      transport: transport
    })
  end

  def persist_spacecraft_routing(setup, opts \\ []) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-#{setup.suffix}",
        mission_id: setup.mission_id,
        display_name: "Boundary Proof Spacecraft"
      })

    assert {:ok, spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(setup.organization_id, spacecraft)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-#{setup.suffix}",
        mission_id: setup.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "SC-001",
        scid: 0,
        display_name: "Simulator SC-001"
      })

    assert {:ok, endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(setup.organization_id, endpoint)

    if Keyword.get(opts, :telemetry?, false) do
      persist_telemetry_binding!(setup.organization_id, setup.mission_id, setup.suffix)
    end

    rule =
      RoutingRule.new(%{
        routing_rule_id: "routing-rule-#{setup.suffix}",
        mission_id: setup.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Simulator telemetry downlink",
        purpose_label: "Telemetry",
        direction: :inbound,
        transport_id: setup.transport.transport_id,
        transport_version: setup.transport.version,
        role: :primary
      })

    assert {:ok, rule} =
             RoutingRuleStore.create_routing_rule(setup.organization_id, rule)

    assert {:ok, %{routes: [route], findings: []}} =
             ProviderScheduling.list_ready_downlink_routes(
               setup.organization_id,
               setup.mission_id,
               spacecraft.spacecraft_id
             )

    assert {:ok, path} =
             Cadence.Contacts.fetch_path_template_version(
               setup.organization_id,
               setup.mission_id,
               route.path_template_id,
               route.path_template_version
             )

    Map.merge(setup, %{
      spacecraft: spacecraft,
      endpoint: endpoint,
      rule: rule,
      path: path,
      route: route
    })
  end

  def persist_telemetry_binding!(organization_id, mission_id, suffix) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-hk-#{suffix}",
        packet_name: "HK",
        apid: 1,
        version: 1,
        fields: [
          %{
            field_id: "timestamp-sec",
            name: "timestamp_sec",
            offset_bits: 0,
            size_bits: 32,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "binding-set-#{suffix}",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "binding-hk-#{suffix}",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 1,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               activated_by: %{"service_identity_id" => "simulator-integration-test"}
             )
  end

  def booking_attrs(setup, opportunity, suffix) do
    opportunity
    |> Map.put("provider_reservation_id", "provider-reservation-#{suffix}")
    |> Map.put("scheduled_contact_id", "scheduled-contact-#{suffix}")
    |> Map.put("idempotency_key", "simulator-boundary-#{suffix}")
    |> Map.put("cadence_spacecraft_id", setup.spacecraft.spacecraft_id)
    |> Map.put("provider_spacecraft_ref", setup.route.provider_spacecraft_ref)
    |> Map.put("provider_version", setup.provider.version)
    |> Map.put("transport_id", setup.transport.transport_id)
    |> Map.put("transport_version", setup.transport.version)
    |> Map.put("service_profile_ref", setup.route.service_profile_ref)
    |> Map.put("delivery_profile_ref", setup.route.delivery_profile_ref)
    |> Map.put("provider_profile_id", setup.route.provider_profile_id)
    |> Map.put("provider_profile_version", setup.route.provider_profile_version)
    |> Map.put("routing_rule_id", setup.route.routing_rule_id)
    |> Map.put("source_endpoint_refs", [setup.route.source_endpoint_id])
    |> Map.put("path_template_ids", [setup.path.path_template_id])
    |> Map.put("path_template_refs", [
      %{"path_template_id" => setup.path.path_template_id, "version" => setup.path.version}
    ])
    |> Map.put("opportunity_ref", opportunity["id"])
  end

  def stage_four_requirement_attrs(spacecraft_id, earliest_start, latest_end) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: earliest_start,
      latest_end: latest_end,
      success_measure: :contact_count,
      minimum_duration_seconds: 5,
      preferred_duration_seconds: 15,
      minimum_data_volume_bytes: nil,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "Downlink telemetry through the external simulator provider",
      metadata: %{}
    }
  end

  def stage_five_requirement_attrs(spacecraft_id, earliest_start, latest_end, index) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "fleet_payload_downlink",
      earliest_start: earliest_start,
      latest_end: latest_end,
      success_measure: :contact_count,
      minimum_duration_seconds: 300,
      preferred_duration_seconds: 600,
      minimum_data_volume_bytes: nil,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: if(rem(index, 25) == 0, do: :critical, else: :routine),
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "Stage 5 300-spacecraft qualification",
      metadata: %{"fleet_index" => index}
    }
  end

  def fleet_policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 86_400,
        "requirement_concurrency" => 16,
        "provider_search_concurrency" => 8,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{
        "priority_weight" => 2_000,
        "deadline_weight" => 1_000,
        "scarcity_weight" => 800,
        "local_improvement_limit" => 100,
        "local_improvement_width" => 2
      },
      resource_policy_document: %{
        "default_exclusive_capacity" => 1,
        "capacities" => %{}
      },
      budget_quota_document: %{
        "max_contacts" => 300,
        "max_estimated_cost_micros" => nil,
        "currency" => nil,
        "per_provider" => %{},
        "critical_contact_reserve" => 0,
        "critical_cost_reserve_micros" => 0
      },
      redundancy_document: %{
        "distinct_provider_required" => false,
        "distinct_station_required" => false,
        "distinct_service_pool_required" => false
      },
      automation_repair_document: %{
        "mode" => "advisory",
        "execution_concurrency" => 8,
        "max_repair_attempts" => 3,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => false
      }
    }
  end

  def fleet_route(setup, spacecraft_id) do
    provider_spacecraft_ref = provider_spacecraft_ref(spacecraft_id)

    %{
      route_key: "fleet-route:#{provider_spacecraft_ref}",
      spacecraft_id: spacecraft_id,
      provider_spacecraft_ref: provider_spacecraft_ref,
      source_endpoint_id: "fleet-source:#{provider_spacecraft_ref}",
      routing_rule_id: "fleet-routing:#{provider_spacecraft_ref}",
      link_assignment_id: "fleet-link:#{provider_spacecraft_ref}",
      path_template_id: "fleet-path:#{provider_spacecraft_ref}",
      path_template_version: 1,
      transport_id: setup.transport.transport_id,
      transport_version: setup.transport.version,
      provider_id: setup.provider.provider_id,
      provider_version: setup.provider.version,
      provider_account_id: setup.provider_account.provider_account_id,
      provider_account_version: setup.provider_account_version.version,
      provider_account_grant_id: setup.provider_account_grant.provider_account_grant_id,
      provider_account_grant_version: setup.provider_account_grant.version,
      provider_profile_id: setup.transport.materialized_provider_profile_id,
      provider_profile_version: 1,
      service_profile_ref: %{
        "id" => setup.service_profile["id"],
        "version" => setup.service_profile["version"]
      },
      delivery_profile_ref: %{
        "id" => setup.delivery_profile.id,
        "version" => setup.delivery_profile.version
      },
      delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
      provider_display_name: setup.provider.display_name,
      service_display_name: setup.service_profile["display_name"],
      delivery_display_name: setup.delivery_profile.display_name,
      route_display_name: "Fleet route #{provider_spacecraft_ref}",
      client: SimulatorHTTP
    }
  end

  def fleet_spacecraft_id(index),
    do: "fleet-spacecraft-#{index |> Integer.to_string() |> String.pad_leading(3, "0")}"

  def provider_spacecraft_ref("fleet-spacecraft-" <> suffix), do: "SC-" <> suffix

  def assert_profile_only_provider_request(reservation, setup) do
    provider_request = reservation.request_document["provider_request"]

    assert provider_request == %{
             "client_reference" => reservation.idempotency_key,
             "delivery_profile_ref" => setup.delivery_profile.id,
             "opportunity_ref" => reservation.provider_opportunity_ref,
             "service_profile_ref" => setup.service_profile["id"],
             "spacecraft_ref" => "SC-001",
             "tags" => %{"cadence_mission_ref" => setup.mission_id}
           }

    refute Enum.any?(
             ~w(host port target framing endpoint data_plane tm_frame_size definitions_path),
             &Map.has_key?(provider_request, &1)
           )

    assert get_in(reservation.request_document, ["bindings", "provider_ref"]) == %{
             "id" => setup.provider.provider_id,
             "version" => setup.provider.version
           }

    assert get_in(reservation.request_document, ["bindings", "transport_ref"]) == %{
             "id" => setup.transport.transport_id,
             "version" => setup.transport.version
           }
  end

  def assert_reconciler_restart_preserves_single_contact(setup, reservation) do
    name = {:global, {__MODULE__, setup.suffix}}

    child =
      {ProviderReservationReconciler,
       name: name,
       safety_poll_interval_ms: 60_000,
       backoff_ms: 0,
       mission_id: setup.mission_id,
       credential_resolver: &resolve_provider_credential/1,
       now: DateTime.add(DateTime.utc_now(), 10, :second)}

    start_supervised!(child)

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             ProviderReservationReconciler.reconcile_now(name)

    assert :ok = stop_supervised(ProviderReservationReconciler)
    start_supervised!(child)

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             ProviderReservationReconciler.reconcile_now(name)

    assert [scheduled_contact] =
             Cadence.Contacts.list_scheduled_contacts(setup.organization_id, setup.mission_id)

    assert scheduled_contact.scheduled_contact_id == reservation.scheduled_contact_id

    assert [persisted_reservation] =
             ProviderReservations.list_for_mission(setup.organization_id, setup.mission_id)

    assert persisted_reservation.provider_contact_ref == reservation.provider_contact_ref
  end

  def admin_post!(url, body) do
    response = Req.post!(url, json: body, auth: {:bearer, "admin-secret"})
    assert response.status in 200..299
    response.body["data"]
  end

  def admin_contact_change!(base_url, run, provider_contact_ref, body) do
    admin_post!(
      base_url <> "/admin/v1/runs/#{run["id"]}/contacts/#{provider_contact_ref}/changes",
      body
    )
  end

  def reconcile_reservation(reservation) do
    ProviderReservationReconciler.reconcile_reservation(
      reservation,
      credential_resolver: &resolve_provider_credential/1
    )
  end

  def reservation_changes(setup, reservation) do
    ProviderReservationChanges.list_for_reservation(
      setup.organization_id,
      reservation.provider_reservation_id
    )
  end

  def admin_scope(setup) do
    user =
      User.new(%{
        user_id: "stage-three-admin-#{setup.suffix}",
        email: "stage-three-admin-#{setup.suffix}@example.test",
        display_name: "Stage Three Admin"
      })

    membership =
      OrganizationMembership.new(%{
        organization_membership_id: "stage-three-membership-#{setup.suffix}",
        user_id: user.user_id,
        organization_id: setup.organization_id,
        role: :organization_admin
      })

    Scope.new(%{
      user: user,
      organization: setup.organization,
      organization_id: setup.organization_id,
      organization_membership: membership
    })
  end

  def shift_iso8601(%DateTime{} = value, seconds) do
    value |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  def assert_event_page_survives_processor_restart(setup) do
    assert {:ok, poll_summary} =
             ProviderEventPoller.poll_once(
               accounts: [{setup.provider_account, setup.provider_account_version}],
               client: SimulatorHTTP,
               credential_resolver: &resolve_provider_credential/1,
               lease_owner: "simulator-integration-poller-#{setup.suffix}"
             )

    assert poll_summary.polled == 1
    assert poll_summary.events > 0

    inbox_entries = ProviderEventInbox.list(setup.organization_id)
    assert inbox_entries != []
    assert Enum.any?(inbox_entries, &(&1.processing_state == :received))

    name = {:global, {__MODULE__, :event_processor, setup.suffix}}

    child =
      {ProviderEventProcessor,
       name: name,
       process_interval_ms: 60_000,
       credential_resolver: &resolve_provider_credential/1}

    start_supervised!(child)
    assert :ok = stop_supervised(ProviderEventProcessor)
    start_supervised!(child)

    assert {:ok, summary} = ProviderEventProcessor.process_now(name)
    assert summary.processed > 0
    assert summary.errors == 0
    assert summary.quarantined == 0
  end

  def delivery_profile_request(port, suffix) do
    %{
      "display_name" => "Cadence boundary proof telemetry ingress",
      "client_reference" => "cadence-boundary-proof-downlink-#{suffix}",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "target" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => "127.0.0.1",
        "port" => port
      },
      "framing" => %{
        "family" => "ccsds_tm",
        "mode" => "fixed_size",
        "frame_bytes" => 1_115
      }
    }
  end

  def resolve_provider_credential("provider-credential-" <> _suffix),
    do: {:ok, "provider-secret"}

  def restore_config(key, nil), do: Application.delete_env(:cadence_simulator, key)
  def restore_config(key, value), do: Application.put_env(:cadence_simulator, key, value)

  def restore_cadence_credentials(nil),
    do: Application.delete_env(:cadence, :ground_network_credentials)

  def restore_cadence_credentials(value),
    do: Application.put_env(:cadence, :ground_network_credentials, value)

  def free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  def count_for_mission(schema, field, mission_id) do
    schema
    |> where([row], row.mission_id == ^mission_id)
    |> Cadence.Repo.aggregate(:count, field)
  end

  def assert_eventually(fun, attempts \\ 100)

  def assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  def assert_eventually(fun, 0), do: assert(fun.())
end
