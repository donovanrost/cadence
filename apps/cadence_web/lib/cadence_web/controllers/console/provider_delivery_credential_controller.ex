defmodule CadenceWeb.Console.ProviderDeliveryCredentialController do
  @moduledoc false
  use CadenceWeb, :controller

  alias Cadence.GroundNetworks.ProviderDeliveryCredentials
  alias Cadence.Management.Transports
  alias CadenceWeb.Console.Problem

  def show(conn, %{"provider_id" => provider, "binding_id" => binding}) do
    reply(conn, ProviderDeliveryCredentials.show(scope(conn), mission(conn), provider, binding))
  end

  def issue(conn, %{"provider_id" => provider, "binding_id" => binding} = params) do
    result =
      ProviderDeliveryCredentials.issue(
        scope(conn),
        mission(conn),
        provider,
        binding,
        params
      )

    reply(conn, result, :created)
  end

  def rotate(conn, %{"provider_id" => provider, "binding_id" => binding} = params) do
    reply(
      conn,
      ProviderDeliveryCredentials.rotate(
        scope(conn),
        mission(conn),
        provider,
        binding,
        params
      )
    )
  end

  def revoke(conn, %{"provider_id" => provider, "binding_id" => binding} = params) do
    reply(
      conn,
      ProviderDeliveryCredentials.revoke(scope(conn), mission(conn), provider, binding, params)
    )
  end

  def downgrade(conn, %{"provider_id" => provider, "binding_id" => binding} = params) do
    case Transports.downgrade_delivery_auth(scope(conn), mission(conn), provider, binding, params) do
      {:ok, transport} ->
        reply(conn, {:ok, %{version: transport.version, delivery_auth: "plaintext"}})

      error ->
        reply(conn, error)
    end
  end

  defp reply(conn, result, status \\ :ok)

  defp reply(conn, {:ok, result}, status), do: conn |> put_status(status) |> json(%{data: result})

  defp reply(conn, {:error, reason}, _status)
       when reason in [:forbidden, :scope_mismatch, :authenticated_user_required],
       do: Problem.respond(conn, :forbidden)

  defp reply(conn, {:error, reason}, _status)
       when reason in [
              :delivery_binding_unavailable,
              :delivery_credential_not_found,
              :delivery_generation_not_found,
              :transport_not_found
            ],
       do: Problem.respond(conn, :delivery_credential_not_found)

  defp reply(conn, {:error, :delivery_issuer_unavailable}, _status),
    do: Problem.respond(conn, :delivery_issuer_unavailable)

  defp reply(conn, {:error, reason}, _status)
       when reason in [
              :delivery_binding_retired,
              :delivery_credential_already_issued,
              :delivery_credential_not_issued,
              :version_conflict
            ],
       do: Problem.respond(conn, :version_conflict)

  defp reply(conn, {:error, reason}, _status)
       when reason in [
              :invalid_delivery_csr,
              :invalid_delivery_generation,
              :invalid_delivery_binding,
              :invalid_delivery_credential_reason,
              :invalid_delivery_revocation_target,
              :invalid_delivery_downgrade,
              :delivery_auth_downgrade_required
            ],
       do: Problem.respond(conn, :invalid_params, %{reason: reason})

  defp reply(conn, {:error, _reason}, _status), do: Problem.respond(conn, :invalid_params)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
