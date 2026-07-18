defmodule CadenceSimulator.Provider.ProviderContractV1Test do
  use CadenceSimulator.Case, async: false

  @moduletag :config

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Contacts, Orchestrator, Router, Store}
  alias Plug.Conn
  alias Plug.Test

  @config_keys [:provider_admin_api_token, :provider_api_token]
  @definitions Path.expand(
                 "../../../../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml",
                 __DIR__
               )

  setup do
    :ok = Store.clear()
    previous = Map.new(@config_keys, &{&1, Application.get_env(:cadence_simulator, &1)})
    Application.put_env(:cadence_simulator, :provider_admin_api_token, "admin-secret")
    Application.put_env(:cadence_simulator, :provider_api_token, "provider-secret")

    on_exit(fn -> restore_config(previous) end)

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 2,
        "provider_behavior" => %{"idempotency" => "native", "page_size_limit" => 25}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 42, "speed" => 100.0})

    delivery_request = %{
      "display_name" => "Cadence primary telemetry ingress",
      "client_reference" => "mission-primary-downlink",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "target" => %{
        "protocol" => "tcp",
        "mode" => "provider_connects",
        "host" => "127.0.0.1",
        "port" => 41_001,
        "api_token" => "must-not-leak"
      },
      "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115}
    }

    %{run: run, delivery_request: delivery_request}
  end

  test "Delivery Profile provisioning is idempotent, isolated, and sanitized", context do
    first =
      request(:post, "/provider/v1/delivery-profiles", context.run, context.delivery_request)

    assert first.status == 201

    assert %{
             "data" => %{
               "id" => profile_id,
               "state" => "ready",
               "diagnostics" => %{
                 "protocol" => "tcp",
                 "mode" => "provider_connects",
                 "frame_bytes" => 1115
               }
             }
           } = Jason.decode!(first.resp_body)

    refute first.resp_body =~ "must-not-leak"

    repeated =
      request(:post, "/provider/v1/delivery-profiles", context.run, context.delivery_request)

    assert %{"data" => %{"id" => ^profile_id}} = Jason.decode!(repeated.resp_body)

    conflict_request = put_in(context.delivery_request, ["target", "port"], 41_002)
    conflict = request(:post, "/provider/v1/delivery-profiles", context.run, conflict_request)
    assert conflict.status == 409
    assert %{"error" => %{"code" => "conflict"}} = Jason.decode!(conflict.resp_body)

    {:ok, other_run} = Provider.create_run(context.run["scenario_id"], %{"seed" => 99})
    assert request(:get, "/provider/v1/delivery-profiles/#{profile_id}", other_run).status == 404
  end

  test "profile-backed Contacts keep contact, pass, and delivery state independent", context do
    delivery_profile = provision_delivery(context)
    opportunity = search_opportunity(context.run)

    contact_request = %{
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "service_profile_ref" => opportunity["service_profile_ref"],
      "delivery_profile_ref" => delivery_profile["id"],
      "client_reference" => "cadence-contact-123",
      "tags" => %{"cadence_mission_ref" => "mission-123"}
    }

    created =
      request(:post, "/provider/v1/contacts", context.run, contact_request,
        "idempotency-key": "booking-123",
        "x-request-id": "request-contact-123"
      )

    assert created.status == 201

    assert %{
             "data" => %{
               "id" => contact_id,
               "status" => "pending",
               "pass_phase" => "scheduled",
               "delivery" => %{
                 "status" => "pending",
                 "endpoint_ref" => delivery_profile_id
               }
             }
           } = Jason.decode!(created.resp_body)

    assert delivery_profile_id == delivery_profile["id"]
    refute created.resp_body =~ "127.0.0.1"
    refute created.resp_body =~ "41001"

    repeated =
      request(:post, "/provider/v1/contacts", context.run, contact_request,
        "idempotency-key": "booking-123"
      )

    assert %{"data" => %{"id" => ^contact_id}} = Jason.decode!(repeated.resp_body)

    conflicting_request = Map.put(contact_request, "client_reference", "another-contact")

    conflict =
      request(:post, "/provider/v1/contacts", context.run, conflicting_request,
        "idempotency-key": "booking-123"
      )

    assert conflict.status == 409

    raw_transport_request =
      contact_request
      |> Map.put("client_reference", "raw-contact")
      |> Map.put("host", "operator-entered.example")

    invalid =
      request(:post, "/provider/v1/contacts", context.run, raw_transport_request,
        "idempotency-key": "booking-raw"
      )

    assert invalid.status == 422

    assert %{"data" => [%{"id" => ^contact_id}]} =
             request(
               :get,
               "/provider/v1/contacts?client_reference=cadence-contact-123",
               context.run
             )
             |> Map.fetch!(:resp_body)
             |> Jason.decode!()

    {:ok, starts_at, _offset} = DateTime.from_iso8601(opportunity["starts_at"])
    {:ok, ends_at, _offset} = DateTime.from_iso8601(opportunity["ends_at"])

    :ok = Orchestrator.reconcile(DateTime.add(starts_at, -5))
    assert_contact(context.run, contact_id, "confirmed", "scheduled", "pending")

    :ok = Orchestrator.reconcile(DateTime.add(starts_at, -2))
    assert_contact(context.run, contact_id, "confirmed", "prepass", "ready")

    :ok = Orchestrator.reconcile(starts_at)
    assert_contact(context.run, contact_id, "active", "pass", "failed")

    :ok = Orchestrator.reconcile(DateTime.add(ends_at, 1))
    assert_contact(context.run, contact_id, "completed", "closed", "failed")

    result = request(:get, "/provider/v1/contacts/#{contact_id}/result", context.run)
    assert result.status == 200

    assert %{
             "data" => %{
               "contact_ref" => ^contact_id,
               "outcome" => "completed",
               "bytes_delivered" => 0,
               "delivery_failure_reason" => delivery_failure_reason
             }
           } = Jason.decode!(result.resp_body)

    assert delivery_failure_reason =~ "data_plane_start_failed"

    events = request(:get, "/provider/v1/events?cursor=0&limit=100", context.run)

    assert %{"data" => event_data, "meta" => %{"next_cursor" => next_cursor}} =
             Jason.decode!(events.resp_body)

    assert is_binary(next_cursor)
    assert Enum.all?(event_data, &(&1["schema_version"] == "1.0"))

    assert Enum.any?(event_data, fn event ->
             event["type"] == "delivery.status_changed" and
               event["data"]["to"] == "failed"
           end)

    assert Enum.any?(event_data, &(&1["type"] == "contact.result_updated"))
  end

  test "client-reference environments recover Contacts without native idempotency", context do
    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 1,
        "provider_behavior" => %{"idempotency" => "client_reference"}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 77, "speed" => 100.0})

    delivery_context = %{
      run: run,
      delivery_request:
        Map.put(context.delivery_request, "client_reference", "client-mode-downlink")
    }

    delivery_profile = provision_delivery(delivery_context)
    opportunity = search_opportunity(run)

    contact_request = %{
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "service_profile_ref" => opportunity["service_profile_ref"],
      "delivery_profile_ref" => delivery_profile["id"],
      "client_reference" => "recoverable-contact",
      "tags" => %{}
    }

    first = request(:post, "/provider/v1/contacts", run, contact_request)
    repeated = request(:post, "/provider/v1/contacts", run, contact_request)

    assert %{"data" => %{"id" => contact_id}} = Jason.decode!(first.resp_body)
    assert %{"data" => %{"id" => ^contact_id}} = Jason.decode!(repeated.resp_body)

    conflicting = Map.put(contact_request, "tags", %{"changed" => true})
    assert request(:post, "/provider/v1/contacts", run, conflicting).status == 409
  end

  test "Contact modification is revision aware and idempotent", context do
    delivery_profile = provision_delivery(context)
    opportunity = search_opportunity(context.run)

    contact_request = %{
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "service_profile_ref" => opportunity["service_profile_ref"],
      "delivery_profile_ref" => delivery_profile["id"],
      "client_reference" => "modifiable-contact",
      "tags" => %{}
    }

    created =
      request(:post, "/provider/v1/contacts", context.run, contact_request,
        "idempotency-key": "modifiable-booking"
      )

    assert %{"data" => %{"id" => contact_id, "revision" => 1}} =
             Jason.decode!(created.resp_body)

    starts_at = shift_time(opportunity["starts_at"], 60)
    ends_at = shift_time(opportunity["ends_at"], 60)

    modification = %{
      "client_reference" => "change-contact-1",
      "expected_revision" => 1,
      "starts_at" => starts_at,
      "ends_at" => ends_at,
      "reason" => "operator_requested"
    }

    modified =
      request(:patch, "/provider/v1/contacts/#{contact_id}", context.run, modification,
        "idempotency-key": "contact-change-1",
        "x-request-id": "request-change-1"
      )

    assert modified.status == 200

    assert %{
             "data" => %{
               "revision" => 2,
               "starts_at" => ^starts_at,
               "ends_at" => ^ends_at
             }
           } = Jason.decode!(modified.resp_body)

    repeated =
      request(:patch, "/provider/v1/contacts/#{contact_id}", context.run, modification,
        "idempotency-key": "contact-change-1"
      )

    assert %{"data" => %{"revision" => repeated_revision}} = Jason.decode!(repeated.resp_body)
    assert repeated_revision >= 2

    assert {:ok, internal_contact} = Contacts.fetch_internal(contact_id)
    assert internal_contact["revision"] == repeated_revision
    assert length(internal_contact["modification_history"]) == 1

    conflicting = Map.put(modification, "ends_at", shift_time(ends_at, 60))

    assert request(
             :patch,
             "/provider/v1/contacts/#{contact_id}",
             context.run,
             conflicting,
             "idempotency-key": "contact-change-1"
           ).status == 409

    stale = Map.put(modification, "client_reference", "change-contact-stale")

    assert request(
             :patch,
             "/provider/v1/contacts/#{contact_id}",
             context.run,
             stale,
             "idempotency-key": "contact-change-stale"
           ).status == 409

    configuration_change =
      modification
      |> Map.put("client_reference", "change-contact-protocol")
      |> Map.put("expected_revision", 2)
      |> Map.put("protocol", "udp")

    assert request(
             :patch,
             "/provider/v1/contacts/#{contact_id}",
             context.run,
             configuration_change,
             "idempotency-key": "contact-change-protocol"
           ).status == 422

    events = request(:get, "/provider/v1/events?cursor=0&limit=100", context.run)
    %{"data" => event_data} = Jason.decode!(events.resp_body)

    assert Enum.any?(event_data, fn event ->
             event["type"] == "contact.modified" and event["resource_revision"] == 2 and
               event["client_reference"] == "modifiable-contact" and
               event["data"]["changed_fields"]["starts_at"] == %{
                 "before" => opportunity["starts_at"],
                 "after" => starts_at
               }
           end)
  end

  test "a profile-backed Contact streams telemetry and records delivery counters", context do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    acceptor =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 2_000)
        send(parent, {:provider_v1_telemetry, byte_size(bytes)})
        drain_socket(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(acceptor), do: Process.exit(acceptor, :normal)
    end)

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 1,
        "provider_behavior" => %{"idempotency" => "native"},
        "telemetry_profile" => %{"definitions_path" => @definitions, "rate_hz" => 50.0}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 101, "speed" => 100.0})

    delivery_request =
      context.delivery_request
      |> Map.put("client_reference", "streaming-proof-downlink")
      |> put_in(["target", "port"], port)

    delivery_profile = provision_delivery(%{run: run, delivery_request: delivery_request})
    opportunity = search_opportunity(run)

    contact_request = %{
      "opportunity_ref" => opportunity["id"],
      "spacecraft_ref" => opportunity["spacecraft_ref"],
      "service_profile_ref" => opportunity["service_profile_ref"],
      "delivery_profile_ref" => delivery_profile["id"],
      "client_reference" => "streaming-proof-contact",
      "tags" => %{}
    }

    response =
      request(:post, "/provider/v1/contacts", run, contact_request,
        "idempotency-key": "streaming-proof-booking"
      )

    %{"data" => %{"id" => contact_id}} = Jason.decode!(response.resp_body)
    {:ok, starts_at, _offset} = DateTime.from_iso8601(opportunity["starts_at"])
    {:ok, ends_at, _offset} = DateTime.from_iso8601(opportunity["ends_at"])

    :ok = Orchestrator.reconcile(DateTime.add(starts_at, -5))
    :ok = Orchestrator.reconcile(DateTime.add(starts_at, -2))
    :ok = Orchestrator.reconcile(starts_at)

    assert_receive {:provider_v1_telemetry, received_bytes}, 2_000
    assert received_bytes > 0

    Process.sleep(50)
    :ok = Orchestrator.reconcile(DateTime.add(starts_at, 1))
    assert_contact(run, contact_id, "active", "pass", "flowing")

    :ok = Orchestrator.reconcile(DateTime.add(ends_at, 1))
    result = request(:get, "/provider/v1/contacts/#{contact_id}/result", run)

    assert %{"data" => %{"frames_delivered" => frames_delivered}} =
             Jason.decode!(result.resp_body)

    assert frames_delivered > 0
  end

  defp provision_delivery(context) do
    response =
      request(:post, "/provider/v1/delivery-profiles", context.run, context.delivery_request)

    %{"data" => profile} = Jason.decode!(response.resp_body)
    profile
  end

  defp search_opportunity(run) do
    now = DateTime.utc_now()

    response =
      request(:post, "/provider/v1/opportunities/search", run, %{
        "spacecraft_refs" => ["SC-001"],
        "ground_station_refs" => [],
        "service_profile_ref" => "service-realtime-ttc-downlink",
        "starts_at" => now |> DateTime.add(5) |> DateTime.to_iso8601(),
        "ends_at" => now |> DateTime.add(7_200) |> DateTime.to_iso8601(),
        "page_size" => 2
      })

    assert response.status == 200
    %{"data" => [opportunity | _rest]} = Jason.decode!(response.resp_body)
    opportunity
  end

  defp assert_contact(run, contact_id, status, phase, delivery_status) do
    response = request(:get, "/provider/v1/contacts/#{contact_id}", run)

    assert %{
             "data" => %{
               "status" => ^status,
               "pass_phase" => ^phase,
               "delivery" => %{"status" => ^delivery_status}
             }
           } = Jason.decode!(response.resp_body)
  end

  defp request(method, path, run, body \\ nil, headers \\ [])

  defp request(method, path, run, body, headers) when is_map(run) do
    request(method, path, run["provider_environment_ref"], body, headers)
  end

  defp request(method, path, environment_ref, body, headers) do
    conn =
      if body do
        method
        |> Test.conn(path, Jason.encode!(body))
        |> Conn.put_req_header("content-type", "application/json")
      else
        Test.conn(method, path)
      end

    conn
    |> Conn.put_req_header("authorization", "Bearer provider-secret")
    |> Conn.put_req_header("x-simulator-environment-ref", environment_ref)
    |> put_headers(headers)
    |> Router.call([])
  end

  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, acc ->
      Conn.put_req_header(acc, to_string(key), value)
    end)
  end

  defp drain_socket(socket) do
    case :gen_tcp.recv(socket, 0, 500) do
      {:ok, _bytes} -> drain_socket(socket)
      {:error, _reason} -> :ok
    end
  end

  defp restore_config(previous) do
    Enum.each(previous, fn
      {key, nil} -> Application.delete_env(:cadence_simulator, key)
      {key, value} -> Application.put_env(:cadence_simulator, key, value)
    end)
  end

  defp shift_time(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end
end
