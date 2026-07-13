defmodule Cadence.Contacts.ProviderBookingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{
    PathTemplate,
    ProviderBooking,
    ProviderContactReconciler,
    ProviderProfile
  }

  alias Cadence.TestSupport.FakeProviderClient

  setup do
    organization_id = "org-provider-booking-#{System.unique_integer([:positive])}"
    mission_id = "mission-provider-booking-#{System.unique_integer([:positive])}"
    persist_mission_scope(organization_id, mission_id)

    {:ok, provider} =
      Cadence.persist_provider_profile(
        organization_id,
        ProviderProfile.new(%{
          provider_profile_id: "simulator-provider",
          mission_id: mission_id,
          adapter_key: :tcp_socket,
          configuration: %{"mode" => "listen", "port" => 4100}
        })
      )

    {:ok, path_template} =
      Cadence.persist_path_template(
        organization_id,
        PathTemplate.new(%{
          path_template_id: "simulator-downlink",
          mission_id: mission_id,
          path_id: "simulator-downlink-path",
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: "source-endpoint-alpha",
          provider_profile_ids: [provider.provider_profile_id]
        })
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      provider: provider,
      path_template: path_template
    }
  end

  test "books provider capacity before persisting the Cadence scheduled contact", context do
    starts_at = DateTime.utc_now() |> DateTime.add(300) |> DateTime.to_iso8601()
    ends_at = DateTime.utc_now() |> DateTime.add(900) |> DateTime.to_iso8601()

    attrs = %{
      "run_id" => "run-alpha",
      "opportunity_id" => "opportunity-alpha",
      "spacecraft_id" => "SC-001",
      "ground_station_id" => "station-svalbard",
      "antenna_id" => "station-svalbard-antenna-1",
      "starts_at" => starts_at,
      "ends_at" => ends_at,
      "source_endpoint_refs" => ["source-endpoint-alpha"],
      "path_template_ids" => [context.path_template.path_template_id]
    }

    assert {:ok, booking} =
             ProviderBooking.book(
               context.organization_id,
               context.mission_id,
               context.provider.provider_profile_id,
               attrs,
               client: FakeProviderClient
             )

    assert booking.provider_reservation["id"] == "provider-reservation-alpha"
    assert booking.provider_reservation["mission_profile_ref"] == context.mission_id
    assert booking.scheduled_contact.provider_contact_ref == "provider-reservation-alpha"
    assert booking.scheduled_contact.source_endpoint_refs == ["source-endpoint-alpha"]
    assert booking.scheduled_contact.path_template_ids == ["simulator-downlink"]
    refute Map.has_key?(booking.scheduled_contact.metadata, "synthetic")

    assert {:ok, persisted} =
             Cadence.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               booking.scheduled_contact.scheduled_contact_id
             )

    assert persisted.provider_contact_ref == "provider-reservation-alpha"
  end

  test "reconciles a terminal provider event into canonical contact cancellation", context do
    starts_at = DateTime.utc_now() |> DateTime.add(300) |> DateTime.to_iso8601()
    ends_at = DateTime.utc_now() |> DateTime.add(900) |> DateTime.to_iso8601()

    {:ok, booking} =
      ProviderBooking.book(
        context.organization_id,
        context.mission_id,
        context.provider.provider_profile_id,
        %{
          "opportunity_id" => "opportunity-failure",
          "spacecraft_id" => "SC-001",
          "ground_station_id" => "station-svalbard",
          "antenna_id" => "station-svalbard-antenna-1",
          "starts_at" => starts_at,
          "ends_at" => ends_at,
          "source_endpoint_refs" => ["source-endpoint-alpha"],
          "path_template_ids" => [context.path_template.path_template_id]
        },
        client: FakeProviderClient
      )

    event = %{
      "type" => "reservation.failed",
      "resource_id" => booking.provider_reservation["id"],
      "data" => %{
        "mission_profile_ref" => context.mission_id,
        "reason" => "simulated_acquisition_failure"
      }
    }

    assert %{canceled: 1, ignored: 0} = ProviderContactReconciler.reconcile_events([event])

    assert {:ok, canceled} =
             Cadence.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               booking.scheduled_contact.scheduled_contact_id
             )

    assert canceled.lifecycle_state == :canceled
    assert canceled.metadata["reason"] == "simulated_acquisition_failure"
  end
end
