defmodule CadenceSimulator.Provider.ApiRouter do
  @moduledoc false

  use Plug.Router

  alias CadenceSimulator.Provider

  alias CadenceSimulator.Provider.{
    Auth,
    Capabilities,
    Contract,
    DeliveryProfiles,
    Environment,
    ServiceProfiles
  }

  plug(:match)
  plug(:authenticate)
  plug(:dispatch)

  get "/v1/account" do
    with_environment(conn, fn conn, run ->
      Contract.success(conn, 200, %{
        "provider_environment_ref" => run["provider_environment_ref"],
        "state" => run["state"],
        "scenario_ref" => run["scenario_id"],
        "simulated" => true
      })
    end)
  end

  get "/v1/capabilities" do
    with_environment(conn, fn conn, run ->
      Contract.success(conn, 200, Capabilities.for_run(run))
    end)
  end

  get "/v1/spacecraft" do
    with_environment(conn, fn conn, run ->
      case Provider.spacecraft(run["id"]) do
        {:ok, spacecraft} -> Contract.list(conn, spacecraft)
        {:error, :not_found} -> environment_not_found(conn)
      end
    end)
  end

  get "/v1/ground-stations" do
    with_environment(conn, fn conn, run ->
      case Provider.ground_stations(run["id"]) do
        {:ok, stations} -> Contract.list(conn, stations)
        {:error, :not_found} -> environment_not_found(conn)
      end
    end)
  end

  get "/v1/service-profiles" do
    with_environment(conn, fn conn, run -> Contract.list(conn, ServiceProfiles.for_run(run)) end)
  end

  get "/v1/delivery-profiles" do
    with_environment(conn, fn conn, run -> Contract.list(conn, DeliveryProfiles.for_run(run)) end)
  end

  match _ do
    Contract.error(conn, 404, "not_found", "resource not found")
  end

  defp authenticate(conn, _opts), do: Auth.authenticate(conn, :provider_api_token)

  defp with_environment(conn, callback) when is_function(callback, 2) do
    case Environment.resolve(conn) do
      {:ok, run} ->
        callback.(conn, run)

      {:error, :missing} ->
        Contract.error(
          conn,
          422,
          "invalid_request",
          "x-simulator-environment-ref header is required"
        )

      {:error, :not_found} ->
        environment_not_found(conn)
    end
  end

  defp environment_not_found(conn) do
    Contract.error(conn, 404, "not_found", "provider environment not found")
  end
end
