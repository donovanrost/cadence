defmodule CadenceSimulator.Provider.ApiRouterTest do
  use CadenceSimulator.Case, async: false

  @moduletag :config

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Router, Store}
  alias Plug.Conn
  alias Plug.Test

  @config_keys [:provider_admin_api_token, :provider_api_token]

  setup do
    :ok = Store.clear()
    previous = Map.new(@config_keys, &{&1, Application.get_env(:cadence_simulator, &1)})

    Application.put_env(:cadence_simulator, :provider_admin_api_token, "admin-secret")
    Application.put_env(:cadence_simulator, :provider_api_token, "provider-secret")

    on_exit(fn -> restore_config(previous) end)

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 2,
        "provider_behavior" => %{
          "idempotency" => "client_reference",
          "event_delivery_semantics" => "best_effort",
          "page_size_limit" => 25
        },
        "delivery_profiles" => [
          %{
            "id" => "delivery-cadence-primary",
            "display_name" => "Cadence primary telemetry ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-realtime-ttc-downlink"],
            "operator_summary" => "Streaming to Cadence",
            "diagnostics" => %{
              "protocol" => "tcp",
              "endpoint_health" => "healthy",
              "api_token" => "must-not-leak"
            }
          }
        ]
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 42})
    %{environment_ref: run["provider_environment_ref"]}
  end

  test "provider account and capability discovery are environment scoped", context do
    account = request("/provider/v1/account", "provider-secret", context.environment_ref)
    assert account.status == 200

    assert %{
             "data" => %{
               "provider_environment_ref" => environment_ref,
               "simulated" => true
             }
           } = Jason.decode!(account.resp_body)

    assert environment_ref == context.environment_ref

    capabilities =
      request("/provider/v1/capabilities", "provider-secret", context.environment_ref)

    assert %{
             "data" => %{
               "reservation" => %{"idempotency" => "client_reference"},
               "events" => %{"delivery_semantics" => "best_effort"},
               "search" => %{"page_size_limit" => 25}
             },
             "meta" => %{"contract_version" => "1.0"}
           } = Jason.decode!(capabilities.resp_body)
  end

  test "provider inventory and profiles use list envelopes", context do
    spacecraft = request("/provider/v1/spacecraft", "provider-secret", context.environment_ref)

    assert %{"data" => spacecraft_data, "meta" => %{"truncated" => false}} =
             Jason.decode!(spacecraft.resp_body)

    assert length(spacecraft_data) == 2

    services =
      request("/provider/v1/service-profiles", "provider-secret", context.environment_ref)

    assert %{"data" => [%{"id" => "service-realtime-ttc-downlink"}]} =
             Jason.decode!(services.resp_body)

    deliveries =
      request("/provider/v1/delivery-profiles", "provider-secret", context.environment_ref)

    assert %{
             "data" => [
               %{
                 "id" => "delivery-cadence-primary",
                 "operator_summary" => "Streaming to Cadence",
                 "diagnostics" => diagnostics
               }
             ]
           } = Jason.decode!(deliveries.resp_body)

    refute Map.has_key?(diagnostics, "api_token")
  end

  test "provider API requires its credential and an existing environment", context do
    assert request("/provider/v1/account", "admin-secret", context.environment_ref).status == 401

    missing_environment = request("/provider/v1/account", "provider-secret", nil)
    assert missing_environment.status == 422

    assert %{"error" => %{"code" => "invalid_request"}} =
             Jason.decode!(missing_environment.resp_body)

    assert request("/provider/v1/account", "provider-secret", "missing-run").status == 404
  end

  defp request(path, token, environment_ref) do
    conn =
      :get
      |> Test.conn(path)
      |> Conn.put_req_header("authorization", "Bearer #{token}")

    conn =
      if environment_ref do
        Conn.put_req_header(conn, "x-simulator-environment-ref", environment_ref)
      else
        conn
      end

    Router.call(conn, [])
  end

  defp restore_config(previous) do
    Enum.each(previous, fn
      {key, nil} -> Application.delete_env(:cadence_simulator, key)
      {key, value} -> Application.put_env(:cadence_simulator, key, value)
    end)
  end
end
