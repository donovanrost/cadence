defmodule Cadence.Auth.ServiceIdentityKeys do
  @moduledoc """
  Rotating and revoking service identity keys (O6). A new token is returned once; only its
  digest is stored (`ServiceIdentityRow`). Rotation records its time in the identity's metadata
  (`key_rotated_at`), which the directory reads as `key_created_at`.
  """

  import Ecto.Query

  alias Cadence.Auth.{Scope, ServiceAccountability, ServiceIdentityRow}
  alias Cadence.Repo

  @doc """
  Issues a new API token for an active identity; the old one stops authenticating. Whoever rotates
  it (`rotated_by`) becomes accountable for it, in the same transaction (#280).
  """
  @spec rotate(binary(), binary(), Scope.t()) ::
          {:ok, map()} | {:error, :service_identity_not_found | term()}
  def rotate(organization_id, service_identity_id, %Scope{} = rotated_by) do
    api_token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    change_active(organization_id, service_identity_id, fn row ->
      with {:ok, row} <- Repo.update(ServiceIdentityRow.rotate_changeset(row, api_token)),
           :ok <-
             ServiceAccountability.record(
               organization_id,
               service_identity_id,
               :rotated,
               rotated_by
             ) do
        {:ok, %{service_identity: ServiceIdentityRow.to_domain(row), api_token: api_token}}
      end
    end)
  end

  @doc "Disables an active identity; its token stops authenticating."
  @spec disable(binary(), binary()) ::
          {:ok, struct()} | {:error, :service_identity_not_found | term()}
  def disable(organization_id, service_identity_id) do
    change_active(organization_id, service_identity_id, fn row ->
      with {:ok, row} <- Repo.update(ServiceIdentityRow.disable_changeset(row)) do
        {:ok, ServiceIdentityRow.to_domain(row)}
      end
    end)
  end

  defp change_active(organization_id, service_identity_id, change) do
    Repo.transaction(fn ->
      ServiceIdentityRow
      |> where(
        [r],
        r.organization_id == ^organization_id and r.service_identity_id == ^service_identity_id and
          r.lifecycle_state == "active"
      )
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> apply_change(change)
    end)
    |> case do
      {:ok, {:ok, result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_change(nil, _change), do: Repo.rollback(:service_identity_not_found)

  defp apply_change(row, change) do
    case change.(row) do
      {:error, reason} -> Repo.rollback(reason)
      ok -> ok
    end
  end
end
