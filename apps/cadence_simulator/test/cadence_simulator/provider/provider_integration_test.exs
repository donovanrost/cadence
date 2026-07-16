defmodule CadenceSimulator.Provider.ProviderIntegrationTest do
  use CadenceSimulator.Case, async: false

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.GroundNetworks.{ProviderContact, ProviderContext, ProviderError}
  alias CadenceSimulator.Provider.{Contacts, Router, Store}
  alias CadenceSimulator.TestProviderFixtures

  @config_keys [:provider_admin_api_token, :provider_api_token]

  setup do
    :ok = Store.clear()
    previous = Map.new(@config_keys, &{&1, Application.get_env(:cadence_simulator, &1)})
    Application.put_env(:cadence_simulator, :provider_admin_api_token, "admin-secret")
    Application.put_env(:cadence_simulator, :provider_api_token, "provider-secret")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:cadence_simulator, key)
        {key, value} -> Application.put_env(:cadence_simulator, key, value)
      end)
    end)

    port = free_port()
    start_supervised!({Bandit, plug: Router, scheme: :http, ip: {127, 0, 0, 1}, port: port})
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

  @tag timeout: 30_000
  test "a modification response lost after commit recovers idempotently", context do
    fixture =
      TestProviderFixtures.create_contact!(%{
        "fault_profile" => %{
          "contact_modification_response_loss_after_commit_count" => 1
        }
      })

    provider_context = provider_context(context.base_url, fixture.run["id"])

    attrs = %{
      "client_reference" => "lost-modification-response",
      "expected_revision" => 1,
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

    assert {:ok, %ProviderContact{provider_revision: 2} = recovered} =
             SimulatorHTTP.modify_contact(provider_context, fixture.contact["id"], attrs,
               idempotency_key: "lost-modification-key",
               credential_resolver: &resolve_credential/1
             )

    assert recovered.starts_at |> DateTime.to_iso8601() == attrs["starts_at"]
    assert {:ok, internal} = Contacts.fetch_internal(fixture.contact["id"])
    assert internal["revision"] == 2
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
end
