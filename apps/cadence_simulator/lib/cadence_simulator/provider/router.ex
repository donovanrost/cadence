defmodule CadenceSimulator.Provider.Router do
  @moduledoc "HTTP boundary for the canonical ground-station provider API."

  use Plug.Router

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{AdminRouter, ApiRouter, Auth}
  alias CadenceSimulator.Provider.Store

  plug(Plug.RequestId)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:authenticate)
  plug(:dispatch)

  forward("/admin", to: AdminRouter)
  forward("/provider", to: ApiRouter)

  get "/health" do
    json(conn, 200, %{"status" => "ok", "service" => "cadence-ground-network-simulator"})
  end

  post "/v1/scenarios" do
    respond(conn, Provider.create_scenario(conn.body_params), status: 201)
  end

  get "/v1/scenarios" do
    json(conn, 200, %{"data" => Provider.list_scenarios()})
  end

  get "/v1/scenarios/:id" do
    respond(conn, Provider.fetch_scenario(id))
  end

  post "/v1/scenarios/:id/runs" do
    respond(conn, Provider.create_run(id, conn.body_params), status: 201)
  end

  get "/v1/runs" do
    json(conn, 200, %{"data" => Provider.list_runs()})
  end

  get "/v1/runs/:id" do
    respond(conn, Provider.fetch_run(id))
  end

  post "/v1/runs/:id/pause" do
    respond(conn, Provider.transition_run(id, "pause"))
  end

  post "/v1/runs/:id/resume" do
    respond(conn, Provider.transition_run(id, "resume"))
  end

  post "/v1/runs/:id/stop" do
    respond(conn, Provider.transition_run(id, "stop"))
  end

  get "/v1/ground-stations" do
    respond_data(conn, Provider.ground_stations(conn.params["run_id"]))
  end

  get "/v1/spacecraft" do
    respond_data(conn, Provider.spacecraft(conn.params["run_id"]))
  end

  post "/v1/contact-opportunities/search" do
    respond(conn, Provider.search_opportunities(conn.body_params))
  end

  post "/v1/contact-reservations" do
    idempotency_key = get_req_header(conn, "idempotency-key") |> List.first()
    respond(conn, Provider.reserve_contact(conn.body_params, idempotency_key), status: 201)
  end

  get "/v1/contact-reservations" do
    json(conn, 200, %{"data" => Provider.list_reservations(conn.params)})
  end

  get "/v1/contact-reservations/:id" do
    respond(conn, Provider.fetch_reservation(id))
  end

  post "/v1/contact-reservations/:id/cancel" do
    respond(conn, Provider.cancel_reservation(id))
  end

  get "/v1/events" do
    cursor = parse_integer(conn.params["cursor"], 0)
    limit = parse_integer(conn.params["limit"], 100)
    result = Store.events(max(cursor, 0), max(limit, 1))
    json(conn, 200, %{"data" => result.data, "next_cursor" => result.next_cursor})
  end

  match _ do
    error(conn, 404, "not_found", "resource not found")
  end

  defp authenticate(conn, _opts) do
    if conn.request_path == "/health" or
         String.starts_with?(conn.request_path, ["/admin/", "/provider/"]) do
      conn
    else
      authenticate_legacy(conn)
    end
  end

  defp authenticate_legacy(conn) do
    expected_token =
      Application.get_env(
        :cadence_simulator,
        :legacy_provider_api_token,
        Application.get_env(:cadence_simulator, :provider_api_token)
      )

    if Auth.authorized?(conn, expected_token) do
      conn
    else
      conn
      |> error(401, "unauthorized", "a valid bearer token is required")
      |> halt()
    end
  end

  defp respond(conn, result, opts \\ [])

  defp respond(conn, {:ok, resource}, opts) do
    status = Keyword.get(opts, :status, 200)
    body = if Keyword.get(opts, :raw?, false), do: resource, else: %{"data" => resource}
    json(conn, status, body)
  end

  defp respond(conn, {:error, :not_found}, _opts),
    do: error(conn, 404, "not_found", "resource not found")

  defp respond(conn, {:error, {:invalid, detail}}, _opts),
    do: error(conn, 422, "invalid_request", detail)

  defp respond(conn, {:error, {:conflict, detail}}, _opts),
    do: error(conn, 409, "conflict", detail)

  defp respond(conn, {:error, reason}, _opts),
    do: error(conn, 500, "provider_error", inspect(reason))

  defp respond_data(conn, {:ok, data}), do: json(conn, 200, %{"data" => data})
  defp respond_data(conn, error_result), do: respond(conn, error_result)

  defp error(conn, status, code, detail) do
    json(conn, status, %{
      "error" => %{
        "code" => code,
        "detail" => detail,
        "correlation_id" => List.first(get_resp_header(conn, "x-request-id"))
      }
    })
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end
end
