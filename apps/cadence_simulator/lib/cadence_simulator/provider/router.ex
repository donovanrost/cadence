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

  # Search uses POST for its filters. Its offers are reconstructed from the persisted run.
  defp flush_mutations(
         %{method: "POST", path_info: ["provider", "v1", "opportunities", "search"]} = conn,
         _opts
       ),
       do: conn

  defp flush_mutations(%{method: method} = conn, _opts)
       when method in ["POST", "PUT", "PATCH", "DELETE"] do
    token = Store.persistence_token()

    conn
    |> put_private(:provider_store_token, token)
    |> register_before_send(&await_mutations(&1, token))
  end

  defp flush_mutations(conn, _opts), do: conn

  defp await_mutations(%{status: status} = conn, token) when status in 200..299 do
    case Store.await_persisted(token) do
      :ok -> conn
      {:error, _reason} -> Contract.persistence_unavailable_response(conn)
    end
  end

  defp await_mutations(conn, _token), do: conn

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
