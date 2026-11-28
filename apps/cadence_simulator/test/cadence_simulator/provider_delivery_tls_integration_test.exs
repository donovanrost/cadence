defmodule CadenceSimulator.ProviderDeliveryTLSIntegrationTest do
  use Cadence.ConfigCase, async: false

  @moduletag :integration

  import CadenceSimulator.ContactSchedulingFixtures

  alias Cadence.Contacts.ProviderBooking
  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Dev.Seed.DeliveryTLS, as: SeedEnrollment
  alias Cadence.GroundNetworks
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.IngressJournal.FileSystem, as: Journal
  alias Cadence.Management.Transports
  alias Cadence.ProviderAdapters.TCPSocket
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Secrets.DevelopmentDeliveryTLS
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow
  alias CadenceSimulator.Provider

  alias CadenceSimulator.Provider.{
    DeliveryProfiles,
    DeliveryTLSFileBackend,
    Orchestrator,
    Router,
    Store
  }

  Code.require_file("../../../../dev/seed/delivery_tls.exs", __DIR__)

  @definitions Path.expand("../../../../dev/catalogs/demo_spacecraft.yaml", __DIR__)

  @tag :runtime
  @tag timeout: 60_000
  test "a simulator delivery with the right SCID and the wrong organization is refused before capture" do
    directory = Path.join(System.tmp_dir!(), Cadence.Ids.new("delivery_tls_test"))
    on_exit(fn -> File.rm_rf!(directory) end)
    context = start_provider!(directory)
    scenario = create_scenario!()
    {:ok, run_a} = Provider.create_run(scenario["id"], %{"seed" => 23})
    {:ok, run_b} = Provider.create_run(scenario["id"], %{"seed" => 23})

    a = provision_binding!(context, run_a, free_port())
    b = provision_binding!(context, run_b, free_port())
    assert a.organization_id != b.organization_id
    assert a.endpoint.scid == b.endpoint.scid and a.endpoint.scid == 0
    assert [_ | _] = addresses = a.delivery_profile.egress["source_addresses"]
    assert b.delivery_profile.egress["source_addresses"] == addresses

    a_ref = a.delivery_profile.egress["delivery_credential_ref"]
    request = mtls_request(b.transport.configuration["port"], "out-of-scope", a_ref)

    assert {:error, {:invalid, "delivery credential is unavailable in this provider run"}} =
             DeliveryProfiles.provision(run_b, request)

    now = DateTime.utc_now()
    first_a = book!(a, DateTime.add(now, 120))
    _runtime = start_cadence!(first_a)
    advance_simulator!(first_a.starts_at)
    assert_eventually(fn -> sample_count(a) > 0 and raw_count(a) > 0 end)
    end_contact!(first_a)

    a_pass = book!(a, DateTime.add(first_a.ends_at, 30))
    b_pass = book!(b, DateTime.add(first_a.ends_at, 30))
    assert a_pass.starts_at == b_pass.starts_at
    assert a_pass.ends_at == b_pass.ends_at

    start_cadence!(a_pass)
    b_runtime = start_cadence!(b_pass)
    {:ok, _paused} = Provider.transition_run(run_b["id"], "pause")

    # The simulator sends A's booked stream to the wrong port. Its run, key and pinned profile
    # identity remain A's, and the same server certificate verifies on both loopback ports.
    change_destination!(a_pass.provider_contact_id, b.transport.configuration["port"])
    advance_simulator!(a_pass.starts_at)

    assert_eventually(fn ->
      {:ok, contact} = Store.fetch(:contact, a_pass.provider_contact_id)

      contact["status"] == "active" and contact["delivery"]["status"] == "failed" and
        contact["delivery"]["reason"] == "delivery_tls_handshake_failed"
    end)

    assert_eventually(fn ->
      match?(
        {:ok, %{connected?: false, refusals: %{last: %{reason: "unknown_leaf"}}}},
        TCPSocket.refusals(b_runtime.adapter)
      )
    end)

    assert {:ok, %{next_offset: 0, appended_entries: 0}} = Journal.snapshot(b_runtime.journal)
    assert raw_count(b) == 0
    assert sample_count(b) == 0

    {:ok, resumed} = Provider.transition_run(run_b["id"], "resume")
    advance_simulator!(DateTime.add(b_pass.starts_at, resumed["paused_duration_seconds"]))

    assert_eventually(fn -> sample_count(b) > 0 and raw_count(b) > 0 end)
    assert {:ok, %{appended_bytes: bytes}} = Journal.snapshot(b_runtime.journal)
    assert bytes > 0
  end

  defp start_provider!(directory) do
    :ok = Store.clear()
    :ok = DevelopmentDeliveryTLS.ensure!(directory)
    backend = {DevelopmentDeliveryTLS, :resolve}
    common = [secret_backend: backend, development_directory: directory]

    configure(:cadence, :provider_delivery_listener, [secret_reference: "listener"] ++ common)
    configure(:cadence, :provider_delivery_issuer, [issuer_reference: "issuer"] ++ common)

    configure(
      :cadence_simulator,
      :delivery_tls_backend,
      {DeliveryTLSFileBackend, :resolve, [Path.join(directory, "provider")]}
    )

    configure(:cadence_simulator, :provider_api_token, "provider-secret")
    http_port = free_port()
    start_supervised!({Bandit, plug: Router, scheme: :http, ip: {127, 0, 0, 1}, port: http_port})

    %{base_url: "http://127.0.0.1:#{http_port}", directory: directory}
  end

  defp configure(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, original} -> Application.put_env(app, key, original)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  defp create_scenario! do
    {:ok, scenario} =
      Provider.create_scenario(%{
        "name" => "Cross-organization delivery TLS proof",
        "spacecraft_count" => 1,
        "spacecraft_prefix" => "SC",
        "provider_behavior" => %{"confirmation" => "immediate"},
        "pass_model" => %{
          "cadence_seconds" => 30,
          "duration_seconds" => 15,
          "jitter_seconds" => 0
        },
        "telemetry_profile" => %{"definitions_path" => @definitions, "rate_hz" => 5.0}
      })

    scenario
  end

  defp provision_binding!(context, run, port) do
    setup = context |> persist_provider_setup(run) |> provision_provider_transport(port)

    ref =
      SeedEnrollment.enroll!(
        admin_scope(setup),
        setup.mission_id,
        setup.provider.provider_id,
        setup.transport.transport_id,
        run["id"],
        context.directory
      )

    {:ok, delivery} =
      SimulatorHTTP.provision_delivery_profile(
        setup.provider_context,
        mtls_request(port, "tls-#{setup.suffix}", ref),
        credential_resolver: &resolve_provider_credential/1
      )

    {:ok, provider} =
      GroundNetworks.sync_provider(
        setup.organization_id,
        setup.mission_id,
        setup.provider.provider_id,
        credential_resolver: &resolve_provider_credential/1
      )

    {:ok, transport} =
      Transports.version_transport(
        setup.organization_id,
        setup.mission_id,
        setup.transport.transport_id,
        %{
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          delivery_profile_ref: %{"id" => delivery.id, "version" => delivery.version}
        }
      )

    assert transport.configuration["delivery_auth"] == "mtls"

    %{setup | provider: provider, transport: transport, delivery_profile: delivery}
    |> persist_spacecraft_routing(telemetry?: true)
  end

  defp mtls_request(port, client_ref, credential_ref) do
    port
    |> delivery_profile_request(client_ref)
    |> Map.put("delivery_auth", "mtls")
    |> Map.put("egress", %{"delivery_credential_ref" => credential_ref})
  end

  defp book!(setup, start_after) do
    {:ok, %{opportunities: [opportunity | _]}} =
      ProviderScheduling.search_opportunities(
        setup.organization_id,
        setup.mission_id,
        setup.route.route_key,
        %{
          "spacecraft_id" => setup.spacecraft.spacecraft_id,
          "starts_at" => DateTime.to_iso8601(start_after),
          "ends_at" => DateTime.to_iso8601(DateTime.add(start_after, 120))
        },
        credential_resolver: &resolve_provider_credential/1
      )

    {:ok, booking} =
      ProviderBooking.reserve(
        setup.organization_id,
        setup.mission_id,
        setup.provider.provider_id,
        booking_attrs(setup, opportunity, Cadence.Ids.new("tls")),
        credential_resolver: &resolve_provider_credential/1
      )

    :ok = Orchestrator.reconcile(DateTime.utc_now())
    {:ok, reservation} = reconcile_reservation(booking.provider_reservation)

    {:ok, scheduled} =
      Cadence.Contacts.fetch_scheduled_contact(
        setup.organization_id,
        setup.mission_id,
        reservation.scheduled_contact_id
      )

    %{
      setup: setup,
      provider_contact_id: reservation.provider_contact_ref,
      scheduled_id: scheduled.scheduled_contact_id,
      starts_at: scheduled.starts_at,
      ends_at: scheduled.ends_at
    }
  end

  defp start_cadence!(pass) do
    mission = pass.setup.mission_id
    {:ok, _summary} = Cadence.Contacts.reconcile(mission, pass.starts_at)
    id = pass.scheduled_id <> "_run"

    {:ok, realized} =
      Cadence.Contacts.fetch_realized_contact(pass.setup.organization_id, mission, id)

    [path] = realized.paths
    [binding] = path.provider_bindings
    assert binding.configuration["delivery_auth"] == "mtls"

    %{
      adapter:
        MissionRuntime.provider_runtime_name(
          mission,
          id,
          path.path_id,
          binding.provider_binding_id
        ),
      journal:
        MissionRuntime.provider_ingress_journal_name(
          mission,
          id,
          path.path_id,
          binding.provider_binding_id
        )
    }
  end

  defp advance_simulator!(starts_at) do
    :ok = Orchestrator.reconcile(DateTime.add(starts_at, -2))
    :ok = Orchestrator.reconcile(starts_at)
  end

  defp end_contact!(pass) do
    ends_after = DateTime.add(pass.ends_at, 1)
    :ok = Orchestrator.reconcile(ends_after)

    assert :ok =
             Cadence.Runtime.stop_realized_contact_sync(
               pass.setup.mission_id,
               pass.scheduled_id <> "_run"
             )
  end

  defp change_destination!(contact_id, port) do
    {:ok, contact} = Store.fetch(:contact, contact_id)

    {:ok, _updated} =
      Store.put(:contact, put_in(contact, ["delivery_profile_snapshot", "target", "port"], port))
  end

  defp sample_count(setup),
    do: count_for_mission(TelemetrySampleRow, :sample_id, setup.mission_id)

  defp raw_count(setup), do: count_for_mission(RawEvidenceRow, :evidence_id, setup.mission_id)
end
