defmodule Cadence.Dashboards.SourceCredentials do
  @moduledoc """
  Durable registry for dashboard source credential references.

  This context manages non-secret references only. It records lifecycle events
  and resolves a reference to a descriptor adapters can use to ask a future
  secret-management subsystem for material under authz/audit controls.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Dashboards.{
    ResolvedSourceCredential,
    SourceCredentialEvent,
    SourceCredentialMaterial,
    SourceCredentialReference
  }

  alias Cadence.Dashboards.SourceCredentials.SecretMaterialResolver
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Persistence.Schemas.{
    DashboardSourceCredentialEventRow,
    DashboardSourceCredentialReferenceRow
  }

  alias Cadence.Repo

  @type write_result ::
          {:ok, SourceCredentialReference.t(), SourceCredentialEvent.t()} | {:error, term()}

  @spec register_reference(map(), keyword()) :: write_result()
  def register_reference(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    reference =
      attrs
      |> Map.put_new(:status, :active)
      |> Map.put_new(:credential_version, 1)
      |> SourceCredentialReference.new()

    event = reference_event(reference, nil, :registered, occurred_at, attrs, opts)
    reference = %{reference | current_event_id: event.source_credential_event_id}

    Repo.transaction(fn ->
      with {:ok, reference_row} <-
             reference
             |> DashboardSourceCredentialReferenceRow.changeset()
             |> Repo.insert(),
           {:ok, event_row} <-
             event
             |> DashboardSourceCredentialEventRow.changeset()
             |> Repo.insert() do
        {DashboardSourceCredentialReferenceRow.to_domain(reference_row),
         DashboardSourceCredentialEventRow.to_domain(event_row)}
      else
        {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> unwrap_transaction()
  end

  @spec rotate_reference(binary(), map(), keyword()) :: write_result()
  def rotate_reference(credentials_ref, attrs \\ %{}, opts \\ [])
      when is_binary(credentials_ref) and is_map(attrs) and is_list(opts) do
    mutate_reference(credentials_ref, :rotated, attrs, opts, fn
      %SourceCredentialReference{} = current, occurred_at ->
        %SourceCredentialReference{
          current
          | status: :active,
            credential_version: current.credential_version + 1,
            provider: get_attr(attrs, :provider, current.provider),
            data_source_id: get_attr(attrs, :data_source_id, current.data_source_id),
            metadata: merge_metadata(current.metadata, get_attr(attrs, :metadata)),
            last_rotated_at: occurred_at,
            disabled_at: nil
        }
    end)
  end

  @spec disable_reference(binary(), map(), keyword()) :: write_result()
  def disable_reference(credentials_ref, attrs \\ %{}, opts \\ [])
      when is_binary(credentials_ref) and is_map(attrs) and is_list(opts) do
    mutate_reference(credentials_ref, :disabled, attrs, opts, fn
      %SourceCredentialReference{} = current, occurred_at ->
        %SourceCredentialReference{current | status: :disabled, disabled_at: occurred_at}
    end)
  end

  @spec enable_reference(binary(), map(), keyword()) :: write_result()
  def enable_reference(credentials_ref, attrs \\ %{}, opts \\ [])
      when is_binary(credentials_ref) and is_map(attrs) and is_list(opts) do
    mutate_reference(credentials_ref, :enabled, attrs, opts, fn
      %SourceCredentialReference{} = current, _occurred_at ->
        %SourceCredentialReference{current | status: :active, disabled_at: nil}
    end)
  end

  @spec fetch_reference(binary()) ::
          {:ok, SourceCredentialReference.t()} | {:error, :credential_reference_not_found}
  def fetch_reference(credentials_ref) when is_binary(credentials_ref) do
    case Repo.get(DashboardSourceCredentialReferenceRow, credentials_ref) do
      nil -> {:error, :credential_reference_not_found}
      row -> {:ok, DashboardSourceCredentialReferenceRow.to_domain(row)}
    end
  end

  @spec resolve(binary(), keyword()) ::
          {:ok, ResolvedSourceCredential.t()}
          | {:error,
             :credential_reference_not_found | :credential_disabled | :credential_scope_mismatch}
  def resolve(credentials_ref, opts \\ []) when is_binary(credentials_ref) and is_list(opts) do
    with {:ok, %SourceCredentialReference{} = reference} <- fetch_reference(credentials_ref),
         :ok <- ensure_active(reference),
         :ok <- ensure_scope(reference, opts) do
      {:ok, ResolvedSourceCredential.from_reference(reference)}
    end
  end

  @spec resolve_material(binary(), keyword()) ::
          {:ok, SourceCredentialMaterial.t()}
          | {:error,
             :credential_reference_not_found
             | :credential_disabled
             | :credential_scope_mismatch
             | {:credential_material_authorization_denied, term()}
             | :credential_material_resolver_not_configured
             | {:credential_material_resolution_failed, term()}}
  def resolve_material(credentials_ref, opts \\ [])
      when is_binary(credentials_ref) and is_list(opts) do
    with {:ok, %ResolvedSourceCredential{} = credential} <- resolve(credentials_ref, opts) do
      result =
        with :ok <- authorize_material_resolution(credential, opts),
             {:ok, material} <- resolve_secret_material(credential, opts) do
          {:ok, SourceCredentialMaterial.new(credential, material)}
        else
          {:error, reason} -> {:error, reason}
        end

      with :ok <- audit_material_resolution(credential, result, opts) do
        result
      end
    end
  end

  @spec list_references(binary(), binary() | nil, keyword()) :: [SourceCredentialReference.t()]
  def list_references(organization_id, mission_id \\ nil, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    DashboardSourceCredentialReferenceRow
    |> where([row], row.organization_id == ^organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter(:status, Keyword.get(opts, :status))
    |> maybe_filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> order_by([row], asc: row.credentials_ref)
    |> Repo.all()
    |> Enum.map(&DashboardSourceCredentialReferenceRow.to_domain/1)
  end

  @spec list_events(binary(), keyword()) :: [SourceCredentialEvent.t()]
  def list_events(credentials_ref, opts \\ [])
      when is_binary(credentials_ref) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    DashboardSourceCredentialEventRow
    |> where([row], row.credentials_ref == ^credentials_ref)
    |> order_by([row], desc: row.occurred_at, desc: row.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&DashboardSourceCredentialEventRow.to_domain/1)
  end

  defp mutate_reference(credentials_ref, event_type, attrs, opts, update_fun) do
    occurred_at = occurred_at(attrs, opts)

    Repo.transaction(fn ->
      case Repo.get(DashboardSourceCredentialReferenceRow, credentials_ref) do
        nil ->
          Repo.rollback(:credential_reference_not_found)

        row ->
          mutate_reference_row(row, event_type, attrs, opts, occurred_at, update_fun)
      end
    end)
    |> unwrap_transaction()
  end

  defp mutate_reference_row(row, event_type, attrs, opts, occurred_at, update_fun) do
    current = DashboardSourceCredentialReferenceRow.to_domain(row)
    updated = update_fun.(current, occurred_at)
    event = reference_event(updated, current, event_type, occurred_at, attrs, opts)
    updated = %{updated | current_event_id: event.source_credential_event_id}

    with {:ok, updated_row} <-
           row
           |> DashboardSourceCredentialReferenceRow.changeset(updated)
           |> Repo.update(),
         {:ok, event_row} <-
           event
           |> DashboardSourceCredentialEventRow.changeset()
           |> Repo.insert() do
      {DashboardSourceCredentialReferenceRow.to_domain(updated_row),
       DashboardSourceCredentialEventRow.to_domain(event_row)}
    else
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reference_event(
         %SourceCredentialReference{} = reference,
         previous,
         event_type,
         %DateTime{} = occurred_at,
         attrs,
         opts
       ) do
    SourceCredentialEvent.new(%{
      credentials_ref: reference.credentials_ref,
      organization_id: reference.organization_id,
      mission_id: reference.mission_id,
      data_source_id: reference.data_source_id,
      event_type: event_type,
      previous_status: previous && previous.status,
      current_status: reference.status,
      previous_credential_version: previous && previous.credential_version,
      current_credential_version: reference.credential_version,
      actor_id: Keyword.get(opts, :actor_id) || get_attr(attrs, :actor_id),
      occurred_at: occurred_at,
      payload: get_attr(attrs, :payload, %{})
    })
  end

  defp ensure_active(%SourceCredentialReference{status: :active}), do: :ok
  defp ensure_active(%SourceCredentialReference{}), do: {:error, :credential_disabled}

  defp ensure_scope(%SourceCredentialReference{} = reference, opts) do
    with :ok <- ensure_scope_value(reference.organization_id, Keyword.get(opts, :organization_id)),
         :ok <- ensure_optional_scope_value(reference.mission_id, Keyword.get(opts, :mission_id)),
         :ok <-
           ensure_optional_scope_value(
             reference.data_source_id,
             Keyword.get(opts, :data_source_id)
           ) do
      :ok
    else
      :error -> {:error, :credential_scope_mismatch}
    end
  end

  defp ensure_scope_value(_stored, nil), do: :ok
  defp ensure_scope_value(stored, requested) when stored == requested, do: :ok
  defp ensure_scope_value(_stored, _requested), do: :error

  defp ensure_optional_scope_value(nil, _requested), do: :ok
  defp ensure_optional_scope_value(_stored, nil), do: :ok
  defp ensure_optional_scope_value(stored, requested) when stored == requested, do: :ok
  defp ensure_optional_scope_value(_stored, _requested), do: :error

  defp resolve_secret_material(%ResolvedSourceCredential{} = credential, opts) do
    case material_resolver(opts) do
      nil ->
        {:error, :credential_material_resolver_not_configured}

      resolver ->
        credential
        |> call_material_resolver(opts, resolver)
        |> normalize_material_result()
    end
  end

  defp authorize_material_resolution(%ResolvedSourceCredential{} = credential, opts) do
    case material_authorizer(opts) do
      nil ->
        # authz pending: replace default allow with RBAC-backed material-read permission checks.
        :ok

      authorizer ->
        credential
        |> call_material_authorizer(opts, authorizer)
        |> normalize_material_authorization_result()
    end
  end

  defp audit_material_resolution(credential, result, opts) do
    if Keyword.get(opts, :audit_material_resolution?, true) do
      do_audit_material_resolution(credential, result, opts)
    else
      :ok
    end
  end

  defp do_audit_material_resolution(%ResolvedSourceCredential{} = credential, result, opts) do
    case material_audit_mission_id(credential, opts) do
      nil ->
        :ok

      mission_id ->
        credential
        |> material_resolution_event(result, mission_id, opts)
        |> OperationalEvents.persist_event()
        |> case do
          {:ok, _event} -> :ok
          {:error, reason} -> {:error, {:credential_material_audit_failed, reason}}
        end
    end
  end

  defp material_resolution_event(
         %ResolvedSourceCredential{} = credential,
         result,
         mission_id,
         opts
       ) do
    occurred_at =
      Keyword.get(opts, :occurred_at, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

    resolution_id = material_resolution_id(opts)
    {kind, severity} = material_resolution_kind(result)

    OperationalEvent.new(%{
      event_id: "operational_event:source_credential_material_resolution:#{resolution_id}",
      organization_id: credential.organization_id || Keyword.get(opts, :organization_id),
      mission_id: mission_id,
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :security,
      kind: kind,
      severity: severity,
      actor: material_resolution_actor(opts),
      subject: %{kind: :source_credential, id: credential.credentials_ref},
      scope: %{
        data_source_id: credential.data_source_id || Keyword.get(opts, :data_source_id)
      },
      causality: %{
        correlation_id: credential.credentials_ref
      },
      payload:
        credential
        |> material_resolution_payload(result, opts)
        |> Map.put(:credential_material_resolution_id, resolution_id),
      current: material_resolution_current(result),
      metadata: %{
        resolver: material_resolver_identity(material_resolver(opts)),
        authorizer: material_authorizer_identity(material_authorizer(opts)),
        audit_policy: :credential_material_resolution
      }
    })
  end

  defp material_audit_mission_id(%ResolvedSourceCredential{} = credential, opts) do
    credential.mission_id || Keyword.get(opts, :mission_id)
  end

  defp material_resolution_id(opts) do
    Keyword.get(opts, :credential_material_resolution_id) ||
      "credential_material_resolution_#{System.unique_integer([:positive])}"
  end

  defp material_resolution_kind({:ok, %SourceCredentialMaterial{}}),
    do: {:source_credential_material_resolved, :info}

  defp material_resolution_kind({:error, {:credential_material_authorization_denied, _reason}}),
    do: {:source_credential_material_resolution_denied, :warning}

  defp material_resolution_kind({:error, _reason}),
    do: {:source_credential_material_resolution_failed, :warning}

  defp material_resolution_actor(opts) do
    actor_id = Keyword.get(opts, :actor_id)
    actor_kind = Keyword.get(opts, :actor_kind, if(actor_id, do: :user, else: :system))

    case actor_id do
      actor_id when is_binary(actor_id) and actor_id != "" -> %{kind: actor_kind, id: actor_id}
      _other -> %{kind: actor_kind}
    end
  end

  defp material_resolution_payload(
         %ResolvedSourceCredential{} = credential,
         {:ok, %SourceCredentialMaterial{} = material},
         opts
       ) do
    Map.merge(credential_audit_payload(credential, opts), %{
      resolution_result: :succeeded,
      material_fields: material_fields(material),
      secret_material_fields: secret_material_fields(material)
    })
  end

  defp material_resolution_payload(
         %ResolvedSourceCredential{} = credential,
         {:error, {:credential_material_authorization_denied, reason}},
         opts
       ) do
    Map.merge(credential_audit_payload(credential, opts), %{
      resolution_result: :denied,
      authorization_result: :denied,
      denial_reason: redacted_reason(reason)
    })
  end

  defp material_resolution_payload(
         %ResolvedSourceCredential{} = credential,
         {:error, reason},
         opts
       ) do
    Map.merge(credential_audit_payload(credential, opts), %{
      resolution_result: :failed,
      failure_reason: redacted_reason(reason)
    })
  end

  defp credential_audit_payload(%ResolvedSourceCredential{} = credential, opts) do
    %{
      credentials_ref: credential.credentials_ref,
      credential_provider: credential.provider,
      credential_kind: credential.kind,
      credential_owner: credential.owner,
      credential_version: credential.credential_version,
      credential_event_id: credential.current_event_id,
      organization_id: credential.organization_id || Keyword.get(opts, :organization_id),
      mission_id: credential.mission_id || Keyword.get(opts, :mission_id),
      data_source_id: credential.data_source_id || Keyword.get(opts, :data_source_id),
      resolver: material_resolver_identity(material_resolver(opts)),
      authorizer: material_authorizer_identity(material_authorizer(opts))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp material_resolution_current({:ok, %SourceCredentialMaterial{} = material}) do
    %{
      resolution_result: :succeeded,
      material_fields: material_fields(material),
      secret_material_fields: secret_material_fields(material)
    }
  end

  defp material_resolution_current({:error, {:credential_material_authorization_denied, reason}}) do
    %{
      resolution_result: :denied,
      authorization_result: :denied,
      denial_reason: redacted_reason(reason)
    }
  end

  defp material_resolution_current({:error, reason}) do
    %{resolution_result: :failed, failure_reason: redacted_reason(reason)}
  end

  defp material_fields(%SourceCredentialMaterial{material: material}) do
    material
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end

  defp secret_material_fields(%SourceCredentialMaterial{material: material}) do
    [:username, :password, :bearer_token, :headers]
    |> Enum.filter(&Map.has_key?(material, &1))
    |> Enum.map(&Atom.to_string/1)
  end

  defp redacted_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp redacted_reason(reason) when is_binary(reason), do: "resolver_error"

  defp redacted_reason({:credential_material_resolution_failed, reason}),
    do: redacted_reason(reason)

  defp redacted_reason({:credential_material_authorization_denied, reason}),
    do: redacted_reason(reason)

  defp redacted_reason(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.map(&redacted_reason/1)
  end

  defp redacted_reason(reason) when is_list(reason), do: Enum.map(reason, &redacted_reason/1)
  defp redacted_reason(reason) when is_map(reason), do: "resolver_error"
  defp redacted_reason(_reason), do: "resolver_error"

  defp material_resolver_identity(nil), do: nil
  defp material_resolver_identity({module, function}), do: "#{inspect(module)}.#{function}/2"

  defp material_resolver_identity({module, function, extra_args}) when is_list(extra_args),
    do: "#{inspect(module)}.#{function}/#{2 + length(extra_args)}"

  defp material_resolver_identity(resolver) when is_function(resolver) do
    {:arity, arity} = Function.info(resolver, :arity)
    "anonymous/#{arity}"
  end

  defp material_resolver_identity(resolver), do: inspect(resolver)

  defp material_authorizer_identity(nil), do: nil
  defp material_authorizer_identity({module, function}), do: "#{inspect(module)}.#{function}/2"

  defp material_authorizer_identity({module, function, extra_args}) when is_list(extra_args),
    do: "#{inspect(module)}.#{function}/#{2 + length(extra_args)}"

  defp material_authorizer_identity(authorizer) when is_function(authorizer) do
    {:arity, arity} = Function.info(authorizer, :arity)
    "anonymous/#{arity}"
  end

  defp material_authorizer_identity(authorizer), do: inspect(authorizer)

  defp material_resolver(opts) do
    configured = Application.get_env(:cadence, :dashboard_source_credentials, [])

    Keyword.get(opts, :credential_material_resolver) ||
      Keyword.get(configured, :material_resolver) ||
      default_secret_material_resolver(opts, configured)
  end

  defp default_secret_material_resolver(opts, configured) do
    if secret_backend_configured?(opts, configured) do
      {SecretMaterialResolver, :resolve}
    end
  end

  defp secret_backend_configured?(opts, configured) do
    Keyword.has_key?(opts, :credential_secret_backend) ||
      Keyword.has_key?(opts, :secret_backend) ||
      Keyword.has_key?(configured, :secret_backend)
  end

  defp material_authorizer(opts) do
    Keyword.get(opts, :credential_material_authorizer) ||
      :cadence
      |> Application.get_env(:dashboard_source_credentials, [])
      |> Keyword.get(:material_authorizer)
  end

  defp call_material_resolver(%ResolvedSourceCredential{} = credential, opts, resolver)
       when is_function(resolver, 2) do
    resolver.(credential, opts)
  end

  defp call_material_resolver(%ResolvedSourceCredential{} = credential, _opts, resolver)
       when is_function(resolver, 1) do
    resolver.(credential)
  end

  defp call_material_resolver(%ResolvedSourceCredential{} = credential, opts, {module, function})
       when is_atom(module) and is_atom(function) do
    apply(module, function, [credential, opts])
  end

  defp call_material_resolver(
         %ResolvedSourceCredential{} = credential,
         opts,
         {module, function, extra_args}
       )
       when is_atom(module) and is_atom(function) and is_list(extra_args) do
    apply(module, function, [credential, opts | extra_args])
  end

  defp call_material_resolver(_credential, _opts, resolver) do
    {:error, {:unsupported_credential_material_resolver, resolver}}
  end

  defp call_material_authorizer(%ResolvedSourceCredential{} = credential, opts, authorizer)
       when is_function(authorizer, 2) do
    authorizer.(credential, opts)
  end

  defp call_material_authorizer(%ResolvedSourceCredential{} = credential, _opts, authorizer)
       when is_function(authorizer, 1) do
    authorizer.(credential)
  end

  defp call_material_authorizer(
         %ResolvedSourceCredential{} = credential,
         opts,
         {module, function}
       )
       when is_atom(module) and is_atom(function) do
    apply(module, function, [credential, opts])
  end

  defp call_material_authorizer(
         %ResolvedSourceCredential{} = credential,
         opts,
         {module, function, extra_args}
       )
       when is_atom(module) and is_atom(function) and is_list(extra_args) do
    apply(module, function, [credential, opts | extra_args])
  end

  defp call_material_authorizer(_credential, _opts, authorizer) do
    {:error, {:unsupported_credential_material_authorizer, authorizer}}
  end

  defp normalize_material_authorization_result(:ok), do: :ok
  defp normalize_material_authorization_result({:ok, _context}), do: :ok
  defp normalize_material_authorization_result(true), do: :ok

  defp normalize_material_authorization_result(:deny),
    do: {:error, {:credential_material_authorization_denied, :denied}}

  defp normalize_material_authorization_result(false),
    do: {:error, {:credential_material_authorization_denied, :denied}}

  defp normalize_material_authorization_result({:deny, reason}),
    do: {:error, {:credential_material_authorization_denied, reason}}

  defp normalize_material_authorization_result({:error, reason}),
    do: {:error, {:credential_material_authorization_denied, reason}}

  defp normalize_material_authorization_result(other),
    do: {:error, {:credential_material_authorization_denied, other}}

  defp normalize_material_result({:ok, material}) when is_map(material), do: {:ok, material}

  defp normalize_material_result(%SourceCredentialMaterial{material: material})
       when is_map(material),
       do: {:ok, material}

  defp normalize_material_result(material) when is_map(material), do: {:ok, material}

  defp normalize_material_result({:error, reason}),
    do: {:error, {:credential_material_resolution_failed, reason}}

  defp normalize_material_result(other),
    do: {:error, {:credential_material_resolution_failed, other}}

  defp maybe_scope_mission(query, nil), do: query

  defp maybe_scope_mission(query, mission_id),
    do: where(query, [row], row.mission_id == ^mission_id)

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    value = enum_string(value)
    where(query, [row], field(row, ^field) == ^value)
  end

  defp merge_metadata(metadata, nil), do: metadata

  defp merge_metadata(metadata, patch) when is_map(metadata) and is_map(patch),
    do: Map.merge(metadata, patch)

  defp merge_metadata(_metadata, patch) when is_map(patch), do: patch
  defp merge_metadata(metadata, _patch), do: metadata

  defp occurred_at(attrs, opts) do
    attrs
    |> get_attr(:occurred_at, Keyword.get(opts, :occurred_at, DateTime.utc_now()))
    |> DateTime.truncate(:microsecond)
  end

  defp unwrap_transaction({:ok, {reference, event}}), do: {:ok, reference, event}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
