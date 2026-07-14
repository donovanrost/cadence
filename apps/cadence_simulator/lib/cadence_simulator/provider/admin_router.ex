defmodule CadenceSimulator.Provider.AdminRouter do
  @moduledoc false

  use Plug.Router

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Auth, Contract}

  plug(:match)
  plug(:authenticate)
  plug(:dispatch)

  post "/v1/scenarios" do
    respond(conn, Provider.create_scenario(conn.body_params), status: 201)
  end

  get "/v1/scenarios" do
    Contract.list(conn, Provider.list_scenarios())
  end

  get "/v1/scenarios/:id" do
    respond(conn, Provider.fetch_scenario(id))
  end

  post "/v1/scenarios/:id/runs" do
    respond(conn, Provider.create_run(id, conn.body_params), status: 201)
  end

  get "/v1/runs" do
    Contract.list(conn, Provider.list_runs())
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

  match _ do
    Contract.error(conn, 404, "not_found", "resource not found")
  end

  defp authenticate(conn, _opts), do: Auth.authenticate(conn, :provider_admin_api_token)

  defp respond(conn, result, opts \\ [])

  defp respond(conn, {:ok, resource}, opts) do
    Contract.success(conn, Keyword.get(opts, :status, 200), resource)
  end

  defp respond(conn, {:error, :not_found}, _opts),
    do: Contract.error(conn, 404, "not_found", "resource not found")

  defp respond(conn, {:error, {:invalid, detail}}, _opts),
    do: Contract.error(conn, 422, "invalid_request", detail)

  defp respond(conn, {:error, {:conflict, detail}}, _opts),
    do: Contract.error(conn, 409, "conflict", detail)

  defp respond(conn, {:error, reason}, _opts),
    do: Contract.error(conn, 500, "provider_error", inspect(reason))
end
