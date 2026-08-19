defmodule CadenceSimulator.Provider.AdminRouterTest do
  use CadenceSimulator.Case, async: false

  @moduletag :config

  alias CadenceSimulator.Provider.{Router, Store}
  alias Plug.Conn
  alias Plug.Test

  @router_options [
    provider_auth: [
      provider_admin_api_token: "admin-secret",
      provider_api_token: "provider-secret"
    ]
  ]

  setup do
    :ok = Store.clear()
    :ok
  end

  test "admin API owns scenarios and returns versioned envelopes" do
    create_conn =
      request(:post, "/admin/v1/scenarios", %{"name" => "Admin constellation"}, "admin-secret")

    assert create_conn.status == 201

    assert %{
             "data" => %{"name" => "Admin constellation"} = scenario,
             "meta" => %{"contract_version" => "1.0", "request_id" => request_id}
           } = Jason.decode!(create_conn.resp_body)

    assert is_binary(request_id)

    run_conn =
      request(
        :post,
        "/admin/v1/scenarios/#{scenario["id"]}/runs",
        %{"seed" => 2_026},
        "admin-secret"
      )

    assert run_conn.status == 201

    assert %{
             "data" => %{
               "id" => run_id,
               "provider_environment_ref" => run_id,
               "state" => "running"
             }
           } = Jason.decode!(run_conn.resp_body)

    assert request(:get, "/admin/v1/runs", nil, "admin-secret").status == 200
  end

  test "admin and provider credentials are not interchangeable" do
    conn = request(:get, "/admin/v1/scenarios", nil, "provider-secret")
    assert conn.status == 401

    assert %{
             "error" => %{"code" => "authentication_failed"},
             "meta" => %{"contract_version" => "1.0"}
           } = Jason.decode!(conn.resp_body)
  end

  test "legacy Stage 1 routes are not exposed" do
    assert request(:get, "/v1/scenarios", nil, "admin-secret").status == 404
    assert request(:get, "/v1/contact-opportunities/search", nil, "provider-secret").status == 404
  end

  test "empty router options retain the application-config compatibility boundary" do
    previous_token = Application.get_env(:cadence_simulator, :provider_admin_api_token)
    Application.put_env(:cadence_simulator, :provider_admin_api_token, "compatibility-secret")

    on_exit(fn ->
      restore_application_env(:provider_admin_api_token, previous_token)
    end)

    conn =
      :get
      |> Test.conn("/admin/v1/scenarios")
      |> Conn.put_req_header("authorization", "Bearer compatibility-secret")
      |> Router.call([])

    assert conn.status == 200
  end

  defp request(method, path, body, token) do
    conn =
      if is_map(body) do
        method
        |> Test.conn(path, Jason.encode!(body))
        |> Conn.put_req_header("content-type", "application/json")
      else
        Test.conn(method, path)
      end

    conn
    |> Conn.put_req_header("authorization", "Bearer #{token}")
    |> Router.call(@router_options)
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:cadence_simulator, key)

  defp restore_application_env(key, value),
    do: Application.put_env(:cadence_simulator, key, value)
end
