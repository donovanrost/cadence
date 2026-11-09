defmodule CadenceWeb.Console.ProviderAccountController do
  @moduledoc """
  PA1 provider accounts under `/api/console/v1/organizations/:organization_id`.
  Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Management.ProviderAccountDirectory
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, _params) do
    case ProviderAccountDirectory.list(conn.assigns.current_scope) do
      {:ok, data} -> json(conn, %{data: ConfigJSON.encode(data)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def test(conn, %{"id" => id}) do
    case ProviderAccountDirectory.test(conn.assigns.current_scope, id) do
      {:ok, result} -> json(conn, %{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, :provider_account_not_found),
    do: Problem.respond(conn, :provider_account_not_found)

  defp error(conn, _forbidden), do: Problem.respond(conn, :forbidden)
end
