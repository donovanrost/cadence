defmodule Cadence.Contacts.ProviderReservationsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Management.Transports

  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{PathTemplate, ProviderReservations}
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-reservations-#{suffix}"
    mission_id = "mission-provider-reservations-#{suffix}"
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
          service_profile_ref: %{"id" => "service-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
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

    assert length(
             Cadence.Contacts.list_scheduled_contacts(context.organization_id, context.mission_id)
           ) ==
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

    assert [] ==
             Cadence.Contacts.list_scheduled_contacts(context.organization_id, context.mission_id)

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

  test "uncertain reservation evidence is scoped, audited and idempotent", c do
    {:ok, reservation} = ProviderReservations.create_attempt(c.organization_id, attempt_attrs(c))
    scope = resolution_scope(c)

    {:ok, review} =
      ControlContacts.review_provider_reservation_resolution(
        scope,
        c.mission_id,
        reservation.provider_reservation_id
      )

    attrs = resolution_evidence(review, "unknown")

    assert {:ok, result} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               attrs
             )

    assert result.reservation.lifecycle_state == :unknown

    assert {:ok, replay} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               attrs
             )

    assert [entry] = replay.reservation.resolution_evidence["entries"]
    assert entry["actor"] == %{"kind" => "service", "id" => "resolution-service"}
    assert entry["reference"] == "provider-case/123"

    assert {:error, :resolution_id_conflict} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               %{attrs | "outcome" => "not_sent"}
             )

    assert {:error, :provider_resolution_basis_changed} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               %{attrs | "basis_sha256" => String.duplicate("0", 64)}
             )

    assert {:error, :forbidden} =
             ControlContacts.resolve_provider_reservation(
               %{scope | capabilities: MapSet.new()},
               c.mission_id,
               reservation.provider_reservation_id,
               attrs
             )

    assert {:error, :provider_reservation_not_found} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               "absent",
               attrs
             )
  end

  test "accepted reservation evidence materializes once and contradictory evidence preserves it",
       c do
    {:ok, reservation} = ProviderReservations.create_attempt(c.organization_id, attempt_attrs(c))
    scope = resolution_scope(c)

    {:ok, review} =
      ControlContacts.review_provider_reservation_resolution(
        scope,
        c.mission_id,
        reservation.provider_reservation_id
      )

    response =
      provider_response(reservation, "resolved-provider-contact", "confirmed")
      |> Map.put("client_reference", reservation.idempotency_key)

    attrs = resolution_evidence(review, "accepted") |> Map.put("provider_response", response)

    assert {:ok, result} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               attrs
             )

    assert result.reservation.lifecycle_state == :confirmed

    assert {:ok, _} =
             Cadence.Contacts.fetch_scheduled_contact(
               c.organization_id,
               c.mission_id,
               reservation.scheduled_contact_id
             )

    assert {:ok, _} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               attrs
             )

    contradictory =
      resolution_evidence(review, "not_sent") |> Map.put("resolution_id", "contradictory")

    assert {:ok, retained} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               contradictory
             )

    assert retained.disposition == "contradictory"
    assert retained.reservation.lifecycle_state == :confirmed
    assert length(retained.reservation.resolution_evidence["entries"]) == 2
  end

  test "unconfirmed non-delivery closes the original reservation without another provider call",
       c do
    attrs = attempt_attrs(c)
    {:ok, reservation} = ProviderReservations.create_attempt(c.organization_id, attrs)
    scope = resolution_scope(c)

    {:ok, review} =
      ControlContacts.review_provider_reservation_resolution(
        scope,
        c.mission_id,
        reservation.provider_reservation_id
      )

    assert {:ok, resolved} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               resolution_evidence(review, "not_sent")
             )

    assert resolved.reservation.lifecycle_state == :failed

    assert {:ok, existing, :existing} =
             ProviderReservations.create_attempt_with_outcome(c.organization_id, attrs)

    assert existing.provider_reservation_id == reservation.provider_reservation_id
    assert existing.lifecycle_state == :failed

    assert {:ok, retained} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               resolution_evidence(review, "accepted")
               |> Map.put("resolution_id", "late-acceptance")
             )

    assert retained.disposition == "contradictory"
    assert retained.reservation.lifecycle_state == :failed
  end

  test "provider evidence must correlate to the original booking and cannot forge audit history",
       c do
    {:ok, reservation} = ProviderReservations.create_attempt(c.organization_id, attempt_attrs(c))
    scope = resolution_scope(c)

    {:ok, review} =
      ControlContacts.review_provider_reservation_resolution(
        scope,
        c.mission_id,
        reservation.provider_reservation_id
      )

    attrs =
      resolution_evidence(review, "accepted")
      |> Map.put("provider_response", %{
        "id" => "other-contact",
        "client_reference" => "other-booking"
      })

    assert {:error, :provider_resolution_correlation_mismatch} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               attrs
             )

    assert {:ok, unchanged} =
             ProviderReservations.fetch(
               c.organization_id,
               c.mission_id,
               reservation.provider_reservation_id
             )

    assert unchanged.resolution_evidence == %{}
    assert unchanged.lifecycle_state == :requesting

    assert {:ok, _} =
             ProviderReservations.record_provider_response(
               c.organization_id,
               c.mission_id,
               reservation.provider_reservation_id,
               provider_response(reservation, "known-contact", "pending")
             )

    assert {:ok, held} =
             ControlContacts.resolve_provider_reservation(
               scope,
               c.mission_id,
               reservation.provider_reservation_id,
               resolution_evidence(review, "not_sent")
             )

    assert held.disposition == "held_provider_status_required"
    assert held.reservation.lifecycle_state == :pending

    for response <- [
          %{"client_reference" => reservation.idempotency_key, "id" => "different-contact"},
          %{"client_reference" => "different-booking", "id" => "known-contact"}
        ] do
      conflicting =
        resolution_evidence(review, "accepted")
        |> Map.put("resolution_id", "conflicting-identifiers")
        |> Map.put("provider_response", Map.put(response, "status", "confirmed"))

      assert {:error, :provider_resolution_correlation_mismatch} =
               ControlContacts.resolve_provider_reservation(
                 scope,
                 c.mission_id,
                 reservation.provider_reservation_id,
                 conflicting
               )
    end
  end

  defp resolution_scope(c) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: "resolution-service",
        organization_id: c.organization_id,
        mission_id: c.mission_id,
        display_name: "Resolution",
        capabilities: [:mission_admin]
      })

    %Scope{
      actor_kind: :service,
      organization_id: c.organization_id,
      mission_id: c.mission_id,
      service_identity: identity,
      capabilities: MapSet.new([:mission_admin])
    }
  end

  defp resolution_evidence(review, outcome),
    do: %{
      "resolution_id" => "resolution-1",
      "basis_sha256" => review.basis_sha256,
      "outcome" => outcome,
      "source" => "provider_receipt",
      "reference" => "provider-case/123",
      "observed_at" => "2026-10-26T00:00:00Z",
      "acceptance_stage" => "provider_acceptance"
    }

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
