defmodule CadenceSimulator.Provider.ApiRouter do
  @moduledoc false

  use Plug.Router

  alias CadenceSimulator.Provider

  alias CadenceSimulator.Provider.{
    Auth,
    Capabilities,
    ContactResults,
    Contacts,
    Contract,
    DeliveryProfiles,
    Environment,
    Opportunities,
    ServiceProfiles
  }

  alias CadenceSimulator.Provider.Store

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

  post "/v1/delivery-profiles" do
    with_environment(conn, fn conn, run ->
      respond(
        conn,
        DeliveryProfiles.provision(run, conn.body_params, request_id: request_id(conn)),
        status: 201
      )
    end)
  end

  get "/v1/delivery-profiles/:id" do
    with_environment(conn, fn conn, run -> respond(conn, DeliveryProfiles.fetch(run, id)) end)
  end

  post "/v1/opportunities/search" do
    with_environment(conn, fn conn, run ->
      case Opportunities.search(run, conn.body_params) do
        {:ok, page} ->
          Contract.list(conn, page.data,
            next_cursor: page.next_cursor,
            truncated: page.truncated
          )

        error ->
          respond(conn, error)
      end
    end)
  end

  post "/v1/contacts" do
    with_environment(conn, fn conn, run ->
      result =
        Contacts.create(run, conn.body_params,
          idempotency_key: request_header(conn, "idempotency-key"),
          request_id: request_id(conn)
        )

      maybe_drop_contact_response_after_commit(run, result)
      respond(conn, result, status: 201)
    end)
  end

  get "/v1/contacts" do
    with_environment(conn, fn conn, run ->
      Contract.list(conn, Contacts.list(run, conn.params))
    end)
  end

  get "/v1/contacts/:id/result" do
    with_environment(conn, fn conn, run -> respond(conn, ContactResults.fetch(run, id)) end)
  end

  post "/v1/contacts/:id/cancel" do
    with_environment(conn, fn conn, run ->
      respond(conn, Contacts.cancel(run, id, request_id: request_id(conn)))
    end)
  end

  get "/v1/contacts/:id" do
    with_environment(conn, fn conn, run -> respond(conn, Contacts.fetch(run, id)) end)
  end

  get "/v1/events" do
    with_environment(conn, fn conn, run ->
      cursor = parse_integer(conn.params["cursor"], 0)
      limit = parse_integer(conn.params["limit"], 100)
      page = Store.events_for_run(run["id"], max(cursor, 0), max(limit, 1))
      Contract.list(conn, page.data, next_cursor: Integer.to_string(page.next_cursor))
    end)
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

  defp respond(conn, result, opts \\ [])

  defp respond(conn, {:ok, resource}, opts) do
    Contract.success(conn, Keyword.get(opts, :status, 200), resource)
  end

  defp respond(conn, {:error, :not_found}, _opts),
    do: Contract.error(conn, 404, "not_found", "resource not found")

  defp respond(conn, {:error, :not_ready}, _opts),
    do: Contract.error(conn, 409, "conflict", "Contact Result is not available yet")

  defp respond(conn, {:error, {:invalid, detail}}, _opts),
    do: Contract.error(conn, 422, "invalid_request", detail)

  defp respond(conn, {:error, {:conflict, detail}}, _opts),
    do: Contract.error(conn, 409, "conflict", detail)

  defp respond(conn, {:error, {:no_capacity, detail}}, _opts),
    do: Contract.error(conn, 409, "no_capacity", detail)

  defp respond(conn, {:error, reason}, _opts),
    do: Contract.error(conn, 500, "provider_error", inspect(reason))

  defp request_id(conn) do
    request_header(conn, "x-request-id") ||
      Plug.Conn.get_resp_header(conn, "x-request-id") |> List.first()
  end

  defp request_header(conn, name), do: Plug.Conn.get_req_header(conn, name) |> List.first()

  defp maybe_drop_contact_response_after_commit(run, {:ok, _contact}) do
    limit =
      get_in(run, [
        "scenario_snapshot",
        "fault_profile",
        "contact_response_loss_after_commit_count"
      ]) ||
        0

    if Store.consume_fault(run["id"], "contact_response_loss_after_commit", limit) do
      Process.exit(self(), :kill)
    end
  end

  defp maybe_drop_contact_response_after_commit(_run, _result), do: :ok

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end
end
