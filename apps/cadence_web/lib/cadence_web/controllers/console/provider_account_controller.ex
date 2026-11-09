defmodule CadenceWeb.Console.ProviderAccountController do
  @moduledoc """
  PA1 provider accounts under `/api/console/v1/organizations/:organization_id`.
  Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Management.{ProviderAccountDirectory, ProviderAccountWrites}
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

  def schema(conn, %{"key" => key}) do
    case ProviderAccountWrites.schema(key) do
      {:ok, fields} -> json(conn, %{data: ConfigJSON.encode(%{key: key, fields: fields})})
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, params) do
    case ProviderAccountWrites.create(conn.assigns.current_scope, params) do
      {:ok, result} -> conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case ProviderAccountWrites.update(conn.assigns.current_scope, id, params) do
      {:ok, result} -> conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id} = params) do
    case ProviderAccountWrites.retire(conn.assigns.current_scope, id, params["reason"]) do
      {:ok, result} -> json(conn, %{data: ConfigJSON.encode(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, {:in_use, missions}),
    do: Problem.respond(conn, :in_use, ConfigJSON.encode(%{missions: missions}))

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:invalid_provider_account, message}),
    do: Problem.respond(conn, :invalid_params, %{settings: message})

  defp error(conn, :provider_adapter_not_found),
    do: Problem.respond(conn, :provider_adapter_not_found)

  defp error(conn, :provider_account_not_found),
    do: Problem.respond(conn, :provider_account_not_found)

  defp error(conn, reason) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, reason) when is_atom(reason), do: Problem.respond(conn, reason)
  defp error(conn, {reason, _detail}) when is_atom(reason), do: Problem.respond(conn, reason)
end
