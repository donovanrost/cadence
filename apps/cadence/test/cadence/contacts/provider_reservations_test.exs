defmodule Cadence.Contacts.ProviderReservationsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{PathTemplate, ProviderReservations}
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-reservations-#{suffix}"
    mission_id = "mission-provider-reservations-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    provider = persist_provider!(organization_id, mission_id, suffix)

    {:ok, transport} =
      TransportStore.persist_transport(
        organization_id,
        Transport.new(%{
          transport_id: "transport-#{suffix}",
          mission_id: mission_id,
          display_name: "Provider telemetry",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
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

  test "creates an organization-scoped attempt idempotently", context do
    attrs = attempt_attrs(context)

    assert {:ok, first} = ProviderReservations.create_attempt(context.organization_id, attrs)
    assert {:ok, replay} = ProviderReservations.create_attempt(context.organization_id, attrs)

    assert replay.provider_reservation_id == first.provider_reservation_id
    assert replay.lifecycle_state == :requesting

    assert [persisted] =
             ProviderReservations.list_for_mission(context.organization_id, context.mission_id)

    assert persisted.provider_reservation_id == first.provider_reservation_id

    assert {:error, :provider_reservation_not_found} =
             ProviderReservations.fetch(
               "another-organization",
               context.mission_id,
               first.provider_reservation_id
             )
  end

  test "rejects a conflicting payload under the same idempotency key", context do
    attrs = attempt_attrs(context)
    assert {:ok, first} = ProviderReservations.create_attempt(context.organization_id, attrs)

    assert {:error, {:idempotency_conflict, reservation_id}} =
             ProviderReservations.create_attempt(
               context.organization_id,
               Map.put(attrs, :ends_at, DateTime.add(attrs.ends_at, 60))
             )

    assert reservation_id == first.provider_reservation_id
  end

  test "enforces unique provider contact references within a mission", context do
    first_attrs = attempt_attrs(context)
    second_attrs = attempt_attrs(context, "second")

    assert {:ok, first} =
             ProviderReservations.create_attempt(context.organization_id, first_attrs)

    assert {:ok, second} =
             ProviderReservations.create_attempt(context.organization_id, second_attrs)

    response = provider_response(first, "shared-provider-contact", "pending")

    assert {:ok, _first} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               first.provider_reservation_id,
               response
             )

    assert {:error, %Ecto.Changeset{}} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               second.provider_reservation_id,
               response
             )
  end

  test "validates lifecycle transitions and preserves terminal state", context do
    assert {:ok, reservation} =
             ProviderReservations.create_attempt(context.organization_id, attempt_attrs(context))

    assert {:ok, pending} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               provider_response(reservation, "provider-alpha", "pending")
             )

    assert pending.lifecycle_state == :pending

    assert {:ok, rejected} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               provider_response(reservation, "provider-alpha", "rejected")
             )

    assert rejected.lifecycle_state == :rejected

    assert {:ok, replayed} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               provider_response(reservation, "provider-alpha", "rejected")
             )

    assert replayed.lifecycle_state == :rejected

    assert {:error, {:invalid_provider_reservation_transition, :rejected, :confirmed}} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               provider_response(reservation, "provider-alpha", "scheduled")
             )
  end

  test "materializes one preallocated Scheduled Contact idempotently", context do
    assert {:ok, reservation} =
             ProviderReservations.create_attempt(context.organization_id, attempt_attrs(context))

    response = provider_response(reservation, "provider-alpha", "scheduled")

    assert {:ok, confirmed} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               response
             )

    assert {:ok, first} =
             ProviderReservations.materialize_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert {:ok, replay} =
             ProviderReservations.materialize_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert first.scheduled_contact.scheduled_contact_id == confirmed.scheduled_contact_id

    assert replay.scheduled_contact.scheduled_contact_id ==
             first.scheduled_contact.scheduled_contact_id

    assert length(Cadence.list_scheduled_contacts(context.organization_id, context.mission_id)) ==
             1
  end

  test "rolls back reservation linkage when the Scheduled Contact is invalid", context do
    attrs =
      context
      |> attempt_attrs()
      |> Map.put(:path_template_ids, ["missing-path-template"])
      |> put_in([:request_document, "routing", "path_template_refs"], [
        %{"path_template_id" => "missing-path-template", "version" => 1}
      ])

    assert {:ok, reservation} =
             ProviderReservations.create_attempt(context.organization_id, attrs)

    assert {:ok, _confirmed} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               provider_response(reservation, "provider-invalid", "scheduled")
             )

    assert {:error, _reason} =
             ProviderReservations.materialize_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    assert [] == Cadence.list_scheduled_contacts(context.organization_id, context.mission_id)

    assert {:ok, persisted} =
             ProviderReservations.fetch(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id
             )

    refute Map.has_key?(persisted.metadata, "scheduled_contact_id")
  end

  test "lists only due nonterminal reservations in oldest-first order", context do
    assert {:ok, first} =
             ProviderReservations.create_attempt(
               context.organization_id,
               attempt_attrs(context, "first")
             )

    Process.sleep(2)

    assert {:ok, second} =
             ProviderReservations.create_attempt(
               context.organization_id,
               attempt_attrs(context, "second")
             )

    assert {:ok, terminal} =
             ProviderReservations.create_attempt(
               context.organization_id,
               attempt_attrs(context, "terminal")
             )

    assert {:ok, _terminal} =
             ProviderReservations.record_provider_response(
               context.organization_id,
               context.mission_id,
               terminal.provider_reservation_id,
               provider_response(terminal, "provider-terminal", "rejected")
             )

    assert [due_first, due_second] =
             ProviderReservations.list_due_for_reconciliation(
               context.organization_id,
               mission_id: context.mission_id
             )

    assert due_first.provider_reservation_id == first.provider_reservation_id
    assert due_second.provider_reservation_id == second.provider_reservation_id
  end

  defp attempt_attrs(context, suffix \\ "alpha") do
    starts_at = DateTime.utc_now() |> DateTime.add(300) |> DateTime.truncate(:microsecond)
    ends_at = DateTime.add(starts_at, 600)
    source_endpoint_ref = "source-#{context.suffix}"

    %{
      provider_reservation_id: "provider-reservation-#{context.suffix}-#{suffix}",
      mission_id: context.mission_id,
      provider_id: context.provider.provider_id,
      provider_version: context.provider.version,
      transport_id: context.transport.transport_id,
      transport_version: context.transport.version,
      service_profile_ref: context.transport.service_profile_ref,
      delivery_profile_ref: context.transport.delivery_profile_ref,
      provider_profile_id: context.runtime_profile.provider_profile_id,
      provider_profile_version: context.runtime_profile.version,
      scheduled_contact_id: "scheduled-contact-#{context.suffix}-#{suffix}",
      provider_opportunity_ref: "opportunity-#{suffix}",
      idempotency_key: "idempotency-#{suffix}",
      lifecycle_state: :requesting,
      spacecraft_id: "spacecraft-#{context.suffix}",
      provider_spacecraft_ref: "SC-#{context.suffix}",
      source_endpoint_refs: [source_endpoint_ref],
      path_template_ids: [context.path_template.path_template_id],
      starts_at: starts_at,
      ends_at: ends_at,
      request_document: %{
        "opportunity_id" => "opportunity-#{suffix}",
        "routing" => %{
          "path_template_refs" => [
            %{
              "path_template_id" => context.path_template.path_template_id,
              "version" => context.path_template.version
            }
          ]
        }
      }
    }
  end

  defp provider_response(reservation, provider_contact_ref, status) do
    %{
      "id" => provider_contact_ref,
      "provider_contact_ref" => provider_contact_ref,
      "status" => status,
      "starts_at" => DateTime.to_iso8601(reservation.starts_at),
      "ends_at" => DateTime.to_iso8601(reservation.ends_at)
    }
  end

  defp persist_provider!(organization_id, mission_id, suffix) do
    now = ~U[2026-07-14 12:00:00.000000Z]

    provider =
      MissionProvider.new(%{
        provider_id: "provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator",
        environment_ref: "run-alpha",
        last_validated_at: now,
        last_synced_at: now,
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: %{
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
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end
end
