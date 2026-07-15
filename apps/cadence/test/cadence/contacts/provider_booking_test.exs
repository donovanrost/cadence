defmodule Cadence.Contacts.ProviderBookingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{PathTemplate, ProviderBooking, ProviderReservations}
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{MissionProvider, ProviderError}
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-booking-#{suffix}"
    mission_id = "mission-provider-booking-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    provider = persist_provider!(organization_id, mission_id, suffix)

    {:ok, transport} =
      Cadence.persist_transport(
        organization_id,
        Transport.new(%{
          transport_id: "provider-transport-#{suffix}",
          mission_id: mission_id,
          display_name: "Simulator telemetry ingress",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-realtime-ttc-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence-primary", "version" => 7}
        })
      )

    {:ok, runtime_profile} =
      Cadence.fetch_provider_profile(
        organization_id,
        mission_id,
        transport.materialized_provider_profile_id
      )

    {:ok, path_template} =
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

  test "persists an attempt before the provider observes the request", context do
    attrs = booking_attrs(context)
    test_pid = self()

    on_reserve = fn provider_attrs ->
      assert provider_attrs == %{
               "client_reference" => attrs["idempotency_key"],
               "delivery_profile_ref" => attrs["delivery_profile_ref"]["id"],
               "opportunity_ref" => attrs["opportunity_ref"],
               "service_profile_ref" => attrs["service_profile_ref"]["id"],
               "spacecraft_ref" => attrs["provider_spacecraft_ref"],
               "tags" => %{"cadence_mission_ref" => context.mission_id}
             }

      assert {:ok, attempt} =
               ProviderReservations.fetch_by_idempotency_key(
                 context.organization_id,
                 context.mission_id,
                 context.provider.provider_id,
                 attrs["idempotency_key"]
               )

      send(test_pid, {:observed_attempt, attempt.lifecycle_state})
    end

    assert {:ok, booking} = reserve(context, attrs, on_reserve: on_reserve)
    assert_received {:observed_attempt, :requesting}
    assert booking.provider_reservation.lifecycle_state == :confirmed
    assert booking.scheduled_contact.scheduled_contact_id == attrs["scheduled_contact_id"]
  end

  test "replayed reservation makes one provider mutation", context do
    attrs = booking_attrs(context)
    test_pid = self()
    on_reserve = fn _attrs -> send(test_pid, :provider_mutation) end

    pending = provider_response(attrs, "pending")

    assert {:ok, first} =
             reserve(context, attrs, on_reserve: on_reserve, reserve_response: {:ok, pending})

    assert {:ok, replay} =
             reserve(context, attrs, on_reserve: on_reserve, reserve_response: {:ok, pending})

    assert_received :provider_mutation
    refute_received :provider_mutation
    assert first.provider_reservation.lifecycle_state == :pending

    assert replay.provider_reservation.provider_reservation_id ==
             first.provider_reservation.provider_reservation_id
  end

  test "pending does not materialize and confirmed materializes exactly once", context do
    attrs = booking_attrs(context)

    assert {:ok, pending} =
             reserve(context, attrs, reserve_response: {:ok, provider_response(attrs, "pending")})

    assert pending.provider_reservation.lifecycle_state == :pending
    assert is_nil(pending.scheduled_contact)

    assert {:ok, confirmed} =
             ProviderReservations.apply_provider_status(
               context.organization_id,
               context.mission_id,
               pending.provider_reservation.provider_reservation_id,
               provider_response(attrs, "confirmed")
             )

    assert confirmed.lifecycle_state == :confirmed
    assert confirmed.pass_phase == :scheduled
    assert confirmed.delivery_state == :ready

    assert confirmed.delivery_descriptor_document["endpoint_ref"] ==
             context.transport.delivery_profile_ref["id"]

    assert {:ok, replayed} =
             ProviderReservations.apply_provider_status(
               context.organization_id,
               context.mission_id,
               pending.provider_reservation.provider_reservation_id,
               provider_response(attrs, "confirmed")
             )

    assert replayed.scheduled_contact_id == confirmed.scheduled_contact_id

    assert length(Cadence.list_scheduled_contacts(context.organization_id, context.mission_id)) ==
             1
  end

  test "a conflicting delivery descriptor fails visibly without materializing a Contact",
       context do
    attrs = booking_attrs(context)

    response =
      attrs
      |> provider_response("confirmed")
      |> put_in(["delivery_descriptor", "endpoint_ref"], "unapproved-endpoint")

    assert {:error, {:provider_configuration_failure, failed, reason}} =
             reserve(context, attrs, reserve_response: {:ok, response})

    assert failed.lifecycle_state == :failed
    assert failed.last_error_document["category"] == "provider_configuration_failure"
    assert reason == :delivery_descriptor_conflicts_with_transport
    assert failed.delivery_descriptor_document == %{}
    assert Cadence.list_scheduled_contacts(context.organization_id, context.mission_id) == []
  end

  test "provider rejection remains durable without a Scheduled Contact", context do
    attrs = booking_attrs(context)

    assert {:error, {:provider_reservation_not_confirmed, rejected}} =
             reserve(context, attrs,
               reserve_response:
                 {:error,
                  ProviderError.from_response(409, %{
                    "error" => %{"code" => "no_capacity", "detail" => "antenna unavailable"}
                  })}
             )

    assert rejected.lifecycle_state == :rejected
    assert rejected.last_error_document["reason"] != nil
    assert [] == Cadence.list_scheduled_contacts(context.organization_id, context.mission_id)
  end

  test "ambiguous timeout becomes unknown and is not resubmitted", context do
    attrs = booking_attrs(context)
    test_pid = self()
    on_reserve = fn _attrs -> send(test_pid, :provider_mutation) end
    timeout = ProviderError.ambiguous(%{"reason" => "timeout"})

    assert {:error, {:provider_reservation_not_confirmed, unknown}} =
             reserve(context, attrs,
               on_reserve: on_reserve,
               reserve_response: {:error, timeout}
             )

    assert unknown.lifecycle_state == :unknown

    assert {:ok, replay} =
             reserve(context, attrs,
               on_reserve: on_reserve,
               reserve_response: {:ok, provider_response(attrs, "confirmed")}
             )

    assert replay.provider_reservation.lifecycle_state == :unknown
    assert_received :provider_mutation
    refute_received :provider_mutation
  end

  test "malformed provider times do not lose the attempt", context do
    attrs = booking_attrs(context)
    malformed = Map.put(provider_response(attrs, "confirmed"), "ends_at", "not-a-time")

    assert {:error, {:provider_reservation_not_confirmed, unknown}} =
             reserve(context, attrs, reserve_response: {:ok, malformed})

    assert unknown.lifecycle_state == :unknown
    assert unknown.last_error_document["reason"] != nil

    assert {:ok, persisted} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               unknown.provider_reservation_id
             )

    assert persisted.lifecycle_state == :unknown
  end

  test "known cancellation cancels the canonical contact", context do
    attrs = booking_attrs(context)
    assert {:ok, booking} = reserve(context, attrs)

    canceled_response = provider_response(attrs, "canceled")

    assert {:ok, canceled} =
             ProviderBooking.cancel(
               context.organization_id,
               context.mission_id,
               booking.provider_reservation.provider_reservation_id,
               client: FakeProviderClient,
               cancel_response: {:ok, canceled_response}
             )

    assert canceled.provider_reservation.lifecycle_state == :canceled
    assert canceled.scheduled_contact.lifecycle_state == :canceled
  end

  test "ambiguous cancellation leaves the contact intact and reconcilable", context do
    attrs = booking_attrs(context)
    assert {:ok, booking} = reserve(context, attrs)

    assert {:error, {:provider_reservation_not_confirmed, unknown}} =
             ProviderBooking.cancel(
               context.organization_id,
               context.mission_id,
               booking.provider_reservation.provider_reservation_id,
               client: FakeProviderClient,
               cancel_response:
                 {:error, ProviderError.ambiguous(%{"reason" => "connection_closed"})}
             )

    assert unknown.lifecycle_state == :unknown

    assert {:ok, scheduled_contact} =
             Cadence.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               booking.scheduled_contact.scheduled_contact_id
             )

    assert scheduled_contact.lifecycle_state == :scheduled
  end

  defp reserve(context, attrs, opts \\ []) do
    ProviderBooking.reserve(
      context.organization_id,
      context.mission_id,
      context.provider.provider_id,
      attrs,
      Keyword.put(opts, :client, FakeProviderClient)
    )
  end

  defp booking_attrs(context) do
    starts_at = DateTime.utc_now() |> DateTime.add(300) |> DateTime.truncate(:microsecond)
    ends_at = DateTime.add(starts_at, 600)

    %{
      "provider_reservation_id" => "provider-reservation-#{context.suffix}",
      "scheduled_contact_id" => "scheduled-contact-#{context.suffix}",
      "idempotency_key" => "idempotency-#{context.suffix}",
      "opportunity_ref" => "opportunity-#{context.suffix}",
      "cadence_spacecraft_id" => "spacecraft-#{context.suffix}",
      "provider_spacecraft_ref" => "SC-#{context.suffix}",
      "ground_station_ref" => "station-svalbard",
      "antenna_or_service_pool_ref" => "station-svalbard-antenna-1",
      "provider_version" => context.provider.version,
      "transport_id" => context.transport.transport_id,
      "transport_version" => context.transport.version,
      "service_profile_ref" => context.transport.service_profile_ref,
      "delivery_profile_ref" => context.transport.delivery_profile_ref,
      "provider_profile_id" => context.runtime_profile.provider_profile_id,
      "provider_profile_version" => context.runtime_profile.version,
      "transport_display_name" => context.transport.display_name,
      "service_display_name" => "Realtime TT&C downlink",
      "delivery_display_name" => "Cadence primary ingress",
      "delivery_operator_summary" => "Streaming to Cadence",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at),
      "source_endpoint_refs" => ["source-endpoint-#{context.suffix}"],
      "path_template_ids" => [context.path_template.path_template_id],
      "path_template_refs" => [
        %{
          "path_template_id" => context.path_template.path_template_id,
          "version" => context.path_template.version
        }
      ]
    }
  end

  defp provider_response(attrs, status) do
    %{
      "id" => "provider-reservation-external-#{attrs["idempotency_key"]}",
      "provider_contact_ref" => "provider-contact-#{attrs["idempotency_key"]}",
      "status" => status,
      "provider_status" => if(status == "confirmed", do: "scheduled", else: status),
      "pass_phase" => "scheduled",
      "delivery_state" => if(status == "confirmed", do: "ready", else: "pending"),
      "client_reference" => attrs["idempotency_key"],
      "opportunity_ref" => attrs["opportunity_ref"],
      "spacecraft_ref" => attrs["provider_spacecraft_ref"],
      "service_profile_ref" => attrs["service_profile_ref"]["id"],
      "delivery_profile_ref" => attrs["delivery_profile_ref"]["id"],
      "delivery_descriptor" => delivery_descriptor(attrs, status),
      "starts_at" => attrs["starts_at"],
      "ends_at" => attrs["ends_at"],
      "provider_evidence" => %{"ground_station_ref" => attrs["ground_station_ref"]}
    }
  end

  defp persist_provider!(organization_id, mission_id, suffix) do
    now = ~U[2026-07-14 12:00:00.000000Z]

    provider =
      MissionProvider.new(%{
        provider_id: "simulator-provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Ground Network Simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator-test",
        environment_ref: "run-alpha",
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

  defp delivery_descriptor(attrs, status) do
    starts_at = DateTime.from_iso8601(attrs["starts_at"]) |> elem(1)
    ends_at = DateTime.from_iso8601(attrs["ends_at"]) |> elem(1)

    %{
      "status" => if(status == "confirmed", do: "ready", else: "pending"),
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "protocol" => "tcp",
      "endpoint_ref" => attrs["delivery_profile_ref"]["id"],
      "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
      "allowed_source_refs" => [attrs["provider_spacecraft_ref"]],
      "activation_window" => %{
        "starts_at" => DateTime.to_iso8601(starts_at),
        "ends_at" => DateTime.to_iso8601(ends_at)
      },
      "credential_ref" => nil,
      "diagnostics" => %{"endpoint_health" => "healthy"}
    }
  end
end
