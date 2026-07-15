defmodule Cadence.Contacts.ProviderReservationReconcilerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{
    PathTemplate,
    ProviderBooking,
    ProviderProfile,
    ProviderReservationReconciler,
    ProviderReservations
  }

  alias Cadence.GroundNetworks.ProviderError
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-reconciler-#{suffix}"
    mission_id = "mission-provider-reconciler-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    {:ok, provider} =
      Cadence.persist_provider_profile(
        organization_id,
        ProviderProfile.new(%{
          provider_profile_id: "provider-#{suffix}",
          mission_id: mission_id,
          adapter_key: :tcp_socket,
          configuration: %{"mode" => "listen", "port" => 4_100}
        })
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

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             reconcile(context,
               now: DateTime.add(DateTime.utc_now(), 1, :second),
               describe_response: {:ok, response}
             )

    assert length(Cadence.list_scheduled_contacts(context.organization_id, context.mission_id)) ==
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
             Cadence.fetch_scheduled_contact(
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
               context.provider.provider_profile_id,
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
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "delivery_profile_ref" => "delivery-cadence-primary",
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
      "starts_at" => attrs["starts_at"],
      "ends_at" => attrs["ends_at"],
      "provider_evidence" => %{}
    }
  end
end
