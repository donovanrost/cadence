defmodule Cadence.GroundNetworks.ProviderAccounts do
  @moduledoc "Authorized organization Provider Account and immutable version registry."

  import Ecto.Query
  alias Ecto.Multi

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.GroundNetworks.{
    ProviderAccount,
    ProviderAccountVersion,
    ProviderAudit,
    ProviderAuditEntry,
    ProviderCredentials
  }

  alias Cadence.Persistence.Schemas.{ProviderAccountRow, ProviderAccountVersionRow}
  alias Cadence.Repo

  @spec create(Scope.t(), map(), keyword()) ::
          {:ok, ProviderAccount.t(), ProviderAccountVersion.t()} | {:error, term()}
  def create(%Scope{} = current_scope, attrs, opts \\ []) when is_map(attrs) do
    organization_id = current_scope.organization_id

    with :ok <-
           Policy.authorize(current_scope, :manage_provider_accounts, %{
             organization_id: organization_id
           }) do
      create_for_system(organization_id, attrs, actor_document(current_scope), opts)
    end
  end

  @spec create_for_system(binary(), map(), map(), keyword()) ::
          {:ok, ProviderAccount.t(), ProviderAccountVersion.t()} | {:error, term()}
  def create_for_system(organization_id, attrs, actor, opts \\ [])
      when is_binary(organization_id) and is_map(attrs) and is_map(actor) do
    with {:ok, account, version} <- build_account(organization_id, attrs),
         :ok <- validate_version(version),
         :ok <- validate_credential(version, opts) do
      audit = account_audit(account, version, "provider_account.created", actor, opts)

      Multi.new()
      |> Multi.insert(:account, ProviderAccountRow.changeset(account))
      |> Multi.insert(:version, ProviderAccountVersionRow.changeset(version))
      |> ProviderAudit.put_entry(:audit_entry, audit)
      |> Repo.transaction()
      |> unwrap_create()
    end
  end

  @spec version(Scope.t(), binary(), map(), keyword()) ::
          {:ok, ProviderAccount.t(), ProviderAccountVersion.t()} | {:error, term()}
  def version(%Scope{} = current_scope, provider_account_id, attrs, opts \\ []) do
    organization_id = current_scope.organization_id

    with :ok <-
           Policy.authorize(current_scope, :manage_provider_accounts, %{
             organization_id: organization_id
           }),
         {:ok, %ProviderAccount{} = account, current} <-
           fetch_for_system(organization_id, provider_account_id),
         {:ok, next} <- build_next_version(account, current, attrs, actor_id(current_scope), opts),
         :ok <- validate_version(next),
         :ok <- validate_credential(next, opts) do
      updated_account = %ProviderAccount{account | active_version: next.version}

      audit =
        account_audit(
          updated_account,
          next,
          "provider_account.versioned",
          actor_document(current_scope),
          opts
        )

      Multi.new()
      |> Multi.update(
        :account,
        ProviderAccountRow.changeset(account_row(account), updated_account)
      )
      |> Multi.insert(:version, ProviderAccountVersionRow.changeset(next))
      |> ProviderAudit.put_entry(:audit_entry, audit)
      |> Repo.transaction()
      |> unwrap_create()
    end
  end

  @spec fetch(Scope.t(), binary()) ::
          {:ok, ProviderAccount.t(), ProviderAccountVersion.t()} | {:error, term()}
  def fetch(%Scope{} = current_scope, provider_account_id) do
    with :ok <-
           Policy.authorize(current_scope, :read_organization, %{
             organization_id: current_scope.organization_id
           }) do
      fetch_for_system(current_scope.organization_id, provider_account_id)
    end
  end

  @spec fetch_for_system(binary(), binary()) ::
          {:ok, ProviderAccount.t(), ProviderAccountVersion.t()}
          | {:error, :provider_account_not_found}
  def fetch_for_system(organization_id, provider_account_id) do
    case account_row_query(organization_id, provider_account_id) |> Repo.one() do
      nil ->
        {:error, :provider_account_not_found}

      row ->
        %ProviderAccount{} = account = ProviderAccountRow.to_domain(row)

        with {:ok, version} <-
               fetch_version(organization_id, provider_account_id, account.active_version) do
          {:ok, account, version}
        end
    end
  end

  @spec fetch_version(binary(), binary(), pos_integer()) ::
          {:ok, ProviderAccountVersion.t()} | {:error, :provider_account_version_not_found}
  def fetch_version(organization_id, provider_account_id, version) do
    ProviderAccountVersionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.provider_account_id == ^provider_account_id and
        row.version == ^version
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :provider_account_version_not_found}
      row -> {:ok, ProviderAccountVersionRow.to_domain(row)}
    end
  end

  @spec list(Scope.t()) ::
          {:ok, [{ProviderAccount.t(), ProviderAccountVersion.t()}]} | {:error, term()}
  def list(%Scope{} = current_scope) do
    with :ok <-
           Policy.authorize(current_scope, :read_organization, %{
             organization_id: current_scope.organization_id
           }) do
      {:ok, list_for_system(current_scope.organization_id)}
    end
  end

  def list_for_system(organization_id) do
    ProviderAccountRow
    |> where([row], row.organization_id == ^organization_id and row.lifecycle_state == "active")
    |> order_by([row], asc: row.display_name)
    |> Repo.all()
    |> Enum.flat_map(fn row ->
      account = ProviderAccountRow.to_domain(row)

      case fetch_version(organization_id, account.provider_account_id, account.active_version) do
        {:ok, version} -> [{account, version}]
        {:error, _reason} -> []
      end
    end)
  end

  @doc "Returns exact active account versions whose event mode includes polling."
  @spec list_polling_accounts() :: [{ProviderAccount.t(), ProviderAccountVersion.t()}]
  def list_polling_accounts do
    ProviderAccountRow
    |> join(:inner, [account], version in ProviderAccountVersionRow,
      on:
        version.organization_id == account.organization_id and
          version.provider_account_id == account.provider_account_id and
          version.version == account.active_version
    )
    |> where(
      [account, version],
      account.lifecycle_state == "active" and
        version.event_ingestion_mode in ["polling", "hybrid"]
    )
    |> order_by([account], asc: account.organization_id, asc: account.provider_account_id)
    |> select([account, version], {account, version})
    |> Repo.all()
    |> Enum.map(fn {account, version} ->
      {ProviderAccountRow.to_domain(account), ProviderAccountVersionRow.to_domain(version)}
    end)
  end

  @spec validate(Scope.t(), binary(), keyword()) ::
          {:ok, ProviderAccount.t()} | {:error, term()}
  def validate(%Scope{} = current_scope, provider_account_id, opts \\ []) do
    organization_id = current_scope.organization_id

    with :ok <-
           Policy.authorize(current_scope, :manage_provider_accounts, %{
             organization_id: organization_id
           }),
         {:ok, _account, version} <- fetch_for_system(organization_id, provider_account_id),
         :ok <- validate_credential(version, Keyword.put(opts, :validate_credential?, true)) do
      update_operational_state(
        organization_id,
        provider_account_id,
        %{credential_status: :active, last_validated_at: now(opts)},
        actor_document(current_scope),
        opts
      )
    end
  end

  @spec update_operational_state(binary(), binary(), map(), map(), keyword()) ::
          {:ok, ProviderAccount.t()} | {:error, term()}
  def update_operational_state(organization_id, provider_account_id, attrs, actor, opts \\ [])
      when is_map(actor) do
    case account_row_query(organization_id, provider_account_id) |> Repo.one() do
      nil ->
        {:error, :provider_account_not_found}

      row ->
        %ProviderAccount{} = account = ProviderAccountRow.to_domain(row)

        updated = %ProviderAccount{
          account
          | credential_status: Map.get(attrs, :credential_status, account.credential_status),
            event_ingestion_status:
              Map.get(attrs, :event_ingestion_status, account.event_ingestion_status),
            last_validated_at: Map.get(attrs, :last_validated_at, account.last_validated_at),
            metadata: Map.merge(account.metadata, Map.get(attrs, :metadata, %{}))
        }

        audit =
          account_audit(
            updated,
            active_version!(updated),
            "provider_account.operational_state_updated",
            actor,
            opts
          )

        Multi.new()
        |> Multi.update(:account, ProviderAccountRow.changeset(row, updated))
        |> ProviderAudit.put_entry(:audit_entry, audit)
        |> Repo.transaction()
        |> case do
          {:ok, %{account: persisted}} -> {:ok, ProviderAccountRow.to_domain(persisted)}
          {:error, _operation, reason, _changes} -> {:error, reason}
        end
    end
  end

  defp build_account(organization_id, attrs) do
    account_attrs =
      %{
        organization_id: organization_id,
        display_name: value(attrs, :display_name),
        credential_status: :active,
        event_ingestion_status: :unknown,
        metadata: value(attrs, :metadata, %{})
      }
      |> maybe_put(:provider_account_id, value(attrs, :provider_account_id))

    account = ProviderAccount.new(account_attrs)

    version =
      attrs
      |> Map.put(:provider_account_id, account.provider_account_id)
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:version, 1)
      |> ProviderAccountVersion.new()

    {:ok, account, version}
  rescue
    error in ArgumentError -> {:error, {:invalid_provider_account, Exception.message(error)}}
  end

  defp build_next_version(account, current, attrs, created_by, opts) do
    merged =
      current
      |> Map.from_struct()
      |> merge_version_attrs(attrs)
      |> Map.put(:provider_account_id, account.provider_account_id)
      |> Map.put(:organization_id, account.organization_id)
      |> Map.put(:version, current.version + 1)
      |> Map.put(:created_by, created_by)
      |> Map.put(:created_at, Keyword.get(opts, :now, DateTime.utc_now()))

    {:ok, ProviderAccountVersion.new(merged)}
  rescue
    error in ArgumentError -> {:error, {:invalid_provider_account, Exception.message(error)}}
  end

  defp validate_version(version) do
    case URI.parse(version.base_url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> :ok
      _other -> {:error, :invalid_provider_account_base_url}
    end
  end

  defp validate_credential(version, opts) do
    with {:ok, credential} <-
           ProviderCredentials.fetch(
             version.organization_id,
             version.provider_account_id,
             version.credential_ref
           ),
         true <- credential.status == :active do
      maybe_resolve_credential(version, opts)
    else
      false -> {:error, :provider_account_credential_revoked}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_resolve_credential(version, opts) do
    if Keyword.get(opts, :validate_credential?, true) do
      case ProviderCredentials.resolve(
             version.organization_id,
             version.provider_account_id,
             version.credential_ref,
             opts
           ) do
        {:ok, _resolved} -> :ok
        {:error, reason} -> {:error, {:provider_account_credential_unavailable, reason}}
      end
    else
      :ok
    end
  end

  defp account_audit(account, version, action, actor, opts) do
    ProviderAuditEntry.new(%{
      organization_id: account.organization_id,
      provider_account_id: account.provider_account_id,
      action: action,
      outcome: "succeeded",
      recorded_at: Keyword.get(opts, :now, DateTime.utc_now()),
      credential_ref: version.credential_ref,
      source_document: %{"kind" => "provider_account_registry"},
      actor_document: actor,
      current_document: %{
        "account_version" => version.version,
        "provider_type" => Atom.to_string(version.provider_type),
        "environment_ref" => version.environment_ref
      }
    })
  end

  defp unwrap_create({:ok, %{account: account_row, version: version_row}}) do
    {:ok, ProviderAccountRow.to_domain(account_row),
     ProviderAccountVersionRow.to_domain(version_row)}
  end

  defp unwrap_create({:error, _operation, reason, _changes}), do: {:error, reason}

  defp account_row(account), do: Repo.get!(ProviderAccountRow, account.provider_account_id)

  defp active_version!(account) do
    {:ok, version} =
      fetch_version(account.organization_id, account.provider_account_id, account.active_version)

    version
  end

  defp account_row_query(organization_id, provider_account_id) do
    ProviderAccountRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.provider_account_id == ^provider_account_id
    )
  end

  defp actor_document(%Scope{user: %{user_id: user_id}}), do: %{"kind" => "user", "id" => user_id}

  defp actor_document(%Scope{service_identity: %{service_identity_id: id}}),
    do: %{"kind" => "service", "id" => id}

  defp actor_document(_scope), do: %{"kind" => "system"}

  defp actor_id(scope), do: actor_document(scope)["id"]

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp merge_version_attrs(current, attrs) do
    Enum.reduce(Map.keys(current), current, fn key, merged ->
      cond do
        Map.has_key?(attrs, key) ->
          Map.put(merged, key, Map.fetch!(attrs, key))

        Map.has_key?(attrs, Atom.to_string(key)) ->
          Map.put(merged, key, Map.fetch!(attrs, Atom.to_string(key)))

        true ->
          merged
      end
    end)
  end
end
