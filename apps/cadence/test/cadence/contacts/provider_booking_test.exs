defmodule Cadence.Contacts.ProviderBookingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{PathTemplate, ProviderBooking, ProviderProfile, ProviderReservations}
  alias Cadence.GroundNetworks.ProviderError
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-booking-#{suffix}"
    mission_id = "mission-provider-booking-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    {:ok, provider} =
      Cadence.persist_provider_profile(
        organization_id,
        ProviderProfile.new(%{
          provider_profile_id: "simulator-provider-#{suffix}",
          mission_id: mission_id,
          adapter_key: :tcp_socket,
          configuration: %{"mode" => "listen", "port" => 4_100}
        })
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
          provider_profile_ids: [provider.provider_profile_id]
        })
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      provider: provider,
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
               "delivery_profile_ref" => attrs["delivery_profile_ref"],
               "opportunity_ref" => attrs["opportunity_ref"],
               "service_profile_ref" => attrs["service_profile_ref"],
               "spacecraft_ref" => attrs["provider_spacecraft_ref"],
               "tags" => %{"cadence_mission_ref" => context.mission_id}
             }

      assert {:ok, attempt} =
               ProviderReservations.fetch_by_idempotency_key(
                 context.organization_id,
                 context.mission_id,
                 context.provider.provider_profile_id,
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
      context.provider.provider_profile_id,
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
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "delivery_profile_ref" => "delivery-cadence-primary",
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
      "starts_at" => attrs["starts_at"],
      "ends_at" => attrs["ends_at"],
      "provider_evidence" => %{"ground_station_ref" => attrs["ground_station_ref"]}
    }
  end
end
