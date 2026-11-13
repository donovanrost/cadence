defmodule CadenceWeb.Console.ProviderAccountController do
  @moduledoc """
  PA1 provider accounts under `/api/console/v1/organizations/:organization_id`.
  Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.GroundNetworks.{ProviderAccountRename, ProviderAccountRetirement}

  alias Cadence.Management.{
    ProviderAccountDirectory,
    ProviderAccountHistory,
    ProviderAccountWrites
  }

  alias Cadence.Missions
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

  @doc "PA1 history: versions newest first, with actor and changes from the previous one."
  def versions(conn, %{"id" => id}) do
    case ProviderAccountHistory.versions(conn.assigns.current_scope, id) do
      {:ok, data} -> json(conn, %{data: ConfigJSON.encode(data)})
      {:error, :forbidden} -> Problem.respond(conn, :forbidden)
      {:error, _not_found} -> Problem.respond(conn, :provider_account_not_found)
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
    scope = conn.assigns.current_scope

    with :ok <- rename(scope, id, params["name"]),
         {:ok, result} <- ProviderAccountWrites.update(scope, id, params) do
      conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  # The name is presentation, renamed without a new version (domain ProviderAccountRename).
  defp rename(_scope, _id, nil), do: :ok

  defp rename(scope, id, name) do
    case ProviderAccountRename.rename(scope, id, name) do
      {:ok, _account} ->
        :ok

      {:error, :invalid_display_name} ->
        {:error, {:invalid_params, %{"name" => "Use 1 to 120 characters."}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope

    case ProviderAccountRetirement.retire(scope, id, params["reason"] || "Removed in the console") do
      {:ok, account} ->
        json(conn, %{
          data:
            ConfigJSON.encode(%{id: account.provider_account_id, state: account.lifecycle_state})
        })

      {:error, {:in_use, uses}} ->
        error(conn, {:in_use, in_use_missions(scope.organization_id, uses)})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  # Name the missions that still use the account, so the console can list them.
  defp in_use_missions(organization_id, uses) do
    names =
      organization_id |> Missions.list_missions() |> Map.new(&{&1.mission_id, &1.display_name})

    uses
    |> Enum.map(& &1.mission_id)
    |> Enum.uniq()
    |> Enum.map(&%{id: &1, name: Map.get(names, &1)})
  end

  defp error(conn, {:in_use, missions}),
    do: Problem.respond(conn, :in_use, ConfigJSON.encode(%{missions: missions}))

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, :invalid_provider_account_base_url),
    do:
      Problem.respond(conn, :invalid_params, %{
        "settings.base_url" => "Use an http or https address."
      })

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
