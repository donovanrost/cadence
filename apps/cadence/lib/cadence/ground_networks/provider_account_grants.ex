defmodule Cadence.GroundNetworks.ProviderAccountGrants do
  @moduledoc "Authorized mission grants for exact Provider Account versions."

  import Ecto.Query
  alias Ecto.Multi

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.GroundNetworks.{
    ProviderAccountGrant,
    ProviderAccounts,
    ProviderAudit,
    ProviderAuditEntry
  }

  alias Cadence.GroundNetworks.ProviderAccountGrants.GrantRow,
    as: ProviderAccountGrantRow

  alias Cadence.Missions
  alias Cadence.Repo

  @spec grant(Scope.t(), binary(), binary(), map(), keyword()) ::
          {:ok, ProviderAccountGrant.t()} | {:error, term()}
  def grant(%Scope{} = current_scope, mission_id, provider_account_id, attrs, opts \\ []) do
    organization_id = current_scope.organization_id

    with :ok <-
           Policy.authorize(current_scope, :manage_provider_accounts, %{
             organization_id: organization_id
           }) do
      grant_for_system(
        organization_id,
        mission_id,
        provider_account_id,
        attrs,
        actor_document(current_scope),
        opts
      )
    end
  end

  @spec grant_for_system(binary(), binary(), binary(), map(), map(), keyword()) ::
          {:ok, ProviderAccountGrant.t()} | {:error, term()}
  def grant_for_system(organization_id, mission_id, provider_account_id, attrs, actor, opts \\ []) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, account, active_version} <-
           ProviderAccounts.fetch_for_system(organization_id, provider_account_id),
         account_version_number = value(attrs, :provider_account_version, active_version.version),
         {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             organization_id,
             provider_account_id,
             account_version_number
           ),
         true <- account.lifecycle_state == :active,
         {:ok, grant} <-
           build_grant(organization_id, mission_id, account_version, attrs, actor, opts),
         true <-
           ProviderAccountGrant.restrictions_narrow?(
             account_version.guardrails,
             grant.restrictions
           ) do
      audit = grant_audit(grant, "provider_account_grant.granted", actor, opts)

      Multi.new()
      |> Multi.insert(:grant, ProviderAccountGrantRow.changeset(grant))
      |> ProviderAudit.put_entry(:audit_entry, audit)
      |> Repo.transaction()
      |> case do
        {:ok, %{grant: row}} -> {:ok, ProviderAccountGrantRow.to_domain(row)}
        {:error, _operation, reason, _changes} -> {:error, reason}
      end
    else
      false -> {:error, :provider_account_grant_widens_guardrails}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec revoke(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, ProviderAccountGrant.t()} | {:error, term()}
  def revoke(%Scope{} = current_scope, provider_account_grant_id, reason, opts \\ []) do
    organization_id = current_scope.organization_id

    with :ok <-
           Policy.authorize(current_scope, :manage_provider_accounts, %{
             organization_id: organization_id
           }),
         {:ok, %ProviderAccountGrant{} = current} <-
           fetch_active_for_system(organization_id, provider_account_grant_id) do
      now = Keyword.get(opts, :now, DateTime.utc_now())

      revoked = %ProviderAccountGrant{
        current
        | version: current.version + 1,
          lifecycle_state: :revoked,
          revoked_by: actor_id(current_scope),
          revoked_at: now,
          revoke_reason: text_reason(reason)
      }

      audit =
        grant_audit(
          revoked,
          "provider_account_grant.revoked",
          actor_document(current_scope),
          opts
        )

      Multi.new()
      |> Multi.insert(:grant, ProviderAccountGrantRow.changeset(revoked))
      |> ProviderAudit.put_entry(:audit_entry, audit)
      |> Repo.transaction()
      |> case do
        {:ok, %{grant: row}} -> {:ok, ProviderAccountGrantRow.to_domain(row)}
        {:error, _operation, error, _changes} -> {:error, error}
      end
    end
  end

  @spec fetch_active_for_system(binary(), binary()) ::
          {:ok, ProviderAccountGrant.t()}
          | {:error, :provider_account_grant_not_found | :provider_account_grant_revoked}
  def fetch_active_for_system(organization_id, provider_account_grant_id) do
    case latest_row(organization_id, provider_account_grant_id) do
      nil ->
        {:error, :provider_account_grant_not_found}

      %ProviderAccountGrantRow{lifecycle_state: "revoked"} ->
        {:error, :provider_account_grant_revoked}

      row ->
        {:ok, ProviderAccountGrantRow.to_domain(row)}
    end
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ProviderAccountGrant.t()} | {:error, :provider_account_grant_not_found}
  def fetch_version(organization_id, provider_account_grant_id, mission_id, version) do
    ProviderAccountGrantRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_account_grant_id == ^provider_account_grant_id and
        row.mission_id == ^mission_id and row.version == ^version
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :provider_account_grant_not_found}
      row -> {:ok, ProviderAccountGrantRow.to_domain(row)}
    end
  end

  @spec list_for_mission(binary(), binary(), keyword()) :: [ProviderAccountGrant.t()]
  def list_for_mission(organization_id, mission_id, opts \\ []) do
    active_only? = Keyword.get(opts, :active_only?, true)

    ProviderAccountGrantRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> order_by([row], asc: row.provider_account_grant_id, desc: row.version)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.provider_account_grant_id, row) end)
    |> Map.values()
    |> then(fn rows ->
      if active_only?, do: Enum.reject(rows, &(&1.lifecycle_state == "revoked")), else: rows
    end)
    |> Enum.map(&ProviderAccountGrantRow.to_domain/1)
  end

  @spec list(Scope.t(), binary(), keyword()) ::
          {:ok, [ProviderAccountGrant.t()]} | {:error, term()}
  def list(%Scope{} = current_scope, provider_account_id, opts \\ []) do
    with :ok <-
           Policy.authorize(current_scope, :read_organization, %{
             organization_id: current_scope.organization_id
           }) do
      {:ok, list_for_account(current_scope.organization_id, provider_account_id, opts)}
    end
  end

  @spec list_for_account(binary(), binary(), keyword()) :: [ProviderAccountGrant.t()]
  def list_for_account(organization_id, provider_account_id, opts \\ []) do
    active_only? = Keyword.get(opts, :active_only?, false)

    ProviderAccountGrantRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_account_id == ^provider_account_id
    )
    |> order_by([row], asc: row.provider_account_grant_id, desc: row.version)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.provider_account_grant_id, row) end)
    |> Map.values()
    |> then(fn rows ->
      if active_only?, do: Enum.reject(rows, &(&1.lifecycle_state == "revoked")), else: rows
    end)
    |> Enum.map(&ProviderAccountGrantRow.to_domain/1)
  end

  @spec validate_binding(binary(), binary(), binary(), pos_integer(), binary(), pos_integer()) ::
          {:ok, ProviderAccountGrant.t()} | {:error, term()}
  def validate_binding(
        organization_id,
        mission_id,
        account_id,
        account_version,
        grant_id,
        grant_version
      ) do
    with {:ok, grant} <- fetch_version(organization_id, grant_id, mission_id, grant_version),
         true <- grant.lifecycle_state == :active,
         true <- grant.provider_account_id == account_id,
         true <- grant.provider_account_version == account_version,
         {:ok, latest} <- fetch_active_for_system(organization_id, grant_id),
         true <- latest.version == grant_version do
      {:ok, grant}
    else
      false -> {:error, :provider_account_grant_binding_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_grant(organization_id, mission_id, account_version, attrs, actor, opts) do
    grant_attrs =
      %{
        organization_id: organization_id,
        mission_id: mission_id,
        provider_account_id: account_version.provider_account_id,
        provider_account_version: account_version.version,
        version: 1,
        restrictions: value(attrs, :restrictions, %{}),
        granted_by: actor["id"],
        granted_at: Keyword.get(opts, :now, DateTime.utc_now()),
        grant_reason: value(attrs, :grant_reason),
        metadata: value(attrs, :metadata, %{})
      }
      |> maybe_put(:provider_account_grant_id, value(attrs, :provider_account_grant_id))

    {:ok, ProviderAccountGrant.new(grant_attrs)}
  rescue
    error in ArgumentError ->
      {:error, {:invalid_provider_account_grant, Exception.message(error)}}
  end

  defp grant_audit(grant, action, actor, opts) do
    ProviderAuditEntry.new(%{
      organization_id: grant.organization_id,
      mission_id: grant.mission_id,
      provider_account_id: grant.provider_account_id,
      provider_account_grant_id: grant.provider_account_grant_id,
      action: action,
      outcome: "succeeded",
      recorded_at: Keyword.get(opts, :now, DateTime.utc_now()),
      source_document: %{"kind" => "provider_account_grant_registry"},
      actor_document: actor,
      current_document: %{
        "grant_version" => grant.version,
        "account_version" => grant.provider_account_version,
        "lifecycle_state" => Atom.to_string(grant.lifecycle_state),
        "restrictions" => grant.restrictions
      }
    })
  end

  defp latest_row(organization_id, provider_account_grant_id) do
    ProviderAccountGrantRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_account_grant_id == ^provider_account_grant_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp actor_document(%Scope{user: %{user_id: user_id}}), do: %{"kind" => "user", "id" => user_id}

  defp actor_document(%Scope{service_identity: %{service_identity_id: id}}),
    do: %{"kind" => "service", "id" => id}

  defp actor_document(_scope), do: %{"kind" => "system"}
  defp actor_id(scope), do: actor_document(scope)["id"]
  defp text_reason(reason) when is_binary(reason) and reason != "", do: reason
  defp text_reason(_reason), do: "revoked"

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
