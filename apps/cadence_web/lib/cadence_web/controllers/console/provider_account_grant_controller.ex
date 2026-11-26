defmodule CadenceWeb.Console.ProviderAccountGrantController do
  @moduledoc """
  L13 (owner: api-ops): one provider account's detail (PA2), its mission grants and its
  credential revoke, under `/api/v1/organizations/:organization_id/provider-accounts/:id`.
  Contract: docs/apogee/api/setup.md §Provider-account grants (L13). Org admins only.
  """

  use CadenceWeb, :controller

  require Logger

  alias Cadence.Control.Providers.ProviderAccountGrantWrites
  alias Cadence.GroundNetworks.ProviderAccounts
  alias Cadence.Management.ProviderAccountDirectory
  alias Cadence.Management.Providers.ProviderAccountDetail
  alias Cadence.Missions
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @changed ~w(account_changed grant_changed credential_changed)a

  # PA2
  def show(conn, %{"id" => id}) do
    case ProviderAccountDetail.fetch(scope(conn), id) do
      {:ok, detail} ->
        json(conn, %{
          data:
            ConfigJSON.encode(%{
              account:
                detail.account
                |> ProviderAccountDirectory.account_row(detail.version)
                |> Map.merge(detail.details),
              grants: detail.grants,
              permissions: ProviderAccountDirectory.permissions(scope(conn))
            })
        })

      error ->
        error(conn, error)
    end
  end

  def grant(conn, %{"id" => id} = params) do
    case ProviderAccountGrantWrites.grant(scope(conn), id, params) do
      {:ok, grant} ->
        conn
        |> put_status(:created)
        |> json(%{data: ConfigJSON.encode(%{grant: grant_row(conn, grant)})})

      error ->
        error(conn, error)
    end
  end

  def revoke_grant(conn, %{"id" => id, "grant_id" => grant_id} = params) do
    case ProviderAccountGrantWrites.revoke_grant(scope(conn), id, grant_id, params) do
      {:ok, %{grant: grant, flagged_reservations: flagged}} ->
        json(conn, %{
          data: ConfigJSON.encode(%{grant: grant_row(conn, grant), flagged_reservations: flagged})
        })

      error ->
        error(conn, error)
    end
  end

  def revoke_credential(conn, %{"id" => id} = params) do
    with :ok <- ProviderAccountGrantWrites.revoke_credential(scope(conn), id, params),
         {:ok, account, version} <- ProviderAccounts.fetch(scope(conn), id) do
      json(conn, %{
        data:
          ConfigJSON.encode(%{account: ProviderAccountDirectory.account_row(account, version)})
      })
    else
      error -> error(conn, error)
    end
  end

  defp grant_row(conn, grant) do
    org = scope(conn).organization_id
    names = org |> Missions.list_missions() |> Map.new(&{&1.mission_id, &1.display_name})

    ProviderAccountDetail.grant_row(grant, names, ProviderAccountDetail.people(org, [grant]))
  end

  defp error(conn, {:error, {code, %{version: version}}}) when code in @changed,
    do: Problem.respond(conn, code, %{version: version})

  defp error(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:error, reason}) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, {:error, reason})
       when reason in [:account_archived, :provider_account_archived],
       do: Problem.respond(conn, :account_archived)

  defp error(conn, {:error, reason})
       when reason in [:grant_already_revoked, :provider_account_grant_revoked],
       do: Problem.respond(conn, :grant_already_revoked)

  defp error(conn, {:error, reason})
       when reason in [:credential_already_revoked, :provider_credential_revoked],
       do: Problem.respond(conn, :credential_already_revoked)

  defp error(conn, {:error, reason})
       when reason in [:account_grant_not_found, :provider_account_grant_not_found],
       do: Problem.respond(conn, :account_grant_not_found)

  defp error(conn, {:error, :provider_account_not_found}),
    do: Problem.respond(conn, :provider_account_not_found)

  # The field check above names the field; this is the domain's whole-map check agreeing.
  defp error(conn, {:error, :provider_account_grant_widens_guardrails}),
    do: Problem.respond(conn, :invalid_params)

  defp error(conn, error) do
    Logger.warning("provider account write failed: #{inspect(error, limit: 20)}")
    Problem.respond(conn, :invalid_params)
  end

  defp scope(conn), do: conn.assigns.current_scope
end
