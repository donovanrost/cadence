defmodule CadenceSimulator.ContactSchedulingIntegrationTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}

  alias Cadence.Contacts.{
    LinkAssignment,
    PathTemplate,
    ProviderBooking,
    ProviderProfile,
    ProviderReservationReconciler,
    ProviderScheduling
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
      post!(context.base_url <> "/v1/scenarios", %{
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
      post!(context.base_url <> "/v1/scenarios/#{scenario["id"]}/runs", %{
        "seed" => 2_026,
        "speed" => 1.0
      })

    setup = persist_cadence_setup(context, run)
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
               }
             )

    assert route.provider_spacecraft_ref == "SC-001"

    booking_attrs = booking_attrs(setup, opportunity, "primary")

    assert {:ok, booking} =
             ProviderBooking.reserve(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_profile_id,
               booking_attrs
             )

    assert booking.provider_reservation.lifecycle_state == :pending
    assert is_nil(booking.scheduled_contact)

    :ok = Orchestrator.reconcile(DateTime.utc_now())

    assert {:ok, %{processed: 1, converged: 1, errors: 0}} =
             ProviderReservationReconciler.reconcile_due(
               setup.organization_id,
               mission_id: setup.mission_id,
               backoff_ms: 0
             )

    assert {:ok, scheduled_contact} =
             Cadence.fetch_scheduled_contact(
               setup.organization_id,
               setup.mission_id,
               booking.provider_reservation.scheduled_contact_id
             )

    assert scheduled_contact.provider_contact_ref ==
             booking.provider_reservation.provider_contact_ref

    assert length(Cadence.list_scheduled_contacts(setup.organization_id, setup.mission_id)) == 1

    assert %{"data" => %{"status" => "scheduled"}} =
             Req.get!(
               context.base_url <>
                 "/v1/contact-reservations/#{booking.provider_reservation.response_document["id"]}"
             ).body

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
               now: DateTime.add(DateTime.utc_now(), 1, :second)
             )

    assert {:ok, completed_reservation} =
             Cadence.fetch_provider_reservation(
               setup.organization_id,
               setup.mission_id,
               booking.provider_reservation.provider_reservation_id
             )

    assert completed_reservation.lifecycle_state == :completed

    assert {:ok, _scheduler_summary} =
             Cadence.Contacts.reconcile(setup.mission_id, DateTime.add(opportunity_ends_at, 1))

    second_opportunity = List.first(more_opportunities)
    assert is_map(second_opportunity)

    assert {:ok, second_booking} =
             ProviderBooking.reserve(
               setup.organization_id,
               setup.mission_id,
               setup.provider.provider_profile_id,
               booking_attrs(setup, second_opportunity, "cancel")
             )

    assert {:ok, canceled_booking} =
             ProviderBooking.cancel(
               setup.organization_id,
               setup.mission_id,
               second_booking.provider_reservation.provider_reservation_id
             )

    assert canceled_booking.provider_reservation.lifecycle_state == :canceled

    assert {:ok, %{processed: 0}} =
             ProviderReservationReconciler.reconcile_due(
               setup.organization_id,
               mission_id: setup.mission_id,
               backoff_ms: 0,
               now: DateTime.add(DateTime.utc_now(), 2, :second)
             )

    assert length(Cadence.list_scheduled_contacts(setup.organization_id, setup.mission_id)) == 1

    assert length(Cadence.list_provider_reservations(setup.organization_id, setup.mission_id)) ==
             2
  end

  defp persist_cadence_setup(context, run) do
    suffix = System.unique_integer([:positive])
    organization_id = "org-simulator-scheduling-#{suffix}"
    mission_id = "mission-simulator-scheduling-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-#{suffix}",
        mission_id: mission_id,
        display_name: "Boundary Proof Spacecraft"
      })

    assert {:ok, spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-#{suffix}",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "SC-001",
        scid: 0,
        display_name: "Simulator SC-001"
      })

    assert {:ok, endpoint} = Cadence.persist_source_endpoint(organization_id, endpoint)
    persist_telemetry_binding!(organization_id, mission_id, suffix)

    provider =
      ProviderProfile.new(%{
        provider_profile_id: "provider-#{suffix}",
        mission_id: mission_id,
        adapter_key: :tcp_socket,
        configuration: %{
          "adapter" => "tcp_socket",
          "mode" => "listen",
          "direction" => "downlink",
          "host" => "127.0.0.1",
          "port" => context.telemetry_port,
          "ingress_protocol_family" => "tm",
          "frame_size" => 1_115,
          "fixed_message_bytes" => 1_115,
          "framing" => %{"mode" => "fixed_size", "fixed_message_bytes" => 1_115},
          "ingress_metadata" => %{"frame_size" => 1_115, "ocf_length" => 0},
          "scheduling" => %{
            "client" => "simulator_http",
            "base_url" => context.base_url,
            "delivery_host" => "127.0.0.1",
            "run_id" => run["id"]
          }
        },
        metadata: %{"display_name" => "External simulator"}
      })

    assert {:ok, provider} = Cadence.persist_provider_profile(organization_id, provider)

    path =
      PathTemplate.new(%{
        path_template_id: "path-#{suffix}",
        mission_id: mission_id,
        path_id: "simulator-downlink-#{suffix}",
        direction: :downlink,
        selection_role: :selected,
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ],
        metadata: %{"display_name" => "Simulator telemetry downlink"}
      })

    assert {:ok, path} = Cadence.persist_path_template(organization_id, path)

    assignment =
      LinkAssignment.new(%{
        link_assignment_id: "assignment-#{suffix}",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: endpoint.source_endpoint_id,
        path_template_id: path.path_template_id,
        path_template_version: path.version,
        direction: :downlink,
        selection_role: :selected,
        provider_profile_refs: path.provider_profile_refs
      })

    assert {:ok, _assignment} = Cadence.persist_link_assignment(organization_id, assignment)

    assert {:ok, %{routes: [route], findings: []}} =
             ProviderScheduling.list_ready_downlink_routes(
               organization_id,
               mission_id,
               spacecraft.spacecraft_id
             )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft: spacecraft,
      endpoint: endpoint,
      provider: provider,
      path: path,
      route: route
    }
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
    |> Map.put("provider_profile_version", setup.provider.version)
    |> Map.put("source_endpoint_refs", [setup.endpoint.source_endpoint_id])
    |> Map.put("path_template_ids", [setup.path.path_template_id])
    |> Map.put("path_template_refs", [
      %{"path_template_id" => setup.path.path_template_id, "version" => setup.path.version}
    ])
    |> Map.put("opportunity_id", opportunity["id"])
  end

  defp post!(url, body) do
    response = Req.post!(url, json: body)
    assert response.status in 200..299
    response.body["data"]
  end

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
