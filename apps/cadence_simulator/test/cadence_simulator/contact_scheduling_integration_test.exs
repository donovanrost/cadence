defmodule CadenceSimulator.ContactSchedulingIntegrationTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{RoutingRule, Transport}

  alias Cadence.Contacts.{
    ProviderBooking,
    ProviderChangeApprovals,
    ProviderReservationChanges,
    ProviderReservationReconciler,
    ProviderScheduling,
    ScheduledContactRevisions
  }

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderAudit,
    ProviderContact,
    ProviderCredentials,
    ProviderEventInbox,
    ProviderEventPoller,
    ProviderEventProcessor,
    ProviderError
  }

  alias Cadence.Persistence.Schemas.{RawEvidenceRow, TelemetrySampleRow}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceSimulator.Provider.{Orchestrator, Router, Store}

  @definitions Path.expand(
                 "../../../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml",
                 __DIR__
               )

  setup do
    :ok = Store.clear()
    previous_admin_token = Application.get_env(:cadence_simulator, :provider_admin_api_token)
    previous_provider_token = Application.get_env(:cadence_simulator, :provider_api_token)
    previous_credentials = Application.get_env(:cadence, :ground_network_credentials)
    Application.put_env(:cadence_simulator, :provider_admin_api_token, "admin-secret")
    Application.put_env(:cadence_simulator, :provider_api_token, "provider-secret")

    Application.put_env(:cadence, :ground_network_credentials, %{
      "simulator-integration" => "provider-secret"
    })

    on_exit(fn ->
      restore_config(:provider_admin_api_token, previous_admin_token)
      restore_config(:provider_api_token, previous_provider_token)
      restore_cadence_credentials(previous_credentials)
    end)

    http_port = free_port()
    telemetry_port = free_port()

    start_supervised!({
      Bandit,
      plug: Router, scheme: :http, ip: {127, 0, 0, 1}, port: http_port
    })

    %{base_url: "http://127.0.0.1:#{http_port}", telemetry_port: telemetry_port}
  end

  @tag timeout: 60_000
  test "provider HTTP scheduling realizes a contact and streams normal Cadence telemetry",
       context do
    scenario =
      admin_post!(context.base_url <> "/admin/v1/scenarios", %{
        "name" => "Cadence scheduling boundary proof",
        "spacecraft_count" => 3,
        "spacecraft_prefix" => "SC",
        "pass_model" => %{
          "cadence_seconds" => 30,
          "duration_seconds" => 15,
          "jitter_seconds" => 0
        },
        "telemetry_profile" => %{
          "rate_hz" => 5.0,
          "definitions_path" => @definitions,
          "noise_amplitude" => 0.1
        }
      })

    run =
      admin_post!(context.base_url <> "/admin/v1/scenarios/#{scenario["id"]}/runs", %{
        "seed" => 2_026,
        "speed" => 1.0
      })

    setup =
      context
      |> persist_provider_setup(run)
      |> provision_provider_transport(context.telemetry_port)
      |> persist_spacecraft_routing(telemetry?: true)

    search_starts_at = DateTime.utc_now() |> DateTime.add(30) |> DateTime.truncate(:second)
    search_ends_at = DateTime.add(search_starts_at, 180)

    assert {:ok, %{opportunities: [opportunity | more_opportunities], route: route}} =
             ProviderScheduling.search_opportunities(
               setup.organization_id,
               setup.mission_id,
               setup.route.route_key,
               %{
                 "spacecraft_id" => setup.spacecraft.spacecraft_id,
                 "starts_at" => DateTime.to_iso8601(search_starts_at),
                 "ends_at" => DateTime.to_iso8601(search_ends_at)
               },
               credential_resolver: &resolve_provider_credential/1
             )

    assert route.provider_spacecraft_ref == "SC-001"

    booking_attrs = booking_attrs(setup, opportunity, "primary")

    assert {:ok, booking} =
             ProviderBooking.reserve(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_id,
               booking_attrs,
               credential_resolver: &resolve_provider_credential/1
             )

    assert booking.provider_reservation.lifecycle_state == :pending
    assert is_nil(booking.scheduled_contact)
    assert_profile_only_provider_request(booking.provider_reservation, setup)

    :ok = Orchestrator.reconcile(DateTime.utc_now())

    assert_event_page_survives_processor_restart(setup)

    assert {:ok, scheduled_contact} =
             Cadence.fetch_scheduled_contact(
               setup.organization_id,
               setup.mission_id,
               booking.provider_reservation.scheduled_contact_id
             )

    assert scheduled_contact.provider_contact_ref ==
             booking.provider_reservation.provider_contact_ref

    assert length(Cadence.list_scheduled_contacts(setup.organization_id, setup.mission_id)) == 1

    assert {:ok, %ProviderContact{status: :confirmed, pass_phase: :scheduled}} =
             SimulatorHTTP.describe_contact(
               setup.provider_context,
               booking.provider_reservation.response_document["id"],
               credential_resolver: &resolve_provider_credential/1
             )

    assert {:ok, confirmed_reservation} =
             Cadence.fetch_provider_reservation(
               setup.organization_id,
               setup.mission_id,
               booking.provider_reservation.provider_reservation_id
             )

    assert confirmed_reservation.delivery_descriptor_document["protocol"] == "tcp"

    assert confirmed_reservation.delivery_descriptor_document["endpoint_ref"] ==
             setup.delivery_profile.id

    assert confirmed_reservation.pass_phase == :scheduled
    assert confirmed_reservation.delivery_state == :pending

    assert_reconciler_restart_preserves_single_contact(setup, confirmed_reservation)

    {:ok, opportunity_starts_at, _offset} = DateTime.from_iso8601(opportunity["starts_at"])
    {:ok, opportunity_ends_at, _offset} = DateTime.from_iso8601(opportunity["ends_at"])

    assert {:ok, scheduler_summary} =
             Cadence.Contacts.reconcile(setup.mission_id, opportunity_starts_at)

    assert scheduler_summary.realized_scheduled_contact_ids == [
             scheduled_contact.scheduled_contact_id <> "_run"
           ]

    assert [realized_contact] =
             Cadence.list_realized_contacts(setup.organization_id, setup.mission_id)

    assert realized_contact.scheduled_contact_id == scheduled_contact.scheduled_contact_id

    :ok = Orchestrator.reconcile(DateTime.add(opportunity_starts_at, -2))
    :ok = Orchestrator.reconcile(opportunity_starts_at)

    assert_eventually(fn ->
      count_for_mission(RawEvidenceRow, :evidence_id, setup.mission_id) > 0
    end)

    assert_eventually(fn ->
      count_for_mission(TelemetrySampleRow, :sample_id, setup.mission_id) > 0
    end)

    sample =
      TelemetrySampleRow
      |> where([row], row.mission_id == ^setup.mission_id)
      |> order_by([row], asc: row.receipt_time)
      |> Cadence.Repo.one()

    assert sample.spacecraft_id == setup.spacecraft.spacecraft_id
    assert is_binary(sample.point_name)

    :ok = Orchestrator.reconcile(DateTime.add(opportunity_ends_at, 1))

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             ProviderReservationReconciler.reconcile_due(
               setup.organization_id,
               mission_id: setup.mission_id,
               backoff_ms: 0,
               credential_resolver: &resolve_provider_credential/1,
               now: DateTime.add(DateTime.utc_now(), 1, :second)
             )

    assert {:ok, completed_reservation} =
             Cadence.fetch_provider_reservation(
               setup.organization_id,
               setup.mission_id,
               booking.provider_reservation.provider_reservation_id
             )

    assert completed_reservation.lifecycle_state == :completed
    assert completed_reservation.pass_phase == :closed
    assert completed_reservation.delivery_state == :ended

    audit_actions =
      setup.organization_id
      |> ProviderAudit.list_entries(
        provider_reservation_id: completed_reservation.provider_reservation_id,
        limit: 100
      )
      |> Enum.map(& &1.action)

    assert "provider_event.processed" in audit_actions

    assert {:ok, _scheduler_summary} =
             Cadence.Contacts.reconcile(setup.mission_id, DateTime.add(opportunity_ends_at, 1))

    assert length(Cadence.list_scheduled_contacts(setup.organization_id, setup.mission_id)) == 1

    assert length(Cadence.list_provider_reservations(setup.organization_id, setup.mission_id)) ==
             1

    assert is_list(more_opportunities)
  end

  @tag timeout: 60_000
  test "client-reference reconciliation recovers a response lost after commit without duplicates",
       context do
    scenario =
      admin_post!(context.base_url <> "/admin/v1/scenarios", %{
        "name" => "Cadence ambiguous response boundary proof",
        "spacecraft_count" => 1,
        "spacecraft_prefix" => "SC",
        "provider_behavior" => %{
          "confirmation" => "asynchronous",
          "idempotency" => "client_reference",
          "recovery" => "client_reference"
        },
        "fault_profile" => %{"contact_response_loss_after_commit_count" => 1},
        "pass_model" => %{
          "cadence_seconds" => 30,
          "duration_seconds" => 15,
          "jitter_seconds" => 0
        }
      })

    run =
      admin_post!(context.base_url <> "/admin/v1/scenarios/#{scenario["id"]}/runs", %{
        "seed" => 2_027,
        "speed" => 1.0
      })

    setup =
      context
      |> persist_provider_setup(run)
      |> provision_provider_transport(context.telemetry_port)
      |> persist_spacecraft_routing()

    search_starts_at = DateTime.utc_now() |> DateTime.add(30) |> DateTime.truncate(:second)

    assert {:ok, %{opportunities: [opportunity | _rest]}} =
             ProviderScheduling.search_opportunities(
               setup.organization_id,
               setup.mission_id,
               setup.route.route_key,
               %{
                 "spacecraft_id" => setup.spacecraft.spacecraft_id,
                 "starts_at" => DateTime.to_iso8601(search_starts_at),
                 "ends_at" => DateTime.to_iso8601(DateTime.add(search_starts_at, 180))
               },
               credential_resolver: &resolve_provider_credential/1
             )

    attrs = booking_attrs(setup, opportunity, "response-loss")

    assert {:error, {:provider_reservation_not_confirmed, ambiguous_reservation}} =
             ProviderBooking.reserve(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_id,
               attrs,
               credential_resolver: &resolve_provider_credential/1
             )

    assert ambiguous_reservation.lifecycle_state == :unknown
    assert ambiguous_reservation.response_document == %{}

    assert get_in(ambiguous_reservation.last_error_document, ["reason", "category"]) ==
             "ambiguous_outcome"

    assert_profile_only_provider_request(ambiguous_reservation, setup)

    assert {:ok, %ProviderContact{id: provider_contact_id}} =
             SimulatorHTTP.find_contact_by_client_reference(
               setup.provider_context,
               ambiguous_reservation.idempotency_key,
               credential_resolver: &resolve_provider_credential/1
             )

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             ProviderReservationReconciler.reconcile_due(
               setup.organization_id,
               mission_id: setup.mission_id,
               backoff_ms: 0,
               credential_resolver: &resolve_provider_credential/1,
               now: DateTime.add(DateTime.utc_now(), 1, :second)
             )

    assert {:ok, recovered_reservation} =
             Cadence.fetch_provider_reservation(
               setup.organization_id,
               setup.mission_id,
               ambiguous_reservation.provider_reservation_id
             )

    assert recovered_reservation.provider_contact_ref == provider_contact_id
    assert recovered_reservation.lifecycle_state in [:pending, :confirmed]

    :ok = Orchestrator.reconcile(DateTime.utc_now())

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             ProviderReservationReconciler.reconcile_due(
               setup.organization_id,
               mission_id: setup.mission_id,
               backoff_ms: 0,
               credential_resolver: &resolve_provider_credential/1,
               now: DateTime.add(DateTime.utc_now(), 2, :second)
             )

    assert [scheduled_contact] =
             Cadence.list_scheduled_contacts(setup.organization_id, setup.mission_id)

    assert scheduled_contact.scheduled_contact_id == recovered_reservation.scheduled_contact_id

    assert {:ok, %ProviderContact{id: ^provider_contact_id}} =
             SimulatorHTTP.find_contact_by_client_reference(
               setup.provider_context,
               ambiguous_reservation.idempotency_key,
               credential_resolver: &resolve_provider_credential/1
             )

    assert_reconciler_restart_preserves_single_contact(setup, recovered_reservation)

    assert [_single_reservation] =
             Cadence.list_provider_reservations(setup.organization_id, setup.mission_id)
  end

  test "credential rotation is observed between calls without recreating mission setup",
       context do
    %{setup: setup} = prepare_confirmed_contact(context)
    {:ok, secret_state} = Agent.start_link(fn -> %{token: "provider-secret", version: "one"} end)
    test_pid = self()

    backend = fn _descriptor, _opts ->
      secret = Agent.get(secret_state, & &1)
      send(test_pid, {:resolved_backend_version, secret.version})

      {:ok,
       %{
         material: %{bearer_token: secret.token},
         backend_version: secret.version
       }}
    end

    assert {:ok, first_provider} =
             GroundNetworks.validate_provider(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_id,
               secret_backend: backend
             )

    assert_receive {:resolved_backend_version, "one"}

    assert {:ok, rotated} =
             ProviderCredentials.rotate(
               setup.organization_id,
               setup.provider_account.provider_account_id,
               setup.provider_credential.provider_credential_ref,
               manage_backend?: false
             )

    Agent.update(secret_state, &%{&1 | version: "two"})

    assert {:ok, second_provider} =
             GroundNetworks.validate_provider(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_id,
               secret_backend: backend
             )

    assert_receive {:resolved_backend_version, "two"}
    assert rotated.registry_version == setup.provider_credential.registry_version + 1
    assert first_provider.provider_id == second_provider.provider_id
    assert first_provider.version == second_provider.version

    assert {:ok, same_transport} =
             Cadence.fetch_transport_version(
               setup.organization_id,
               setup.mission_id,
               setup.transport.transport_id,
               setup.transport.version
             )

    assert same_transport.transport_id == setup.transport.transport_id
  end

  test "policy-approved provider timing shift appends exactly one execution revision", context do
    policy = %{
      "mode" => "bounded_automatic",
      "maximum_later_start_shift_seconds" => 30,
      "maximum_later_end_shift_seconds" => 30
    }

    %{setup: setup, run: run, reservation: reservation} =
      prepare_confirmed_contact(context, policy: policy)

    admin_contact_change!(context.base_url, run, reservation.provider_contact_ref, %{
      "type" => "timing_shift",
      "start_shift_seconds" => 30,
      "end_shift_seconds" => 30,
      "effective" => false,
      "reason" => "network_optimization"
    })

    assert {:ok, reconciled} = reconcile_reservation(reservation)
    assert reconciled.provider_revision == reservation.provider_revision + 1

    change =
      setup
      |> reservation_changes(reservation)
      |> Enum.find(&(&1.classification == :policy_accept))

    assert change
    assert change.classification == :policy_accept
    assert change.lifecycle_state == :policy_accepted

    assert [initial, accepted] =
             ScheduledContactRevisions.list(
               setup.organization_id,
               reservation.scheduled_contact_id
             )

    assert initial.revision == 1
    assert accepted.revision == 2

    assert {:ok, replayed} = reconcile_reservation(reconciled)
    assert replayed.provider_revision == reconciled.provider_revision

    assert [_initial, _accepted] =
             ScheduledContactRevisions.list(
               setup.organization_id,
               reservation.scheduled_contact_id
             )
  end

  test "a material counteroffer waits for approval and a superseded proposal stays stale",
       context do
    %{setup: setup, run: run, reservation: reservation} = prepare_confirmed_contact(context)
    first_start = shift_iso8601(reservation.starts_at, 10)
    first_end = shift_iso8601(reservation.ends_at, 10)

    admin_contact_change!(context.base_url, run, reservation.provider_contact_ref, %{
      "type" => "counteroffer",
      "starts_at" => first_start,
      "ends_at" => first_end,
      "expires_at" => shift_iso8601(DateTime.utc_now(), 3_600),
      "reason" => "provider_capacity_rebalance"
    })

    assert {:ok, first_reconciled} = reconcile_reservation(reservation)

    first_change =
      setup
      |> reservation_changes(reservation)
      |> Enum.find(&(&1.lifecycle_state == :pending_approval))

    assert first_change
    assert first_change.lifecycle_state == :pending_approval

    admin_contact_change!(context.base_url, run, reservation.provider_contact_ref, %{
      "type" => "counteroffer",
      "starts_at" => shift_iso8601(reservation.starts_at, 20),
      "ends_at" => shift_iso8601(reservation.ends_at, 20),
      "expires_at" => shift_iso8601(DateTime.utc_now(), 3_600),
      "reason" => "provider_capacity_rebalance_updated"
    })

    assert {:ok, _second_reconciled} = reconcile_reservation(first_reconciled)

    assert [superseded, pending] =
             setup
             |> reservation_changes(reservation)
             |> Enum.filter(&(&1.lifecycle_state in [:superseded, :pending_approval]))

    assert superseded.lifecycle_state == :superseded
    assert pending.lifecycle_state == :pending_approval

    assert {:error, {:provider_change_not_decidable, "superseded"}} =
             ProviderChangeApprovals.approve(
               admin_scope(setup),
               superseded.provider_reservation_change_id,
               superseded.proposal_hash,
               "The provider replaced this proposal"
             )

    assert [revision] =
             ScheduledContactRevisions.list(
               setup.organization_id,
               reservation.scheduled_contact_id
             )

    assert revision.revision == 1
  end

  test "provider-effective cancellation becomes an acknowledged contingency fact", context do
    %{setup: setup, run: run, reservation: reservation} = prepare_confirmed_contact(context)

    admin_contact_change!(context.base_url, run, reservation.provider_contact_ref, %{
      "type" => "cancellation",
      "reason" => "provider_station_outage"
    })

    assert {:ok, canceled} = reconcile_reservation(reservation)
    assert canceled.lifecycle_state == :canceled

    change =
      setup
      |> reservation_changes(reservation)
      |> Enum.find(&(&1.lifecycle_state == :acknowledgment_required))

    assert change
    assert change.lifecycle_state == :acknowledgment_required
    assert change.already_effective
    refute change.actionable

    assert {:ok, acknowledged} =
             ProviderChangeApprovals.acknowledge(
               admin_scope(setup),
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Flight has opened the station-outage contingency"
             )

    assert acknowledged.lifecycle_state == :acknowledged

    assert {:ok, scheduled} =
             Cadence.fetch_scheduled_contact(
               setup.organization_id,
               setup.mission_id,
               reservation.scheduled_contact_id
             )

    assert scheduled.lifecycle_state == :canceled
  end

  test "provider endpoint and framing drift fails closed as configuration remediation", context do
    %{setup: setup, run: run, reservation: reservation} = prepare_confirmed_contact(context)

    admin_contact_change!(context.base_url, run, reservation.provider_contact_ref, %{
      "type" => "delivery_configuration_mismatch",
      "endpoint_ref" => "delivery-profile-unapproved",
      "frame_bytes" => 1_024,
      "reason" => "provider_configuration_drift"
    })

    assert {:error, failed, reason} = reconcile_reservation(reservation)
    assert failed.lifecycle_state == :failed
    assert reason == :delivery_descriptor_conflicts_with_transport

    change =
      setup
      |> reservation_changes(reservation)
      |> Enum.find(&(&1.classification == :configuration_failure))

    assert change
    assert change.classification == :configuration_failure
    assert change.lifecycle_state == :configuration_failure
    refute change.actionable

    assert [revision] =
             ScheduledContactRevisions.list(
               setup.organization_id,
               reservation.scheduled_contact_id
             )

    assert revision.revision == 1
  end

  test "a lost modification response recovers by authoritative describe without replay",
       context do
    %{setup: setup, reservation: reservation} =
      prepare_confirmed_contact(context,
        policy: %{
          "mode" => "bounded_automatic",
          "maximum_later_start_shift_seconds" => 30,
          "maximum_later_end_shift_seconds" => 30
        },
        fault_profile: %{"contact_modification_response_loss_after_commit_count" => 1}
      )

    assert {:ok, provider_contact} =
             SimulatorHTTP.describe_contact(
               setup.provider_context,
               reservation.provider_contact_ref,
               credential_resolver: &resolve_provider_credential/1
             )

    modification = %{
      "client_reference" => "cadence-modification-#{setup.suffix}",
      "expected_revision" => provider_contact.provider_revision,
      "starts_at" => shift_iso8601(provider_contact.starts_at, 15),
      "ends_at" => shift_iso8601(provider_contact.ends_at, 15),
      "reason" => "operator_requested"
    }

    assert {:error, %ProviderError{category: :ambiguous_outcome}} =
             SimulatorHTTP.modify_contact(
               setup.provider_context,
               reservation.provider_contact_ref,
               modification,
               idempotency_key: "modification-loss-#{setup.suffix}",
               credential_resolver: &resolve_provider_credential/1
             )

    assert {:ok, described} =
             SimulatorHTTP.describe_contact(
               setup.provider_context,
               reservation.provider_contact_ref,
               credential_resolver: &resolve_provider_credential/1
             )

    assert described.provider_revision == provider_contact.provider_revision + 1
    assert {:ok, reconciled} = reconcile_reservation(reservation)
    assert reconciled.provider_revision == described.provider_revision

    assert {:ok, internal} =
             CadenceSimulator.Provider.Contacts.fetch_internal(reservation.provider_contact_ref)

    assert length(internal["modification_history"]) == 1
  end

  defp prepare_confirmed_contact(context, opts \\ []) do
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
             Cadence.fetch_scheduled_contact(
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

  defp persist_provider_setup(context, run, opts \\ []) do
    suffix = System.unique_integer([:positive])
    organization_id = "org-simulator-scheduling-#{suffix}"
    mission_id = "mission-simulator-scheduling-#{suffix}"
    %{organization: organization} = persist_mission_scope(organization_id, mission_id)

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

  defp provision_provider_transport(setup, telemetry_port) do
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

    assert {:ok, transport} = Cadence.persist_transport(setup.organization_id, transport)
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

  defp persist_spacecraft_routing(setup, opts \\ []) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-#{setup.suffix}",
        mission_id: setup.mission_id,
        display_name: "Boundary Proof Spacecraft"
      })

    assert {:ok, spacecraft} = Cadence.persist_spacecraft(setup.organization_id, spacecraft)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-#{setup.suffix}",
        mission_id: setup.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "SC-001",
        scid: 0,
        display_name: "Simulator SC-001"
      })

    assert {:ok, endpoint} = Cadence.persist_source_endpoint(setup.organization_id, endpoint)

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

    assert {:ok, rule} = Cadence.create_routing_rule(setup.organization_id, rule)

    assert {:ok, %{routes: [route], findings: []}} =
             ProviderScheduling.list_ready_downlink_routes(
               setup.organization_id,
               setup.mission_id,
               spacecraft.spacecraft_id
             )

    assert {:ok, path} =
             Cadence.fetch_path_template_version(
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

  defp persist_telemetry_binding!(organization_id, mission_id, suffix) do
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

    assert {:ok, binding_set} = Cadence.persist_binding_set(organization_id, binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               activated_by: %{"service_identity_id" => "simulator-integration-test"}
             )
  end

  defp booking_attrs(setup, opportunity, suffix) do
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

  defp assert_profile_only_provider_request(reservation, setup) do
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

  defp assert_reconciler_restart_preserves_single_contact(setup, reservation) do
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
             Cadence.list_scheduled_contacts(setup.organization_id, setup.mission_id)

    assert scheduled_contact.scheduled_contact_id == reservation.scheduled_contact_id

    assert [persisted_reservation] =
             Cadence.list_provider_reservations(setup.organization_id, setup.mission_id)

    assert persisted_reservation.provider_contact_ref == reservation.provider_contact_ref
  end

  defp admin_post!(url, body) do
    response = Req.post!(url, json: body, auth: {:bearer, "admin-secret"})
    assert response.status in 200..299
    response.body["data"]
  end

  defp admin_contact_change!(base_url, run, provider_contact_ref, body) do
    admin_post!(
      base_url <> "/admin/v1/runs/#{run["id"]}/contacts/#{provider_contact_ref}/changes",
      body
    )
  end

  defp reconcile_reservation(reservation) do
    ProviderReservationReconciler.reconcile_reservation(
      reservation,
      credential_resolver: &resolve_provider_credential/1
    )
  end

  defp reservation_changes(setup, reservation) do
    ProviderReservationChanges.list_for_reservation(
      setup.organization_id,
      reservation.provider_reservation_id
    )
  end

  defp admin_scope(setup) do
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

  defp shift_iso8601(%DateTime{} = value, seconds) do
    value |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp assert_event_page_survives_processor_restart(setup) do
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

  defp delivery_profile_request(port, suffix) do
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

  defp resolve_provider_credential("provider-credential-" <> _suffix),
    do: {:ok, "provider-secret"}

  defp restore_config(key, nil), do: Application.delete_env(:cadence_simulator, key)
  defp restore_config(key, value), do: Application.put_env(:cadence_simulator, key, value)

  defp restore_cadence_credentials(nil),
    do: Application.delete_env(:cadence, :ground_network_credentials)

  defp restore_cadence_credentials(value),
    do: Application.put_env(:cadence, :ground_network_credentials, value)

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp count_for_mission(schema, field, mission_id) do
    schema
    |> where([row], row.mission_id == ^mission_id)
    |> Cadence.Repo.aggregate(:count, field)
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0), do: assert(fun.())
end
