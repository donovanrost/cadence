defmodule CadenceSimulator.Provider.ProviderIntegrationTest do
  use CadenceSimulator.Case, async: false

  @moduletag :integration

  @moduletag :config

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.GroundNetworks.{ProviderContact, ProviderContext, ProviderError}
  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Contacts, FleetScenarios, Router, Store}
  alias CadenceSimulator.TestProviderFixtures

  @router_options [
    provider_auth: [
      provider_admin_api_token: "admin-secret",
      provider_api_token: "provider-secret"
    ]
  ]

  setup do
    :ok = Store.clear()

    port = free_port()

    start_supervised!(
      {Bandit, plug: {Router, @router_options}, scheme: :http, ip: {127, 0, 0, 1}, port: port}
    )

    %{base_url: "http://127.0.0.1:#{port}"}
  end

  test "admin controls change run faults and initiate provider Contact changes", context do
    fixture = TestProviderFixtures.create_contact!()

    fault_response =
      Req.patch!("#{context.base_url}/admin/v1/runs/#{fixture.run["id"]}/fault-profile",
        auth: {:bearer, "admin-secret"},
        json: %{"event_duplication_count" => 2}
      )

    assert fault_response.status == 200

    assert get_in(fault_response.body, [
             "data",
             "scenario_snapshot",
             "fault_profile",
             "event_duplication_count"
           ]) ==
             2

    change_response =
      Req.post!(
        "#{context.base_url}/admin/v1/runs/#{fixture.run["id"]}/contacts/#{fixture.contact["id"]}/changes",
        auth: {:bearer, "admin-secret"},
        headers: [{"x-request-id", "admin-change-request"}],
        json: %{
          "type" => "station_substitution",
          "ground_station_ref" => "station-hawaii",
          "antenna_or_service_pool_ref" => "station-hawaii-antenna-1"
        }
      )

    assert change_response.status == 200
    assert get_in(change_response.body, ["data", "ground_station_ref"]) == "station-hawaii"
    refute inspect(change_response.body) =~ "provider-secret"
  end

  test "opportunity search exposes provider-owned orbit readiness and fails explicitly when expired",
       context do
    {:ok, current_scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 1,
        "pass_model" => %{
          "cadence_seconds" => 30,
          "duration_seconds" => 15,
          "jitter_seconds" => 0
        },
        "orbit_readiness" => %{
          "status" => "current",
          "ephemeris_ref" => "synthetic-oem-current",
          "version" => 4
        }
      })

    {:ok, current_run} = Provider.create_run(current_scenario["id"], %{"seed" => 2_026})
    current_context = provider_context(context.base_url, current_run["id"])
    starts_at = DateTime.utc_now() |> DateTime.add(30, :second) |> DateTime.truncate(:second)

    params = %{
      "spacecraft_refs" => ["SC-001"],
      "ground_station_refs" => [],
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(180, :second) |> DateTime.to_iso8601(),
      "page_size" => 10,
      "cursor" => nil
    }

    assert {:ok, current_page} =
             SimulatorHTTP.search_opportunities(current_context, params,
               credential_resolver: &resolve_credential/1
             )

    assert get_in(current_page, [:provider_evidence, "orbit_readiness", "status"]) ==
             "current"

    assert get_in(current_page, [
             :provider_evidence,
             "orbit_readiness",
             "ephemeris_ref"
           ]) == "synthetic-oem-current"

    assert Enum.all?(current_page.data, fn opportunity ->
             opportunity.extensions["orbit_readiness"]["version"] == 4
           end)

    {:ok, expired_scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 1,
        "orbit_readiness" => %{
          "status" => "expired",
          "ephemeris_ref" => "synthetic-oem-expired"
        }
      })

    {:ok, expired_run} = Provider.create_run(expired_scenario["id"], %{"seed" => 2_027})
    expired_context = provider_context(context.base_url, expired_run["id"])

    assert {:error, %ProviderError{category: :provider_not_ready} = error} =
             SimulatorHTTP.search_opportunities(expired_context, params,
               credential_resolver: &resolve_credential/1
             )

    assert get_in(error.evidence, ["error", "evidence", "orbit_readiness", "status"]) ==
             "expired"

    assert get_in(error.evidence, [
             "error",
             "evidence",
             "orbit_readiness",
             "ephemeris_ref"
           ]) == "synthetic-oem-expired"
  end

  test "fleet route profiles expose bounded latency, rate limits, shared pools, and empty success",
       context do
    {:ok, scenario} =
      FleetScenarios.stage_five(spacecraft_count: 300)
      |> Provider.create_scenario()

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 2_030})
    provider_context = provider_context(context.base_url, run["id"])
    starts_at = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.truncate(:second)

    params = %{
      "spacecraft_refs" => ["SC-001", "SC-002"],
      "ground_station_refs" => ["station-svalbard"],
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(3_600, :second) |> DateTime.to_iso8601(),
      "page_size" => 50,
      "cursor" => nil
    }

    started_at = System.monotonic_time(:millisecond)

    assert {:error,
            %ProviderError{
              category: :rate_limited,
              retryable: true,
              retry_after_seconds: 1
            } = rate_limit_error} =
             SimulatorHTTP.search_opportunities(provider_context, params,
               credential_resolver: &resolve_credential/1
             )

    assert System.monotonic_time(:millisecond) - started_at >= 10

    assert get_in(rate_limit_error.evidence, [
             "error",
             "evidence",
             "route_profile_ref"
           ]) == "route-svalbard-shared"

    assert {:ok, page} =
             SimulatorHTTP.search_opportunities(provider_context, params,
               credential_resolver: &resolve_credential/1
             )

    assert page.data != []

    assert Enum.all?(page.data, fn opportunity ->
             opportunity.antenna_or_service_pool_ref == "pool-svalbard-realtime" and
               opportunity.extensions["route_profile_ref"] == "route-svalbard-shared" and
               DateTime.before?(opportunity.expires_at, opportunity.starts_at)
           end)

    empty_params = Map.put(params, "spacecraft_refs", ["SC-DOES-NOT-EXIST"])

    assert {:ok, %{data: [], truncated: false}} =
             SimulatorHTTP.search_opportunities(provider_context, empty_params,
               credential_resolver: &resolve_credential/1
             )
  end

  test "missing and processing orbit states remain distinct provider-not-ready evidence",
       context do
    starts_at = DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)

    params = %{
      "spacecraft_refs" => ["SC-001"],
      "ground_station_refs" => [],
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(600, :second) |> DateTime.to_iso8601(),
      "page_size" => 10,
      "cursor" => nil
    }

    for {status, ephemeris_ref} <- [
          {"missing", nil},
          {"processing", "synthetic-oem-processing"}
        ] do
      {:ok, scenario} =
        Provider.create_scenario(%{
          "spacecraft_count" => 1,
          "orbit_readiness" => %{
            "status" => status,
            "ephemeris_ref" => ephemeris_ref || "ignored-when-missing"
          }
        })

      {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 2_031})

      assert {:error, %ProviderError{category: :provider_not_ready} = error} =
               SimulatorHTTP.search_opportunities(
                 provider_context(context.base_url, run["id"]),
                 params,
                 credential_resolver: &resolve_credential/1
               )

      assert get_in(error.evidence, ["error", "evidence", "orbit_readiness", "status"]) ==
               status

      assert get_in(error.evidence, [
               "error",
               "evidence",
               "orbit_readiness",
               "ephemeris_ref"
             ]) == ephemeris_ref
    end
  end

  @tag timeout: 30_000
  test "a modification response lost after commit recovers idempotently", context do
    fixture =
      TestProviderFixtures.create_contact!(
        %{
          "fault_profile" => %{
            "contact_modification_response_loss_after_commit_count" => 1
          }
        },
        search_starts_at: DateTime.utc_now() |> DateTime.add(600) |> DateTime.truncate(:second)
      )

    provider_context = provider_context(context.base_url, fixture.run["id"])

    assert_eventually(fn ->
      case Contacts.fetch_internal(fixture.contact["id"]) do
        {:ok, %{"status" => "confirmed"}} -> true
        _other -> false
      end
    end)

    assert {:ok, %{"state" => "paused"}} =
             Provider.transition_run(fixture.run["id"], "pause")

    {:ok, current_contact} = Contacts.fetch_internal(fixture.contact["id"])

    attrs = %{
      "client_reference" => "lost-modification-response",
      "expected_revision" => current_contact["revision"],
      "starts_at" => shift_time(fixture.contact["starts_at"], 90),
      "ends_at" => shift_time(fixture.contact["ends_at"], 90),
      "reason" => "operator_requested"
    }

    first =
      SimulatorHTTP.modify_contact(provider_context, fixture.contact["id"], attrs,
        idempotency_key: "lost-modification-key",
        credential_resolver: &resolve_credential/1
      )

    assert {:error, %ProviderError{category: :ambiguous_outcome}} = first

    assert {:ok, %ProviderContact{provider_revision: provider_revision} = recovered} =
             SimulatorHTTP.modify_contact(provider_context, fixture.contact["id"], attrs,
               idempotency_key: "lost-modification-key",
               credential_resolver: &resolve_credential/1
             )

    assert provider_revision == current_contact["revision"] + 1
    assert recovered.starts_at |> DateTime.to_iso8601() == attrs["starts_at"]
    assert {:ok, internal} = Contacts.fetch_internal(fixture.contact["id"])
    assert internal["revision"] == provider_revision
    assert length(internal["modification_history"]) == 1
  end

  defp provider_context(base_url, environment_ref) do
    {:ok, context} =
      ProviderContext.new(%{
        provider_ref: "simulator-integration",
        organization_id: "organization-integration",
        mission_id: "mission-integration",
        client_key: "simulator_http",
        base_url: base_url,
        credential_ref: "test-provider-token",
        environment_ref: environment_ref
      })

    context
  end

  defp resolve_credential("test-provider-token"), do: {:ok, "provider-secret"}

  defp shift_time(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(fun, 0), do: assert(fun.())
end
