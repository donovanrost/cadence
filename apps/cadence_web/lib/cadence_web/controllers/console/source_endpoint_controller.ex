defmodule CadenceWeb.Console.SourceEndpointController do
  @moduledoc "Mission and spacecraft source endpoint reads and creation."

  use CadenceWeb, :controller

  import CadenceWeb.API.ParamParser, only: [positive_integer: 3]

  alias Cadence.Auth.Policy
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore
  alias CadenceWeb.Console.{Problem, SourceEndpointParams}

  @max_offset 9_223_372_036_854_775_807

  def index(conn, params) do
    spacecraft_id = Map.get(conn.path_params, "spacecraft_id")

    with :ok <- authorize(conn),
         :ok <- ensure_spacecraft(conn, spacecraft_id),
         {:ok, page} <- positive_integer(params, "page", 1),
         {:ok, page_size} <- positive_integer(params, "page_size", 50),
         true <- (page - 1) * min(page_size, 100) <= @max_offset do
      listing =
        SourceEndpoints.list_source_endpoints_page(org_id(conn), mission_id(conn),
          spacecraft_id: spacecraft_id,
          page: page,
          page_size: page_size
        )

      json(conn, %{
        data: Enum.map(listing.items, &encode/1),
        meta: Map.take(listing, [:page, :page_size, :total_count])
      })
    else
      error -> failure(conn, error)
    end
  end

  def show(conn, %{"source_endpoint_id" => id}) do
    with :ok <- authorize(conn),
         {:ok, endpoint} <-
           SourceEndpoints.fetch_source_endpoint(org_id(conn), mission_id(conn), id) do
      json(conn, %{data: encode(endpoint)})
    else
      error -> failure(conn, error)
    end
  end

  def create(conn, %{"source_endpoint" => attrs} = params) when is_map(attrs) do
    spacecraft_id = Map.get(conn.path_params, "spacecraft_id")

    with :ok <- authorize(conn),
         :ok <- reject_supplied_id(params, attrs),
         :ok <- ensure_spacecraft(conn, spacecraft_id),
         {:ok, endpoint} <-
           SourceEndpointParams.source_endpoint(
             org_id(conn),
             mission_id(conn),
             spacecraft_id,
             attrs
           ),
         {:ok, _created} <- SourceEndpoints.persist_source_endpoint(org_id(conn), endpoint),
         {:ok, saved} <-
           SourceEndpoints.fetch_source_endpoint(
             org_id(conn),
             mission_id(conn),
             endpoint.source_endpoint_id
           ) do
      conn |> put_status(:created) |> json(%{data: encode(saved)})
    else
      error -> failure(conn, error)
    end
  end

  def create(conn, _params), do: Problem.respond(conn, :invalid_params)

  defp reject_supplied_id(params, attrs) do
    if Map.has_key?(params, "source_endpoint_id") or Map.has_key?(attrs, "source_endpoint_id"),
      do: {:error, {:invalid_param, "source_endpoint_id", :server_generated}},
      else: :ok
  end

  defp authorize(conn) do
    Policy.authorize(conn.assigns.current_scope, :manage_mission, %{
      organization_id: org_id(conn),
      mission_id: mission_id(conn)
    })
  end

  defp ensure_spacecraft(_conn, nil), do: :ok

  defp ensure_spacecraft(conn, spacecraft_id) do
    with {:ok, _spacecraft} <-
           SpacecraftStore.fetch_spacecraft(org_id(conn), mission_id(conn), spacecraft_id),
         do: :ok
  end

  defp failure(conn, false), do: Problem.respond(conn, :invalid_params, %{field: "page"})

  defp failure(conn, {:error, {:invalid_param, key, reason}}),
    do: Problem.respond(conn, :invalid_params, %{field: key, reason: reason})

  defp failure(conn, {:error, %Ecto.Changeset{}}), do: Problem.respond(conn, :invalid_params)
  defp failure(conn, {:error, reason}), do: Problem.respond(conn, reason)

  defp encode(endpoint), do: Map.from_struct(endpoint)
  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
