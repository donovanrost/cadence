defmodule CadenceSimulator.Provider.Router do
  @moduledoc "HTTP boundary for the canonical ground-station provider API."

  use Plug.Router

  alias CadenceSimulator.Provider.{AdminRouter, ApiRouter, Contract}

  plug(Plug.RequestId)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  forward("/admin", to: AdminRouter)
  forward("/provider", to: ApiRouter)

  get "/health" do
    json(conn, 200, %{"status" => "ok", "service" => "cadence-ground-network-simulator"})
  end

  match _ do
    Contract.error(conn, 404, "not_found", "resource not found")
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
