defmodule Cadence.Contacts.ProviderReservationReconcilerTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Management.Transports

  alias Cadence.Comms.Transport

  alias Cadence.Contacts.{
    PathTemplate,
    ProviderBooking,
    ProviderReservationReconciler,
    ProviderReservations
  }

  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials,
    ProviderError
  }

  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-reconciler-#{suffix}"
    mission_id = "mission-provider-reconciler-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    provider = persist_provider!(organization_id, mission_id, suffix)

    {:ok, transport} =
      Transports.persist_transport(
        organization_id,
        Transport.new(%{
          transport_id: "transport-#{suffix}",
          mission_id: mission_id,
          display_name: "Provider telemetry",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-realtime-ttc-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence-primary", "version" => 7}
        })
      )

    {:ok, runtime_profile} =
      Cadence.Contacts.fetch_provider_profile(
        organization_id,
        mission_id,
        transport.materialized_provider_profile_id
      )

    {:ok, path_template} =
      Cadence.Contacts.persist_path_template(
        organization_id,
        PathTemplate.new(%{
          path_template_id: "path-#{suffix}",
          mission_id: mission_id,
          path_id: "downlink-#{suffix}",
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: "source-#{suffix}",
          provider_profile_refs: [
            %{
              "provider_profile_id" => runtime_profile.provider_profile_id,
              "version" => runtime_profile.version
            }
          ]
        })
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      provider: provider,
      transport: transport,
      runtime_profile: runtime_profile,
      path_template: path_template,
      suffix: suffix
    }
  end

  test "pending to confirmed creates the preallocated Scheduled Contact once", context do
    {reservation, attrs} = pending_reservation(context)
    response = provider_response(reservation, attrs, "confirmed")

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             reconcile(context, describe_response: {:ok, response})

    assert {:ok, confirmed} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert confirmed.lifecycle_state == :confirmed
    assert confirmed.provider_account_id == context.provider.provider_account_id
    assert confirmed.provider_account_version == context.provider.provider_account_version
    assert confirmed.provider_account_grant_id == context.provider.provider_account_grant_id

    assert confirmed.provider_account_grant_version ==
             context.provider.provider_account_grant_version

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             reconcile(context,
               now: DateTime.add(DateTime.utc_now(), 1, :second),
               describe_response: {:ok, response}
             )

    assert length(
             Cadence.Contacts.list_scheduled_contacts(context.organization_id, context.mission_id)
           ) ==
             1
  end

  test "active and completed provider states converge", context do
    {reservation, attrs} = pending_reservation(context)

    assert {:ok, _summary} =
             reconcile(context,
               describe_response: {:ok, provider_response(reservation, attrs, "active")}
             )

    assert {:ok, active} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert active.lifecycle_state == :active

    assert {:ok, _summary} =
             reconcile(context,
               now: DateTime.add(DateTime.utc_now(), 1, :second),
               describe_response: {:ok, provider_response(reservation, attrs, "completed")}
             )

    assert {:ok, completed} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert completed.lifecycle_state == :completed
  end

  test "terminal failure states converge and cancel a materialized contact", context do
    {reservation, attrs} = pending_reservation(context)

    assert {:ok, _summary} =
             reconcile(context,
               describe_response: {:ok, provider_response(reservation, attrs, "confirmed")}
             )

    assert {:ok, _summary} =
             reconcile(context,
               now: DateTime.add(DateTime.utc_now(), 1, :second),
               describe_response: {:ok, provider_response(reservation, attrs, "failed")}
             )

    assert {:ok, failed} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert failed.lifecycle_state == :failed

    assert {:ok, contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.scheduled_contact_id
             )

    assert contact.lifecycle_state == :canceled
  end

  test "an unavailable provider records an error and observes backoff", context do
    {reservation, _attrs} = pending_reservation(context)

    assert {:ok, %{processed: 1, converged: 0, errors: 1}} =
             reconcile(context,
               describe_response: {:error, ProviderError.unavailable(%{"reason" => "offline"})}
             )

    assert {:ok, errored} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert errored.lifecycle_state == :pending
    assert errored.last_error_document["source"] == "provider_reservation_reconciler"

    assert {:ok, %{processed: 0}} =
             ProviderReservationReconciler.reconcile_due(
               context.organization_id,
               mission_id: context.mission_id,
               client: FakeProviderClient,
               backoff_ms: 60_000,
               describe_response: {:error, :still_offline}
             )
  end

  test "describe preserves a durable configuration failure for an unapproved descriptor",
       context do
    {reservation, attrs} = pending_reservation(context)

    response =
      reservation
      |> provider_response(attrs, "confirmed")
      |> Map.put("delivery_descriptor", conflicting_descriptor(attrs))

    assert {:ok, %{processed: 1, converged: 0, errors: 1}} =
             reconcile(context, describe_response: {:ok, response})

    assert {:ok, failed} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert failed.lifecycle_state == :failed
    assert failed.last_error_document["category"] == "provider_configuration_failure"
    assert failed.delivery_descriptor_document == %{}

    assert Cadence.Contacts.list_scheduled_contacts(context.organization_id, context.mission_id) ==
             []
  end

  test "organization and mission scope constrain durable work", context do
    {_reservation, _attrs} = pending_reservation(context)

    assert {:ok, %{processed: 0}} =
             ProviderReservationReconciler.reconcile_due(
               context.organization_id,
               mission_id: "another-mission",
               client: FakeProviderClient,
               backoff_ms: 0,
               describe_response: {:error, :should_not_run}
             )

    assert {:ok, %{processed: 0}} =
             ProviderReservationReconciler.reconcile_due(
               "another-organization",
               mission_id: context.mission_id,
               client: FakeProviderClient,
               backoff_ms: 0,
               describe_response: {:error, :should_not_run}
             )
  end

  test "process restart re-reads durable work", context do
    {reservation, attrs} = pending_reservation(context)
    response = provider_response(reservation, attrs, "confirmed")
    name = Module.concat(__MODULE__, "Reconciler#{context.suffix}")

    pid =
      start_supervised!({
        ProviderReservationReconciler,
        name: name,
        safety_poll_interval_ms: 60_000,
        client: FakeProviderClient,
        backoff_ms: 0,
        describe_response: {:ok, response}
      })

    Process.exit(pid, :kill)
    Process.sleep(10)

    restarted_pid = Process.whereis(name)
    assert is_pid(restarted_pid)
    refute restarted_pid == pid

    assert {:ok, %{processed: 1, converged: 1}} =
             ProviderReservationReconciler.reconcile_now(name)

    assert {:ok, confirmed} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert confirmed.lifecycle_state == :confirmed
  end

  defp reconcile(context, opts) do
    ProviderReservationReconciler.reconcile_due(
      context.organization_id,
      [
        mission_id: context.mission_id,
        client: FakeProviderClient,
        backoff_ms: 0
      ] ++ opts
    )
  end

  defp pending_reservation(context) do
    attrs = booking_attrs(context)

    assert {:ok, booking} =
             ProviderBooking.reserve(
               context.organization_id,
               context.mission_id,
               context.provider.provider_id,
               attrs,
               client: FakeProviderClient,
               reserve_response: {:ok, provider_response(nil, attrs, "pending")}
             )

    {booking.provider_reservation, attrs}
  end

  defp booking_attrs(context) do
    starts_at = DateTime.utc_now() |> DateTime.add(300) |> DateTime.truncate(:microsecond)

    %{
      "provider_reservation_id" => "provider-reservation-#{context.suffix}",
      "scheduled_contact_id" => "scheduled-contact-#{context.suffix}",
      "idempotency_key" => "idempotency-#{context.suffix}",
      "opportunity_ref" => "opportunity-#{context.suffix}",
      "cadence_spacecraft_id" => "spacecraft-#{context.suffix}",
      "provider_spacecraft_ref" => "SC-#{context.suffix}",
      "ground_station_ref" => "station-alpha",
      "antenna_or_service_pool_ref" => "antenna-alpha",
      "provider_version" => context.provider.version,
      "transport_id" => context.transport.transport_id,
      "transport_version" => context.transport.version,
      "service_profile_ref" => context.transport.service_profile_ref,
      "delivery_profile_ref" => context.transport.delivery_profile_ref,
      "provider_profile_id" => context.runtime_profile.provider_profile_id,
      "provider_profile_version" => context.runtime_profile.version,
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(600) |> DateTime.to_iso8601(),
      "source_endpoint_refs" => ["source-#{context.suffix}"],
      "path_template_ids" => [context.path_template.path_template_id],
      "path_template_refs" => [
        %{
          "path_template_id" => context.path_template.path_template_id,
          "version" => context.path_template.version
        }
      ]
    }
  end

  defp provider_response(reservation, attrs, status) do
    provider_contact_ref =
      if reservation,
        do: reservation.provider_contact_ref || "provider-contact-#{attrs["idempotency_key"]}",
        else: "provider-contact-#{attrs["idempotency_key"]}"

    %{
      "id" => "external-reservation-#{attrs["idempotency_key"]}",
      "provider_contact_ref" => provider_contact_ref,
      "status" => status,
      "provider_status" => if(status == "confirmed", do: "scheduled", else: status),
      "pass_phase" => "scheduled",
      "delivery_state" => if(status == "confirmed", do: "ready", else: "pending"),
      "client_reference" => attrs["idempotency_key"],
      "opportunity_ref" => attrs["opportunity_ref"],
      "spacecraft_ref" => attrs["provider_spacecraft_ref"],
      "service_profile_ref" => attrs["service_profile_ref"]["id"],
      "delivery_profile_ref" => attrs["delivery_profile_ref"]["id"],
      "starts_at" => attrs["starts_at"],
      "ends_at" => attrs["ends_at"],
      "provider_evidence" => %{}
    }
  end

  defp persist_provider!(organization_id, mission_id, suffix) do
    now = ~U[2026-07-14 12:00:00.000000Z]
    account_id = "provider-account-#{suffix}"
    credential_ref = "provider-credential-#{suffix}"

    {:ok, _credential} =
      ProviderCredentials.create(
        organization_id,
        account_id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "providers/#{suffix}/control-plane",
          registered_at: now
        },
        manage_backend?: false,
        now: now
      )

    actor = %{"kind" => "system", "id" => "provider-reconciler-test"}

    {:ok, _account, account_version} =
      ProviderAccounts.create_for_system(
        organization_id,
        %{
          provider_account_id: account_id,
          display_name: "Simulator Account",
          provider_type: :simulator,
          base_url: "http://simulator.test",
          environment_ref: "run-alpha",
          credential_ref: credential_ref
        },
        actor,
        validate_credential?: false,
        now: now
      )

    {:ok, grant} =
      ProviderAccountGrants.grant_for_system(
        organization_id,
        mission_id,
        account_id,
        %{provider_account_grant_id: "provider-account-grant-#{suffix}"},
        actor,
        now: now
      )

    provider =
      MissionProvider.new(%{
        provider_id: "provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Simulator",
        provider_account_id: account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        provider_type: account_version.provider_type,
        client_key: account_version.client_key,
        base_url: account_version.base_url,
        credential_ref: account_version.credential_ref,
        environment_ref: account_version.environment_ref,
        last_validated_at: now,
        last_synced_at: now,
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

  defp conflicting_descriptor(attrs) do
    %{
      "status" => "ready",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "protocol" => "tcp",
      "endpoint_ref" => "unapproved-endpoint",
      "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
      "allowed_source_refs" => [attrs["provider_spacecraft_ref"]],
      "activation_window" => %{
        "starts_at" => attrs["starts_at"],
        "ends_at" => attrs["ends_at"]
      },
      "credential_ref" => nil,
      "diagnostics" => %{}
    }
  end
end
