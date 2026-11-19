defmodule Cadence.Auth.ServiceAccountability do
  @moduledoc """
  Who is accountable for a service identity (#280, director 11-19): the people its acts count as for
  separation of duties. Each `service_identity_accountables` row is one accountable actor:

  - `issued`: whoever issued the identity;
  - `rotated`: whoever rotated its credential;
  - `attributed`: whoever an organization admin later recorded as accountable, plus that admin.

  An actor is a person, or another service whose own accountable people count in turn
  (transitively). Rows are written by the server, in the same transaction as the act they record,
  from the acting scope, never from client input (identity metadata is client-writable on REST).

  `people/2` is `{:error, :unknown}` when the identity has no `issued` or `attributed` row, or any
  service link in its chain is unknown or loops back. Callers fail closed on unknown.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope, ServiceAccountableRow, ServiceIdentityRow}
  alias Cadence.{Ids, Repo}

  @type event :: :issued | :rotated | :attributed

  @doc """
  Records `scope`'s actor as accountable for `service_identity_id` because of `event`. Must run in
  the transaction of the act it records.
  """
  @spec record(binary(), binary(), event(), Scope.t()) :: :ok | {:error, term()}
  def record(organization_id, service_identity_id, event, %Scope{} = scope)
      when event in [:issued, :rotated] do
    with {:ok, actor} <- actor(scope) do
      insert(organization_id, service_identity_id, event, actor, recorded_by(scope))
    end
  end

  @doc """
  Records `user_ids` as accountable for an identity, plus the organization admin who records them
  (#280: attributing never clears the way for its author to approve). Person-only, organization
  admins only. The rows are the audit: who recorded whom, and when.
  """
  @spec attribute(Scope.t(), binary(), binary(), [binary()]) :: :ok | {:error, term()}
  def attribute(%Scope{} = scope, organization_id, service_identity_id, user_ids)
      when is_list(user_ids) do
    with :ok <- authorize_attribution(scope, organization_id),
         :ok <- valid_user_ids(user_ids),
         {:ok, _row} <- fetch_identity(organization_id, service_identity_id) do
      admin_id = scope.user.user_id

      Repo.transaction(fn ->
        [admin_id | user_ids]
        |> Enum.uniq()
        |> Enum.each(&attribute_one(organization_id, service_identity_id, &1, admin_id))
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "The people accountable for a service identity, transitively; unknown fails closed."
  @spec people(binary(), binary()) :: {:ok, [binary()]} | {:error, :unknown}
  def people(organization_id, service_identity_id)
      when is_binary(organization_id) and is_binary(service_identity_id) do
    case resolve(organization_id, service_identity_id, MapSet.new()) do
      {:ok, ids} -> {:ok, ids |> MapSet.to_list() |> Enum.sort()}
      :unknown -> {:error, :unknown}
    end
  end

  def people(_organization_id, _service_identity_id), do: {:error, :unknown}

  defp resolve(organization_id, service_identity_id, visited) do
    if MapSet.member?(visited, service_identity_id) do
      :unknown
    else
      rows = rows(organization_id, service_identity_id)

      if Enum.any?(rows, &(&1.event in ["issued", "attributed"])),
        do: collect(organization_id, rows, MapSet.put(visited, service_identity_id)),
        else: :unknown
    end
  end

  defp collect(organization_id, rows, visited) do
    Enum.reduce_while(rows, {:ok, MapSet.new()}, fn row, {:ok, acc} ->
      case row_people(organization_id, row, visited) do
        {:ok, ids} -> {:cont, {:ok, MapSet.union(acc, ids)}}
        :unknown -> {:halt, :unknown}
      end
    end)
  end

  defp row_people(_organization_id, %{actor_kind: "user", user_id: id}, _visited),
    do: {:ok, MapSet.new([id])}

  defp row_people(organization_id, %{actor_kind: "service", by_service_identity_id: id}, visited),
    do: resolve(organization_id, id, visited)

  defp rows(organization_id, service_identity_id) do
    ServiceAccountableRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.service_identity_id == ^service_identity_id
    )
    |> Repo.all()
  end

  defp attribute_one(organization_id, service_identity_id, user_id, admin_id) do
    case insert(organization_id, service_identity_id, :attributed, {:user, user_id}, admin_id) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert(organization_id, service_identity_id, event, actor, recorded_by_user_id) do
    {user_id, by_service_identity_id, kind} =
      case actor do
        {:user, id} -> {id, nil, "user"}
        {:service, id} -> {nil, id, "service"}
      end

    %{
      accountable_id: Ids.new("svc_acct"),
      organization_id: organization_id,
      service_identity_id: service_identity_id,
      event: Atom.to_string(event),
      actor_kind: kind,
      user_id: user_id,
      by_service_identity_id: by_service_identity_id,
      recorded_by_user_id: recorded_by_user_id,
      recorded_at: DateTime.utc_now()
    }
    |> ServiceAccountableRow.changeset()
    |> Repo.insert()
    |> case do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp actor(%Scope{actor_kind: :user, user: %{user_id: id}}) when is_binary(id) and id != "",
    do: {:ok, {:user, id}}

  defp actor(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}})
       when is_binary(id) and id != "",
       do: {:ok, {:service, id}}

  defp actor(_scope), do: {:error, :service_identity_actor_required}

  defp recorded_by(%Scope{actor_kind: :user, user: %{user_id: id}}), do: id
  defp recorded_by(_scope), do: nil

  defp authorize_attribution(%Scope{actor_kind: :user, user: %{user_id: id}} = scope, org)
       when is_binary(id) do
    Policy.authorize(scope, :manage_service_identities, %{organization_id: org})
  end

  defp authorize_attribution(_scope, _org), do: {:error, :authenticated_user_required}

  defp valid_user_ids(ids) do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")),
      do: :ok,
      else: {:error, :invalid_accountable_user_ids}
  end

  defp fetch_identity(organization_id, service_identity_id) do
    ServiceIdentityRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.service_identity_id == ^service_identity_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :service_identity_not_found}
      row -> {:ok, row}
    end
  end
end
