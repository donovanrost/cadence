defmodule CadenceSimulator.Provider.ContractTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.Provider.{
    Auth,
    Capabilities,
    Contract,
    DeliveryProfiles,
    ServiceProfiles
  }

  alias Plug.Conn
  alias Plug.Test

  @fixture_dir Path.expand("../../fixtures/provider_contract/v1", __DIR__)

  test "success and error envelopes carry contract and request metadata" do
    success_conn =
      :get
      |> Test.conn("/")
      |> Conn.put_resp_header("x-request-id", "request-success")
      |> Contract.success(200, %{"status" => "ready"})

    assert %{
             "data" => %{"status" => "ready"},
             "meta" => %{
               "contract_version" => "1.0",
               "request_id" => "request-success"
             }
           } = Jason.decode!(success_conn.resp_body)

    error_conn =
      :get
      |> Test.conn("/")
      |> Conn.put_resp_header("x-request-id", "request-error")
      |> Contract.error(429, "rate_limited", "slow down",
        retryable: true,
        retry_after_seconds: 2
      )

    assert %{
             "error" => %{
               "code" => "rate_limited",
               "retryable" => true,
               "retry_after_seconds" => 2
             },
             "meta" => %{"request_id" => "request-error"}
           } = Jason.decode!(error_conn.resp_body)
  end

  test "sanitizes nested credentials from provider evidence" do
    assert %{
             "diagnostics" => %{"host" => "cadence.internal"},
             "items" => [%{"status" => "ready", "credential_ref" => "env://TOKEN"}]
           } =
             Contract.sanitize(%{
               diagnostics: %{host: "cadence.internal", api_token: "secret"},
               password: "secret",
               items: [%{status: :ready, credential_ref: "env://TOKEN"}]
             })
  end

  test "checked-in contract fixtures are valid string-keyed JSON" do
    for filename <- [
          "capabilities.json",
          "service_profile.json",
          "delivery_profile.json",
          "opportunity_page.json",
          "contact_pending.json",
          "contact_confirmed.json",
          "contact_active.json",
          "contact_completed.json",
          "contact_result.json",
          "event_page.json",
          "error.json"
        ] do
      document = @fixture_dir |> Path.join(filename) |> File.read!() |> Jason.decode!()
      assert is_map(document)
      assert Enum.all?(Map.keys(document), &is_binary/1)
    end
  end

  test "checked-in discovery fixtures match the normalized provider contract" do
    capabilities = fixture("capabilities.json")
    service_profile = fixture("service_profile.json")
    delivery_profile = fixture("delivery_profile.json")

    run = %{
      "scenario_snapshot" => %{"provider_behavior" => Capabilities.default_behavior()}
    }

    assert Capabilities.for_run(run) == capabilities
    assert {:ok, [^service_profile]} = ServiceProfiles.normalize([service_profile])
    assert {:ok, [^delivery_profile]} = DeliveryProfiles.normalize([delivery_profile])
  end

  test "Contact fixtures keep the three lifecycle dimensions explicit" do
    required_keys = [
      "id",
      "client_reference",
      "opportunity_ref",
      "spacecraft_ref",
      "ground_station_ref",
      "service_profile_ref",
      "delivery_profile_ref",
      "starts_at",
      "ends_at",
      "status",
      "pass_phase",
      "delivery",
      "tags",
      "extensions"
    ]

    for filename <- [
          "contact_pending.json",
          "contact_confirmed.json",
          "contact_active.json",
          "contact_completed.json"
        ] do
      contact = fixture(filename)
      assert Enum.all?(required_keys, &Map.has_key?(contact, &1))
      assert is_binary(contact["delivery"]["status"])
    end
  end

  test "production authentication validation requires both API credentials" do
    assert :ok = Auth.validate_configuration!(false, true, nil, nil)
    assert :ok = Auth.validate_configuration!(true, false, nil, nil)
    assert :ok = Auth.validate_configuration!(true, true, "admin", "provider")

    assert_raise ArgumentError, fn ->
      Auth.validate_configuration!(true, true, "admin", nil)
    end
  end

  defp fixture(filename) do
    @fixture_dir |> Path.join(filename) |> File.read!() |> Jason.decode!()
  end
end
