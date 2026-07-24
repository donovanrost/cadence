defmodule Cadence.GroundNetworks.ProviderEventProcessorTest do
  use Cadence.DataCase, async: false

  alias Cadence.Management.Transports

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{ProviderReservation, ProviderReservations}

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox,
    ProviderEventPoller,
    ProviderEventProcessor
  }

  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-processor-#{suffix}"
    mission_id = "mission-provider-processor-#{suffix}"
    scope = persist_mission_scope(organization_id, mission_id)
    provider_scope = persist_provider_scope!(organization_id, mission_id, suffix)
    reservation = persist_reservation!(provider_scope, suffix)

    Map.merge(provider_scope, %{
      organization: scope.organization,
      organization_id: organization_id,
      mission_id: mission_id,
      reservation: reservation,
      suffix: suffix
    })
  end

  test "an inbox commit remains durable until authoritative processing succeeds", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    assert {:ok, entry} = ingest_contact_event(context, "event-process", now)
    assert entry.processing_state == :received

    assert {:ok, %{claimed: 1, processed: 1, errors: 0}} =
             ProviderEventProcessor.process_once(processor_opts(context, now))

    assert {:ok, processed} =
             ProviderEventInbox.fetch(context.organization_id, entry.provider_event_inbox_id)

    assert processed.processing_state == :processed
    assert processed.mission_id == context.mission_id
    assert processed.provider_id == context.provider.provider_id
    assert processed.provider_reservation_id == context.reservation.provider_reservation_id

    assert {:ok, reconciled} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               context.reservation.provider_reservation_id
             )

    assert reconciled.attempt_count == context.reservation.attempt_count + 1
    assert %DateTime{} = reconciled.last_reconciled_at
  end

  test "restart after domain commit reclaims processing and converges", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    assert {:ok, entry} = ingest_contact_event(context, "event-domain-restart", now)

    assert {:ok, %{claimed: 1, processed: 0, errors: 1}} =
             ProviderEventProcessor.process_once(
               processor_opts(context, now,
                 after_reconcile: fn _entry, _reservation ->
                   {:error, :injected_after_domain_commit}
                 end
               )
             )

    assert {:ok, processing} =
             ProviderEventInbox.fetch(context.organization_id, entry.provider_event_inbox_id)

    assert processing.processing_state == :processing

    assert {:ok, %{claimed: 1, processed: 1, errors: 0}} =
             ProviderEventProcessor.process_once(
               processor_opts(context, DateTime.add(now, 1, :second), processing_timeout_ms: 0)
             )

    assert {:ok, processed} =
             ProviderEventInbox.fetch(context.organization_id, entry.provider_event_inbox_id)

    assert processed.processing_state == :processed

    assert Cadence.Contacts.list_scheduled_contacts(context.organization_id, context.mission_id) ==
             []
  end

  test "event correlation cannot cross an exact Provider Account boundary", context do
    now = ~U[2026-07-15 12:00:00.000000Z]

    {other_account, other_version, _credential} =
      persist_account!(context.organization_id, context.suffix + 100)

    assert {:ok, cursor} = ProviderEventCursors.ensure(other_version)

    assert {:ok, claimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "other-poller", now: now)

    assert {:ok, %{entries: [entry]}} =
             ProviderEventInbox.ingest_page(
               claimed,
               [event_document("event-wrong-account", context.reservation)],
               "cursor-one",
               "other-poller",
               now: now
             )

    assert {:ok, %{claimed: 1, quarantined: 1, processed: 0}} =
             ProviderEventProcessor.process_once(processor_opts(context, now))

    assert {:ok, quarantined} =
             ProviderEventInbox.fetch(context.organization_id, entry.provider_event_inbox_id)

    assert quarantined.processing_state == :quarantined
    assert quarantined.provider_account_id == other_account.provider_account_id
    assert quarantined.error_document["reason"] == "provider_reservation_not_found"
  end

  test "quarantine reprocessing requires organization administration", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    assert {:ok, entry} = ingest_uncorrelated_event(context, now)

    assert {:ok, %{quarantined: 1}} =
             ProviderEventProcessor.process_once(processor_opts(context, now))

    member_scope = user_scope(context, :member)

    assert {:error, :forbidden} =
             ProviderEventInbox.reprocess(member_scope, entry.provider_event_inbox_id, now: now)

    admin_scope = user_scope(context, :organization_admin)

    assert {:ok, reprocessing} =
             ProviderEventInbox.reprocess(admin_scope, entry.provider_event_inbox_id, now: now)

    assert reprocessing.processing_state == :reprocessing

    assert {:ok, %{claimed: 1, quarantined: 1}} =
             ProviderEventProcessor.process_once(
               processor_opts(context, DateTime.add(now, 1, :second))
             )
  end

  test "account-level run events process without pretending to be mission contacts", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    assert {:ok, cursor} = ProviderEventCursors.ensure(context.account_version)

    assert {:ok, claimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "run-poller", now: now)

    run_event = %{
      "id" => "run-event-one",
      "schema_version" => "1.0",
      "sequence" => 1,
      "occurred_at" => "2026-07-15T11:59:00.000000Z",
      "type" => "run.created",
      "resource_type" => "run",
      "resource_id" => context.account_version.environment_ref,
      "resource_revision" => 1,
      "data" => %{"state" => "running"}
    }

    assert {:ok, %{entries: [entry]}} =
             ProviderEventInbox.ingest_page(
               claimed,
               [run_event],
               "cursor-run",
               "run-poller",
               now: now
             )

    assert {:ok, %{processed: 1}} = ProviderEventProcessor.process_once(now: now)

    assert {:ok, processed} =
             ProviderEventInbox.fetch(context.organization_id, entry.provider_event_inbox_id)

    assert processed.processing_state == :processed
    assert processed.mission_id == nil
  end

  defp ingest_contact_event(context, event_id, now) do
    poll_opts = [
      accounts: [{context.account, context.account_version}],
      client: FakeProviderClient,
      events_response:
        {:ok,
         %{
           data: [event_document(event_id, context.reservation)],
           next_cursor: event_id,
           truncated: false
         }},
      lease_owner: "processor-poller",
      now: now,
      secret_backend: &secret_backend/2
    ]

    assert {:ok, %{polled: 1}} = ProviderEventPoller.poll_once(poll_opts)
    [entry] = ProviderEventInbox.list(context.organization_id, limit: 1)
    {:ok, entry}
  end

  defp ingest_uncorrelated_event(context, now) do
    assert {:ok, cursor} = ProviderEventCursors.ensure(context.account_version)

    assert {:ok, claimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "bad-poller", now: now)

    event =
      event_document("event-uncorrelated", context.reservation)
      |> Map.put("resource_id", "missing-contact")
      |> Map.put("client_reference", "missing-client-reference")

    assert {:ok, %{entries: [entry]}} =
             ProviderEventInbox.ingest_page(
               claimed,
               [event],
               "cursor-bad",
               "bad-poller",
               now: now
             )

    {:ok, entry}
  end

  defp processor_opts(context, now, extra \\ []) do
    [
      client: FakeProviderClient,
      describe_response: {:ok, provider_response(context.reservation)},
      now: now,
      worker_ref: "processor-test"
    ] ++ extra
  end

  defp provider_response(reservation) do
    %{
      "id" => reservation.provider_contact_ref,
      "provider_contact_ref" => reservation.provider_contact_ref,
      "status" => "pending",
      "provider_status" => "pending",
      "pass_phase" => "scheduled",
      "delivery_state" => "pending",
      "client_reference" => reservation.idempotency_key,
      "opportunity_ref" => reservation.provider_opportunity_ref,
      "spacecraft_ref" => reservation.provider_spacecraft_ref,
      "service_profile_ref" => reservation.service_profile_ref["id"],
      "delivery_profile_ref" => reservation.delivery_profile_ref["id"],
      "starts_at" => DateTime.to_iso8601(reservation.starts_at),
      "ends_at" => DateTime.to_iso8601(reservation.ends_at)
    }
  end

  defp event_document(id, reservation) do
    %{
      "id" => id,
      "schema_version" => "1.0",
      "sequence" => 1,
      "occurred_at" => "2026-07-15T11:59:00.000000Z",
      "type" => "contact.status_changed",
      "resource_type" => "contact",
      "resource_id" => reservation.provider_contact_ref,
      "resource_revision" => 1,
      "client_reference" => reservation.idempotency_key,
      "data" => %{"status" => "pending"}
    }
  end

  defp persist_provider_scope!(organization_id, mission_id, suffix) do
    {account, account_version, _credential} = persist_account!(organization_id, suffix)

    assert {:ok, grant} =
             ProviderAccountGrants.grant_for_system(
               organization_id,
               mission_id,
               account.provider_account_id,
               %{provider_account_grant_id: "provider-grant-processor-#{suffix}"},
               %{"kind" => "system", "id" => "processor-test"}
             )

    provider =
      MissionProvider.new(%{
        provider_id: "provider-processor-#{suffix}",
        mission_id: mission_id,
        display_name: "Processor Simulator",
        provider_account_id: account.provider_account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        provider_type: account_version.provider_type,
        client_key: account_version.client_key,
        base_url: account_version.base_url,
        credential_ref: account_version.credential_ref,
        environment_ref: account_version.environment_ref,
        last_validated_at: ~U[2026-07-15 11:00:00.000000Z],
        last_synced_at: ~U[2026-07-15 11:00:00.000000Z],
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: provider_inventory()
      })

    assert {:ok, provider} =
             Cadence.GroundNetworks.persist_provider(organization_id, provider)

    assert {:ok, transport} =
             Transports.persist_transport(
               organization_id,
               Transport.new(%{
                 transport_id: "transport-processor-#{suffix}",
                 mission_id: mission_id,
                 display_name: "Provider telemetry",
                 origin: :provider_managed,
                 mission_provider_id: provider.provider_id,
                 mission_provider_version: provider.version,
                 service_profile_ref: %{"id" => "service-downlink", "version" => 3},
                 delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
               })
             )

    %{
      account: account,
      account_version: account_version,
      grant: grant,
      provider: provider,
      transport: transport
    }
  end

  defp persist_reservation!(context, suffix) do
    starts_at = ~U[2026-07-15 13:00:00.000000Z]

    reservation =
      ProviderReservation.new(%{
        provider_reservation_id: "provider-reservation-processor-#{suffix}",
        organization_id: context.account.organization_id,
        mission_id: context.provider.mission_id,
        provider_id: context.provider.provider_id,
        provider_version: context.provider.version,
        provider_account_id: context.account.provider_account_id,
        provider_account_version: context.account_version.version,
        provider_account_grant_id: context.grant.provider_account_grant_id,
        provider_account_grant_version: context.grant.version,
        transport_id: context.transport.transport_id,
        transport_version: context.transport.version,
        service_profile_ref: context.transport.service_profile_ref,
        delivery_profile_ref: context.transport.delivery_profile_ref,
        provider_profile_id: context.transport.materialized_provider_profile_id,
        provider_profile_version: 1,
        scheduled_contact_id: "scheduled-contact-processor-#{suffix}",
        provider_opportunity_ref: "opportunity-processor-#{suffix}",
        provider_contact_ref: "provider-contact-processor-#{suffix}",
        idempotency_key: "idempotency-processor-#{suffix}",
        lifecycle_state: :pending,
        pass_phase: :scheduled,
        delivery_state: :pending,
        spacecraft_id: "spacecraft-processor-#{suffix}",
        provider_spacecraft_ref: "SC-#{suffix}",
        source_endpoint_refs: [],
        path_template_ids: [],
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 600),
        request_document: %{}
      })

    assert {:ok, persisted} =
             ProviderReservations.create_attempt(context.account.organization_id, reservation)

    persisted
  end

  defp persist_account!(organization_id, suffix) do
    account_id = "provider-account-processor-#{suffix}"
    credential_ref = "provider-credential-processor-#{suffix}"

    assert {:ok, credential} =
             ProviderCredentials.create(
               organization_id,
               account_id,
               %{
                 provider_credential_ref: credential_ref,
                 backend_type: :external,
                 backend_key: "providers/#{suffix}/control-plane"
               },
               manage_backend?: false
             )

    assert {:ok, account, version} =
             ProviderAccounts.create_for_system(
               organization_id,
               %{
                 provider_account_id: account_id,
                 display_name: "Processor Account #{suffix}",
                 provider_type: :simulator,
                 base_url: "http://simulator.test",
                 environment_ref: "environment-processor-#{suffix}",
                 credential_ref: credential_ref
               },
               %{"kind" => "system", "id" => "processor-test"},
               validate_credential?: false
             )

    {account, version, credential}
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-downlink",
            "version" => 3,
            "display_name" => "Realtime telemetry",
            "direction" => "downlink",
            "state" => "active"
          }
        ]
      },
      "delivery_profiles" => %{
        "items" => [
          %{
            "id" => "delivery-cadence",
            "version" => 7,
            "display_name" => "Cadence primary ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-downlink"],
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

  defp user_scope(context, role) do
    user =
      User.new(%{
        user_id: "user-#{role}-#{context.suffix}",
        email: "#{role}-#{context.suffix}@example.com",
        display_name: "Provider operator"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: context.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization: context.organization,
      organization_id: context.organization_id,
      organization_membership: membership
    })
  end

  defp secret_backend(_descriptor, _opts) do
    {:ok, %{material: %{bearer_token: "ephemeral-provider-token"}}}
  end
end
