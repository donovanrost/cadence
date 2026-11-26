defmodule CadenceSimulator.Provider.Router do
  @moduledoc "HTTP boundary for the canonical ground-station provider API."

  use Plug.Router, copy_opts_to_assign: :provider_router_config

  alias CadenceSimulator.Provider.{AdminRouter, ApiRouter, Contract, Store}

  plug(Plug.RequestId)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:flush_mutations)
  plug(:dispatch)

  forward("/admin", to: AdminRouter)
  forward("/provider", to: ApiRouter)

  get "/health" do
    json(conn, 200, %{"status" => "ok", "service" => "cadence-ground-network-simulator"})
  end

  match _ do
    Contract.error(conn, 404, "not_found", "resource not found")
  end

  # Persist all writes from one API operation before acknowledging it.
  defp flush_mutations(%{method: method} = conn, _opts) when method in ["POST", "PATCH"] do
    register_before_send(conn, fn conn ->
      if conn.status in 200..299, do: :ok = Store.flush()
      conn
    end)
  end

  defp flush_mutations(conn, _opts), do: conn

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
