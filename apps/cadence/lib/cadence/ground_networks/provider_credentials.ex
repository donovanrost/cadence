defmodule Cadence.GroundNetworks.ProviderCredentials do
  @moduledoc "Organization and Provider Account-scoped credential lifecycle registry."

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.GroundNetworks.{ProviderAudit, ProviderAuditEntry, ProviderCredential}
  alias Cadence.Persistence.Schemas.ProviderCredentialRow
  alias Cadence.Repo
  alias Cadence.Secrets.{EnvBackend, ExternalBackend, ResolvedSecret, Resolver}

  @spec create(binary(), binary(), map(), keyword()) ::
          {:ok, ProviderCredential.t()} | {:error, term()}
  def create(organization_id, provider_account_id, attrs, opts \\ [])
      when is_binary(organization_id) and is_binary(provider_account_id) and is_map(attrs) and
             is_list(opts) do
    attrs =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:provider_account_id, provider_account_id)

    with {:ok, credential} <- build_credential(attrs),
         {:ok, backend_metadata} <- maybe_mutate_backend(:create, credential, opts) do
      credential = maybe_put_backend_reference(credential, backend_metadata)
      audit_entry = audit_entry(credential, :created, :succeeded, backend_metadata, opts)

      Multi.new()
      |> Multi.insert(:credential, ProviderCredentialRow.changeset(credential))
      |> ProviderAudit.put_entry(:audit_entry, audit_entry)
      |> Repo.transaction()
      |> unwrap_create()
    else
      {:error, reason} -> audit_failed_create(attrs, reason, opts)
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, ProviderCredential.t()} | {:error, :provider_credential_not_found}
  def fetch(organization_id, provider_account_id, provider_credential_ref)
      when is_binary(organization_id) and is_binary(provider_account_id) and
             is_binary(provider_credential_ref) do
    ProviderCredentialRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_account_id == ^provider_account_id and
        row.provider_credential_ref == ^provider_credential_ref
    )
    |> Repo.one()
    |> row_result()
  end

  @doc "Internal stable-reference lookup for provider runtime calls."
  @spec fetch_registered(binary()) ::
          {:ok, ProviderCredential.t()} | {:error, :provider_credential_not_found}
  def fetch_registered(provider_credential_ref) when is_binary(provider_credential_ref) do
    ProviderCredentialRow
    |> Repo.get(provider_credential_ref)
    |> row_result()
  end

  @spec list(binary(), binary(), keyword()) :: [ProviderCredential.t()]
  def list(organization_id, provider_account_id, opts \\ [])
      when is_binary(organization_id) and is_binary(provider_account_id) and is_list(opts) do
    ProviderCredentialRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_account_id == ^provider_account_id
    )
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> order_by([row], asc: row.provider_credential_ref)
    |> Repo.all()
    |> Enum.map(&ProviderCredentialRow.to_domain/1)
  end

  @spec resolve(binary(), binary(), binary(), keyword()) ::
          {:ok, ResolvedSecret.t()} | {:error, term()}
  def resolve(organization_id, provider_account_id, provider_credential_ref, opts \\ []) do
    with {:ok, credential} <- fetch(organization_id, provider_account_id, provider_credential_ref) do
      do_resolve(credential, opts)
    end
  end

  @doc "Resolves a globally unique registry reference for an internal provider request."
  @spec resolve_registered(binary(), keyword()) :: {:ok, ResolvedSecret.t()} | {:error, term()}
  def resolve_registered(provider_credential_ref, opts \\ []) do
    with {:ok, credential} <- fetch_registered(provider_credential_ref) do
      do_resolve(credential, opts)
    end
  end

  @spec rotate(binary(), binary(), binary(), keyword()) ::
          {:ok, ProviderCredential.t()} | {:error, term()}
  def rotate(organization_id, provider_account_id, provider_credential_ref, opts \\ []) do
    case fetch(organization_id, provider_account_id, provider_credential_ref) do
      {:ok, credential} -> rotate_credential(credential, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec revoke(binary(), binary(), binary(), keyword()) ::
          {:ok, ProviderCredential.t()} | {:error, term()}
  def revoke(organization_id, provider_account_id, provider_credential_ref, opts \\ []) do
    case fetch(organization_id, provider_account_id, provider_credential_ref) do
      {:ok, credential} -> revoke_credential(credential, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp rotate_credential(credential, opts) do
    with :ok <- ensure_active(credential),
         {:ok, backend_metadata} <- maybe_mutate_backend(:rotate, credential, opts) do
      updated = %ProviderCredential{
        credential
        | registry_version: credential.registry_version + 1,
          backend_reference:
            Map.get(backend_metadata, :backend_reference, credential.backend_reference),
          last_rotated_at: now(opts)
      }

      persist_mutation(credential, updated, :rotated, backend_metadata, opts)
    else
      {:error, reason} -> audit_failure(credential, :rotation_failed, reason, opts)
    end
  end

  defp revoke_credential(credential, opts) do
    with :ok <- ensure_active(credential),
         {:ok, backend_metadata} <- maybe_mutate_backend(:revoke, credential, opts) do
      updated = %ProviderCredential{
        credential
        | status: :revoked,
          registry_version: credential.registry_version + 1,
          revoked_at: now(opts)
      }

      persist_mutation(credential, updated, :revoked, backend_metadata, opts)
    else
      {:error, reason} -> audit_failure(credential, :revocation_failed, reason, opts)
    end
  end

  defp do_resolve(%ProviderCredential{} = credential, opts) do
    with :ok <- ensure_active(credential),
         {:ok, resolved} <- Resolver.resolve(credential, secret_opts(credential, opts)) do
      updated = %ProviderCredential{credential | last_resolved_at: now(opts)}

      backend_metadata = %{
        backend_version: resolved.backend_version,
        fingerprint: resolved.fingerprint,
        expires_at: resolved.expires_at
      }

      case persist_mutation(credential, updated, :resolved, backend_metadata, opts) do
        {:ok, _updated} -> {:ok, resolved}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> audit_failure(credential, :resolution_failed, reason, opts)
    end
  end

  defp persist_mutation(current, updated, operation, backend_metadata, opts) do
    audit_entry = audit_entry(updated, operation, :succeeded, backend_metadata, opts)

    Multi.new()
    |> Multi.update(:credential, ProviderCredentialRow.changeset(row_for(current), updated))
    |> ProviderAudit.put_entry(:audit_entry, audit_entry)
    |> Repo.transaction()
    |> case do
      {:ok, %{credential: row}} -> {:ok, ProviderCredentialRow.to_domain(row)}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  defp maybe_mutate_backend(operation, credential, opts) do
    if manage_backend?(credential, opts),
      do: Resolver.mutate(operation, credential, secret_opts(credential, opts)),
      else: {:ok, %{}}
  end

  defp manage_backend?(credential, opts) do
    Keyword.get(opts, :manage_backend?, credential.backend_type == :external)
  end

  defp secret_opts(credential, opts) do
    if Resolver.configured?(opts),
      do: opts,
      else: Keyword.put(opts, :secret_backend, backend_module(credential.backend_type))
  end

  defp backend_module(:env), do: EnvBackend
  defp backend_module(:external), do: ExternalBackend

  defp ensure_active(%ProviderCredential{status: :active}), do: :ok
  defp ensure_active(%ProviderCredential{}), do: {:error, :provider_credential_revoked}

  defp audit_entry(credential, operation, outcome, backend_metadata, opts) do
    ProviderAuditEntry.new(%{
      organization_id: credential.organization_id,
      provider_account_id: credential.provider_account_id,
      action: "provider_credential.#{operation}",
      outcome: Atom.to_string(outcome),
      recorded_at: now(opts),
      credential_ref: credential.provider_credential_ref,
      credential_registry_version: credential.registry_version,
      credential_backend_version: text_value(Map.get(backend_metadata, :backend_version)),
      source_document: %{
        "kind" => "provider_credential_registry",
        "backend_type" => Atom.to_string(credential.backend_type)
      },
      actor_document: Keyword.get(opts, :actor, %{"kind" => "system"}),
      current_document: %{
        "status" => Atom.to_string(credential.status),
        "registry_version" => credential.registry_version,
        "backend_fingerprint" => Map.get(backend_metadata, :fingerprint),
        "backend_expires_at" => Map.get(backend_metadata, :expires_at),
        "failure_reason" => Map.get(backend_metadata, :failure_reason)
      }
    })
  end

  defp audit_failure(credential, operation, reason, opts) do
    credential
    |> audit_entry(operation, :failed, %{failure_reason: redacted_reason(reason)}, opts)
    |> ProviderAudit.append()
    |> case do
      {:ok, _entry} -> {:error, reason}
      {:error, audit_reason} -> {:error, {:provider_credential_audit_failed, audit_reason}}
    end
  end

  defp audit_failed_create(attrs, reason, opts) do
    case build_credential(attrs) do
      {:ok, credential} -> audit_failure(credential, :creation_failed, reason, opts)
      {:error, _invalid} -> {:error, reason}
    end
  end

  defp maybe_put_backend_reference(%ProviderCredential{} = credential, backend_metadata) do
    case Map.get(backend_metadata, :backend_reference) do
      reference when is_binary(reference) and reference != "" ->
        %ProviderCredential{credential | backend_reference: reference}

      _missing ->
        credential
    end
  end

  defp unwrap_create({:ok, %{credential: row}}),
    do: {:ok, ProviderCredentialRow.to_domain(row)}

  defp unwrap_create({:error, _operation, reason, _changes}), do: {:error, reason}

  defp row_for(%ProviderCredential{provider_credential_ref: reference}) do
    Repo.get!(ProviderCredentialRow, reference)
  end

  defp row_result(nil), do: {:error, :provider_credential_not_found}
  defp row_result(row), do: {:ok, ProviderCredentialRow.to_domain(row)}

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_atom(status),
    do: maybe_filter_status(query, Atom.to_string(status))

  defp maybe_filter_status(query, status) when is_binary(status),
    do: where(query, [row], row.status == ^status)

  defp build_credential(attrs) do
    {:ok, ProviderCredential.new(attrs)}
  rescue
    error in ArgumentError -> {:error, {:invalid_provider_credential, Exception.message(error)}}
  end

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp text_value(nil), do: nil
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)

  defp redacted_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp redacted_reason(reason) when is_integer(reason), do: reason
  defp redacted_reason(reason) when is_binary(reason), do: "backend_error"

  defp redacted_reason(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.map(&redacted_reason/1)
  end

  defp redacted_reason(_reason), do: "backend_error"
end
