defmodule Cadence.ProviderChangeFixtures do
  @moduledoc false

  alias Cadence.Comms.TransportStore

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{PathTemplate, ProviderReservations}
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}

  def setup_contact(policy_document \\ %{}) do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-change-#{suffix}"
    mission_id = "mission-provider-change-#{suffix}"

    %{organization: organization} =
      Cadence.DataCase.persist_mission_scope(organization_id, mission_id)

    provider = persist_provider!(organization_id, mission_id, suffix, policy_document)

    {:ok, transport} =
      TransportStore.persist_transport(
        organization_id,
        Transport.new(%{
          transport_id: "transport-provider-change-#{suffix}",
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
          path_template_id: "path-provider-change-#{suffix}",
          mission_id: mission_id,
          path_id: "downlink-provider-change-#{suffix}",
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: "source-provider-change-#{suffix}",
          provider_profile_refs: [
            %{
              "provider_profile_id" => runtime_profile.provider_profile_id,
              "version" => runtime_profile.version
            }
          ]
        })
      )

    starts_at = ~U[2026-07-20 12:00:00.000000Z]
    ends_at = DateTime.add(starts_at, 600)

    {:ok, reservation} =
      ProviderReservations.create_attempt(organization_id, %{
        provider_reservation_id: "provider-reservation-change-#{suffix}",
        mission_id: mission_id,
        provider_id: provider.provider_id,
        provider_version: provider.version,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        service_profile_ref: transport.service_profile_ref,
        delivery_profile_ref: transport.delivery_profile_ref,
        provider_profile_id: runtime_profile.provider_profile_id,
        provider_profile_version: runtime_profile.version,
        scheduled_contact_id: "scheduled-contact-change-#{suffix}",
        provider_opportunity_ref: "opportunity-change-#{suffix}",
        idempotency_key: "client-reference-change-#{suffix}",
        spacecraft_id: "spacecraft-change-#{suffix}",
        provider_spacecraft_ref: "SC-CHANGE-#{suffix}",
        source_endpoint_refs: ["source-provider-change-#{suffix}"],
        path_template_ids: [path_template.path_template_id],
        starts_at: starts_at,
        ends_at: ends_at,
        request_document: %{
          "routing" => %{
            "path_template_refs" => [
              %{
                "path_template_id" => path_template.path_template_id,
                "version" => path_template.version
              }
            ]
          }
        }
      })

    baseline = response(reservation, 1, %{})

    {:ok, reservation} =
      ProviderReservations.apply_provider_status(
        organization_id,
        mission_id,
        reservation.provider_reservation_id,
        baseline
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      organization: organization,
      provider: provider,
      reservation: reservation,
      baseline: baseline,
      admin_scope: admin_scope(organization, suffix)
    }
  end

  def advance(context, revision, patch) do
    response =
      context.baseline
      |> Map.put("provider_revision", revision)
      |> Map.merge(patch)

    ProviderReservations.apply_provider_status(
      context.organization_id,
      context.mission_id,
      context.reservation.provider_reservation_id,
      response
    )
  end

  def shift(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp response(reservation, revision, patch) do
    Map.merge(
      %{
        "id" => "provider-contact-change-#{reservation.provider_reservation_id}",
        "provider_contact_ref" =>
          "provider-contact-change-#{reservation.provider_reservation_id}",
        "provider_revision" => revision,
        "client_reference" => reservation.idempotency_key,
        "opportunity_ref" => reservation.provider_opportunity_ref,
        "spacecraft_ref" => reservation.provider_spacecraft_ref,
        "ground_station_ref" => "station-alpha",
        "antenna_or_service_pool_ref" => "pool-alpha",
        "service_profile_ref" => reservation.service_profile_ref["id"],
        "delivery_profile_ref" => reservation.delivery_profile_ref["id"],
        "starts_at" => DateTime.to_iso8601(reservation.starts_at),
        "ends_at" => DateTime.to_iso8601(reservation.ends_at),
        "status" => "confirmed",
        "pass_phase" => "scheduled",
        "delivery_state" => "pending",
        "status_reason" => nil,
        "extensions" => %{
          "estimated_capacity" => %{"value" => 1_000_000, "unit" => "bytes"},
          "cost" => 100
        }
      },
      patch
    )
  end

  defp persist_provider!(organization_id, mission_id, suffix, policy_document) do
    provider =
      MissionProvider.new(%{
        provider_id: "provider-change-#{suffix}",
        mission_id: mission_id,
        display_name: "Simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator",
        environment_ref: "run-change-#{suffix}",
        last_validated_at: ~U[2026-07-15 12:00:00.000000Z],
        last_synced_at: ~U[2026-07-15 12:00:00.000000Z],
        delivery_policy_document: policy_document,
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

    {:ok, provider} = MissionProviders.persist_provider(organization_id, provider)
    provider
  end

  defp admin_scope(organization, suffix) do
    user =
      User.new(%{
        user_id: "user-provider-change-#{suffix}",
        email: "provider-change-#{suffix}@example.test",
        display_name: "Provider Change Admin"
      })

    membership =
      OrganizationMembership.new(%{
        organization_membership_id: "membership-provider-change-#{suffix}",
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: :organization_admin
      })

    Scope.new(%{
      user: user,
      organization: organization,
      organization_id: organization.organization_id,
      organization_membership: membership
    })
  end
end
