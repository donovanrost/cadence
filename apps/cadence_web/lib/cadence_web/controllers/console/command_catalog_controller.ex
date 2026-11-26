defmodule CadenceWeb.Console.CommandCatalogController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/commands` and
  `GET …/commands/:command_id` (M17). Contract: docs/apogee/api/commanding.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.CommandCatalog
  alias CadenceWeb.Console.{CommandCatalogJSON, Problem}

  @max_limit 500

  def index(conn, params) do
    with {:ok, opts} <- list_opts(params),
         {:ok, page} <- CommandCatalog.list(org_id(conn), mission_id(conn), opts) do
      json(conn, CommandCatalogJSON.list(page))
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
      {:error, _reason} -> Problem.respond(conn, :catalog_unavailable)
    end
  end

  def show(conn, %{"command_id" => command_id}) do
    case CommandCatalog.fetch(org_id(conn), mission_id(conn), command_id) do
      {:ok, result} -> json(conn, CommandCatalogJSON.show(result))
      {:error, :command_not_found} -> Problem.respond(conn, :command_not_found)
      {:error, _reason} -> Problem.respond(conn, :catalog_unavailable)
    end
  end

  defp list_opts(params) do
    case parse_limit(Map.get(params, "limit")) do
      {:ok, limit} ->
        {:ok, %{query: params["q"], after: blank_to_nil(params["after"]), limit: limit}}

      :error ->
        {:error, {:invalid_params, %{limit: "must be an integer from 1 to #{@max_limit}"}}}
    end
  end

  defp parse_limit(nil), do: {:ok, 100}

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..@max_limit -> {:ok, limit}
      _other -> :error
    end
  end

  defp parse_limit(_value), do: :error

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
