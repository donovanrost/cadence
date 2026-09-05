defmodule Cadence.Applications.OpsConsole.Actions.DataSources do
  @moduledoc """
  Exact host actions for the federated Ops data-sources surface.

  The surface id is deliberately separate from the typed action request so the
  final host composer can bind this adapter without changing ActionRequest.
  """

  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.DataSources, as: DataSourceControl
  alias Cadence.Control.ManagedResources
  alias Cadence.DataSources.{AdapterRegistry, DataBinding, DataSource, SourceHealthEvent}
  alias Cadence.ExtensionCatalog
  alias Cadence.Jobs
  alias Cadence.Jobs.Job
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  @surface_ids ["data_source_registration", "data_source_settings"]
  @surface_version 1

  @registration_action_ids ["register-source"]
  @settings_action_ids [
    "change-binding",
    "disable-source",
    "enable-source",
    "reconcile-tsdb-backend",
    "deprovision-tsdb-backend",
    "provision-tsdb-backend",
    "probe-source",
    "rotate-source-credential",
    "retry-deployment-run",
    "requeue-deployment-run"
  ]

  @source_fields [
    "data_source_id",
    "logical_source",
    "kind",
    "isolation_level",
    "credentials_ref",
    "credential_provider",
    "endpoint_ref",
    "material_env_profile",
    "http_endpoint_env",
    "storage"
  ]

  @spec bindings() :: [{binary(), binary()}]
  def bindings,
    do:
      [{"data_source_registration", "register-source"}] ++
        Enum.map(@settings_action_ids, &{"data_source_settings", &1})

  @spec execute(Scope.t(), HostContext.t(), binary(), ActionRequest.t()) ::
          {:ok, term()} | {:error, term()}
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    execute(scope, host_context, request.surface_id, request)
  end

  def execute(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id} = host_context,
        surface_id,
        %ActionRequest{} = request
      )
      when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
             mission_id != "" do
    with :ok <- validate_request(surface_id, host_context, request),
         :ok <- validate_json_params(request.params),
         :ok <- validate_mission_param(mission_id, request.params),
         {:ok, params} <- normalize_params(request.action_id, request.params),
         :ok <- authorize(scope, organization_id, mission_id),
         {:ok, value} <- dispatch(scope, host_context, request, params) do
      {:ok, value}
    end
  end

  def execute(_scope, _host_context, _surface_id, _request),
    do: {:error, :unsupported_application_action}

  @spec result(term()) :: term()
  def result(%DataSource{} = source) do
    %{
      "dataSourceId" => source.data_source_id,
      "organizationId" => source.organization_id,
      "missionId" => source.mission_id,
      "status" => text(source.status),
      "kind" => text(source.kind),
      "isolationLevel" => text(source.isolation_level)
    }
  end

  def result(%DataBinding{} = binding) do
    %{
      "bindingId" => binding.binding_id,
      "dataSourceId" => binding.data_source_id,
      "organizationId" => binding.organization_id,
      "missionId" => binding.mission_id,
      "status" => text(binding.status),
      "bindingVersion" => binding.binding_version
    }
  end

  def result(%{source: source, job: job}) do
    %{"source" => result(source), "job" => result(job)}
  end

  def result(%{reference: reference, event: event}) do
    %{"reference" => result(reference), "eventId" => event_id(event)}
  end

  def result(%Cadence.DataSources.SourceCredentialReference{} = reference) do
    %{
      "credentialsRef" => reference.credentials_ref,
      "organizationId" => reference.organization_id,
      "missionId" => reference.mission_id,
      "dataSourceId" => reference.data_source_id,
      "status" => text(reference.status),
      "credentialVersion" => reference.credential_version
    }
  end

  def result(%Job{} = job) do
    %{
      "jobId" => job.job_id,
      "runId" => job.run_id,
      "missionId" => job.mission_id,
      "status" => text(job.status),
      "attemptCount" => job.attempt_count
    }
  end

  def result(%{run_id: run_id, job_id: job_id} = run) do
    %{
      "jobId" => job_id,
      "runId" => run_id,
      "status" => text(Map.get(run, :status)),
      "statusText" => text(Map.get(run, :status_text)),
      "missionId" => text_or_nil(Map.get(run, :mission_id))
    }
  end

  def result(%{event: event, status: status}) do
    %{"event" => probe_event_result(event), "status" => probe_status_result(status)}
  end

  def result(value) when is_map(value) do
    case JSONBoundary.safe(value) do
      {:ok, safe_value} -> safe_value
      {:error, _reason} -> nil
    end
  end

  def result(_value), do: nil

  defp validate_request(
         surface_id,
         %HostContext{placement: :mission} = host_context,
         %ActionRequest{
           application_key: "ops_console",
           application_version: 1,
           surface_id: surface_id,
           surface_version: @surface_version,
           action_id: action_id,
           params: params
         }
       )
       when is_binary(surface_id) and is_binary(action_id) and is_map(params) do
    if HostContext.valid?(host_context) and valid_binding?(surface_id, action_id) do
      :ok
    else
      {:error, :unsupported_application_action}
    end
  end

  defp validate_request(_surface_id, _host_context, _request),
    do: {:error, :unsupported_application_action}

  defp valid_binding?(surface_id, action_id) when surface_id in @surface_ids do
    case surface_id do
      "data_source_registration" -> action_id in @registration_action_ids
      "data_source_settings" -> action_id in @settings_action_ids
    end
  end

  defp valid_binding?(_surface_id, _action_id), do: false

  defp validate_json_params(params) do
    if JSONBoundary.validate(params) == :ok and string_keyed?(params),
      do: :ok,
      else: {:error, :malformed_action_input}
  end

  defp string_keyed?(value) when is_map(value) do
    Enum.all?(value, fn {key, item} -> is_binary(key) and string_keyed?(item) end)
  end

  defp string_keyed?(value) when is_list(value), do: Enum.all?(value, &string_keyed?/1)
  defp string_keyed?(_value), do: true

  defp validate_mission_param(mission_id, params) do
    case Map.fetch(params, "mission_id") do
      :error -> :ok
      {:ok, ^mission_id} -> :ok
      {:ok, _other} -> {:error, :scope_mismatch}
    end
  end

  defp authorize(scope, organization_id, mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         :ok <- Policy.authorize(scope, :read_organization, %{organization_id: organization_id}) do
      :ok
    end
  end

  defp normalize_params(action_id, params) do
    case action_id do
      "register-source" ->
        normalize_register_source(params)

      "change-binding" ->
        normalize_change_binding(params)

      "rotate-source-credential" ->
        normalize_rotate_credential(params)

      action_id
      when action_id in [
             "disable-source",
             "enable-source",
             "reconcile-tsdb-backend",
             "deprovision-tsdb-backend",
             "provision-tsdb-backend",
             "probe-source"
           ] ->
        normalize_data_source_action(params)

      action_id when action_id in ["retry-deployment-run", "requeue-deployment-run"] ->
        normalize_deployment_action(params)

      _unknown ->
        {:error, :unsupported_application_action}
    end
  end

  defp normalize_register_source(params) do
    with :ok <- exact_keys(params, ["source"], ["mission_id"]),
         {:ok, source_params} <- fetch_map(params, "source"),
         :ok <- exact_keys(source_params, @source_fields, []),
         {:ok, attrs} <- parse_source(source_params) do
      {:ok, %{source: attrs}}
    end
  end

  defp normalize_change_binding(params) do
    with :ok <- exact_keys(params, ["binding"], ["mission_id"]),
         {:ok, binding_params} <- fetch_map(params, "binding"),
         :ok <- exact_keys(binding_params, ["binding_id", "data_source_id"], []),
         {:ok, binding_id} <- required_text(binding_params, "binding_id"),
         {:ok, data_source_id} <- required_text(binding_params, "data_source_id") do
      {:ok, %{binding_id: binding_id, data_source_id: data_source_id}}
    end
  end

  defp normalize_rotate_credential(params) do
    with :ok <- exact_keys(params, ["data-source-id", "credentials-ref"], ["mission_id"]),
         {:ok, data_source_id} <- required_text(params, "data-source-id"),
         {:ok, credentials_ref} <- required_text(params, "credentials-ref") do
      {:ok, %{data_source_id: data_source_id, credentials_ref: credentials_ref}}
    end
  end

  defp normalize_data_source_action(params) do
    with :ok <- exact_keys(params, ["data-source-id"], ["mission_id"]),
         {:ok, data_source_id} <- required_text(params, "data-source-id") do
      {:ok, %{data_source_id: data_source_id}}
    end
  end

  defp normalize_deployment_action(params) do
    with :ok <- exact_keys(params, ["job-id"], ["mission_id"]),
         {:ok, job_id} <- required_text(params, "job-id") do
      {:ok, %{job_id: job_id}}
    end
  end

  defp exact_keys(params, required, optional) do
    keys = Map.keys(params)
    allowed = MapSet.new(required ++ optional)

    if Enum.all?(keys, &is_binary/1) and Enum.all?(keys, &MapSet.member?(allowed, &1)) and
         Enum.all?(required, &Map.has_key?(params, &1)) do
      :ok
    else
      {:error, :malformed_action_input}
    end
  end

  defp fetch_map(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _other -> {:error, :malformed_action_input}
    end
  end

  defp required_text(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :malformed_action_input}
          trimmed -> {:ok, trimmed}
        end

      _other ->
        {:error, :malformed_action_input}
    end
  end

  defp optional_text(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, blank_to_nil(value)}
      _other -> {:error, :malformed_action_input}
    end
  end

  defp parse_source(params) do
    with {:ok, data_source_id} <- required_text(params, "data_source_id"),
         {:ok, logical_source, adapter_definition} <- parse_logical_source(params),
         {:ok, kind} <- parse_source_kind(params),
         {:ok, isolation_level} <- parse_isolation_level(params),
         :ok <- validate_kind_isolation(kind, isolation_level),
         {:ok, storage} <- parse_storage(params),
         {:ok, credentials_ref} <- parse_credentials_ref(params, kind),
         {:ok, credential_provider} <- optional_text(params, "credential_provider"),
         {:ok, endpoint_ref} <- optional_text(params, "endpoint_ref"),
         {:ok, material_env_profile} <- optional_text(params, "material_env_profile"),
         {:ok, http_endpoint_env} <- optional_text(params, "http_endpoint_env") do
      {:ok,
       %{
         data_source_id: data_source_id,
         logical_source: logical_source,
         kind: kind,
         owner: source_owner(kind),
         isolation_level: isolation_level,
         credentials_ref: credentials_ref,
         credential_provider: credential_provider,
         endpoint_ref: endpoint_ref,
         material_env_profile: material_env_profile,
         http_endpoint_env: http_endpoint_env,
         storage: storage,
         adapter_definition: adapter_definition
       }}
    end
  end

  defp parse_logical_source(params) do
    case Map.get(params, "logical_source") do
      value when is_binary(value) ->
        case Enum.find(
               ExtensionCatalog.source_adapters(),
               &(Atom.to_string(&1.logical_source) == value)
             ) do
          nil -> {:error, :malformed_action_input}
          definition -> {:ok, definition.logical_source, definition}
        end

      _other ->
        {:error, :malformed_action_input}
    end
  end

  defp parse_source_kind(params) do
    case Map.get(params, "kind") do
      "byo_tsdb" -> {:ok, :byo_tsdb}
      "managed_tsdb" -> {:ok, :managed_tsdb}
      _other -> {:error, :malformed_action_input}
    end
  end

  defp parse_isolation_level(params) do
    case Map.get(params, "isolation_level") do
      "shared" -> {:ok, :shared}
      "org_isolated" -> {:ok, :org_isolated}
      "mission_isolated" -> {:ok, :mission_isolated}
      "customer_owned" -> {:ok, :customer_owned}
      _other -> {:error, :malformed_action_input}
    end
  end

  defp parse_storage(params) do
    case Map.get(params, "storage") do
      "questdb" -> {:ok, :questdb}
      "postgres_projection" -> {:ok, :postgres_projection}
      _other -> {:error, :malformed_action_input}
    end
  end

  defp parse_credentials_ref(params, :byo_tsdb), do: required_text(params, "credentials_ref")
  defp parse_credentials_ref(params, :managed_tsdb), do: optional_text(params, "credentials_ref")

  defp validate_kind_isolation(:byo_tsdb, isolation_level)
       when isolation_level in [:customer_owned, :org_isolated, :mission_isolated],
       do: :ok

  defp validate_kind_isolation(:byo_tsdb, _isolation_level),
    do: {:error, :malformed_action_input}

  defp validate_kind_isolation(:managed_tsdb, :customer_owned),
    do: {:error, :malformed_action_input}

  defp validate_kind_isolation(:managed_tsdb, _isolation_level), do: :ok

  defp dispatch(scope, host_context, %ActionRequest{action_id: "register-source"} = request, %{
         source: attrs
       }) do
    register_source(scope, host_context, request, attrs)
  end

  defp dispatch(
         scope,
         host_context,
         %ActionRequest{action_id: "change-binding"} = request,
         %{binding_id: binding_id, data_source_id: data_source_id}
       ) do
    change_binding(scope, host_context, request, binding_id, data_source_id)
  end

  defp dispatch(
         scope,
         host_context,
         %ActionRequest{action_id: action_id} = request,
         %{data_source_id: data_source_id}
       )
       when action_id in [
              "disable-source",
              "enable-source",
              "reconcile-tsdb-backend",
              "deprovision-tsdb-backend",
              "provision-tsdb-backend",
              "probe-source"
            ] do
    source_action(scope, host_context, request, data_source_id)
  end

  defp dispatch(
         scope,
         host_context,
         %ActionRequest{action_id: "rotate-source-credential"} = request,
         %{data_source_id: data_source_id, credentials_ref: credentials_ref}
       ) do
    rotate_source_credential(scope, host_context, request, data_source_id, credentials_ref)
  end

  defp dispatch(
         scope,
         host_context,
         %ActionRequest{action_id: action_id} = request,
         %{job_id: job_id}
       )
       when action_id in ["retry-deployment-run", "requeue-deployment-run"] do
    deployment_action(scope, host_context, request, job_id)
  end

  defp dispatch(_scope, _host_context, _request, _params),
    do: {:error, :unsupported_application_action}

  defp register_source(scope, %HostContext{mission_id: mission_id}, request, attrs) do
    organization_id = scope.organization_id
    source = data_source(attrs, organization_id, mission_id)
    payload = action_payload(request)

    with :ok <- maybe_register_credentials(attrs, organization_id, mission_id, payload, scope),
         {:ok, persisted} <-
           DataSources.persist_data_source(source,
             actor_id: actor_id(scope),
             payload: payload
           ) do
      {:ok, persisted}
    end
  end

  defp maybe_register_credentials(
         %{credentials_ref: nil},
         _organization_id,
         _mission_id,
         _payload,
         _scope
       ),
       do: :ok

  defp maybe_register_credentials(attrs, organization_id, mission_id, payload, scope) do
    case SourceCredentials.fetch_reference(attrs.credentials_ref) do
      {:ok, _reference} ->
        :ok

      {:error, :credential_reference_not_found} ->
        credential_attrs = %{
          credentials_ref: attrs.credentials_ref,
          organization_id: organization_id,
          mission_id: mission_id,
          data_source_id: attrs.data_source_id,
          owner: attrs.owner,
          kind: credential_kind(attrs.kind),
          provider: attrs.credential_provider,
          metadata:
            compact(%{
              storage: attrs.storage,
              registered_by: "ops_console_data_sources_action",
              endpoint_ref: attrs.endpoint_ref,
              material_env_profile: attrs.material_env_profile,
              http_endpoint_env: attrs.http_endpoint_env
            }),
          payload: payload
        }

        case SourceCredentials.register_reference(credential_attrs, actor_id: actor_id(scope)) do
          {:ok, _reference, _event} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp change_binding(
         scope,
         %HostContext{mission_id: mission_id},
         request,
         binding_id,
         data_source_id
       ) do
    organization_id = scope.organization_id

    with {:ok, binding} <- scoped_binding(organization_id, mission_id, binding_id),
         :ok <- different_source?(binding, data_source_id),
         {:ok, source} <- scoped_source(organization_id, mission_id, data_source_id),
         :ok <- compatible_source?(source, binding),
         {:ok, persisted} <-
           DataSources.persist_data_binding(
             %DataBinding{binding | data_source_id: data_source_id},
             actor_id: actor_id(scope),
             payload:
               Map.merge(action_payload(request), %{
                 "previous_data_source_id" => binding.data_source_id,
                 "current_data_source_id" => data_source_id
               })
           ) do
      {:ok, persisted}
    end
  end

  defp source_action(scope, %HostContext{mission_id: mission_id}, request, data_source_id) do
    with {:ok, source} <- scoped_source(scope.organization_id, mission_id, data_source_id) do
      execute_source_action(scope, mission_id, request, source)
    end
  end

  defp execute_source_action(
         scope,
         _mission_id,
         %ActionRequest{action_id: "disable-source"} = request,
         source
       ) do
    DataSources.disable_data_source(source.data_source_id, %{}, write_opts(scope, request))
  end

  defp execute_source_action(
         scope,
         _mission_id,
         %ActionRequest{action_id: "enable-source"} = request,
         source
       ) do
    DataSources.enable_data_source(source.data_source_id, %{}, write_opts(scope, request))
  end

  defp execute_source_action(
         scope,
         _mission_id,
         %ActionRequest{action_id: "reconcile-tsdb-backend"} = request,
         source
       ) do
    ManagedResources.reconcile_tsdb_backend(
      source.data_source_id,
      %{},
      write_opts(scope, request)
    )
  end

  defp execute_source_action(
         scope,
         _mission_id,
         %ActionRequest{action_id: "deprovision-tsdb-backend"} = request,
         source
       ) do
    case ManagedResources.request_tsdb_backend(
           source.data_source_id,
           :deprovision,
           %{},
           write_opts(scope, request)
         ) do
      {:ok, persisted_source, job} -> {:ok, %{source: persisted_source, job: job}}
      other -> other
    end
  end

  defp execute_source_action(
         scope,
         _mission_id,
         %ActionRequest{action_id: "provision-tsdb-backend"} = request,
         source
       ) do
    case ManagedResources.request_tsdb_backend(
           source.data_source_id,
           :provision,
           %{},
           write_opts(scope, request)
         ) do
      {:ok, persisted_source, job} -> {:ok, %{source: persisted_source, job: job}}
      other -> other
    end
  end

  defp execute_source_action(
         scope,
         mission_id,
         %ActionRequest{action_id: "probe-source"} = request,
         source
       ) do
    case DataSourceControl.probe(
           source.data_source_id,
           %{mission_id: mission_id},
           [
             actor_id: actor_id(scope),
             materialize_adapter_capabilities?: true,
             payload: action_payload(request)
           ] ++ source_probe_opts(source)
         ) do
      {:ok, event, status} -> {:ok, %{event: event, status: status}}
      other -> other
    end
  end

  defp rotate_source_credential(
         scope,
         %HostContext{mission_id: mission_id},
         request,
         data_source_id,
         credentials_ref
       ) do
    with {:ok, source} <- scoped_source(scope.organization_id, mission_id, data_source_id),
         :ok <- credential_belongs_to_source?(source, credentials_ref),
         {:ok, reference, event} <-
           SourceCredentials.rotate_reference(
             credentials_ref,
             %{
               data_source_id: data_source_id,
               organization_id: scope.organization_id,
               mission_id: mission_id,
               payload: action_payload(request)
             },
             actor_id: actor_id(scope)
           ) do
      {:ok, %{reference: reference, event: event}}
    end
  end

  defp deployment_action(scope, %HostContext{mission_id: mission_id}, request, job_id) do
    with {:ok, %Job{} = job} <- Jobs.fetch_job(job_id),
         :ok <- scoped_job?(scope.organization_id, mission_id, job) do
      case request.action_id do
        "retry-deployment-run" ->
          ManagedResources.retry_deployment_run(job_id)

        "requeue-deployment-run" ->
          ManagedResources.requeue_deployment_run(job_id)
      end
    end
  end

  defp scoped_source(organization_id, mission_id, data_source_id) do
    case Enum.find(
           DataSources.list_data_sources(organization_id, mission_id),
           &(&1.data_source_id == data_source_id)
         ) do
      %DataSource{} = source -> {:ok, source}
      nil -> {:error, :scope_mismatch}
    end
  end

  defp scoped_binding(organization_id, mission_id, binding_id) do
    case Enum.find(
           DataSources.list_data_bindings(organization_id, mission_id),
           &(&1.binding_id == binding_id)
         ) do
      %DataBinding{} = binding -> {:ok, binding}
      nil -> {:error, :scope_mismatch}
    end
  end

  defp different_source?(%DataBinding{data_source_id: data_source_id}, data_source_id),
    do: {:error, :same_data_source}

  defp different_source?(%DataBinding{}, _data_source_id), do: :ok

  defp compatible_source?(%DataSource{} = source, %DataBinding{} = binding) do
    if DataSource.active?(source) and
         AdapterRegistry.logical_source(source.adapter) == binding.logical_source do
      :ok
    else
      {:error, :incompatible_data_source}
    end
  end

  defp credential_belongs_to_source?(
         %DataSource{credentials_ref: credentials_ref},
         credentials_ref
       ),
       do: :ok

  defp credential_belongs_to_source?(_source, _credentials_ref),
    do: {:error, :scope_mismatch}

  defp scoped_job?(organization_id, mission_id, %Job{} = job) do
    payload_organization_id = payload_value(job.payload, :organization_id)
    payload_mission_id = payload_value(job.payload, :mission_id)

    if job.mission_id == mission_id and payload_organization_id in [nil, organization_id] and
         payload_mission_id in [nil, mission_id] do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  defp data_source(attrs, organization_id, mission_id) do
    %DataSource{
      data_source_id: attrs.data_source_id,
      owner: attrs.owner,
      kind: attrs.kind,
      adapter: attrs.adapter_definition.module,
      organization_id: organization_id,
      mission_id: mission_id,
      isolation_level: attrs.isolation_level,
      credentials_ref: attrs.credentials_ref,
      capabilities: attrs.adapter_definition.default_data_source_capabilities,
      metadata:
        compact(%{
          storage: attrs.storage,
          registered_by: "ops_console_data_sources_action",
          logical_source: attrs.logical_source,
          endpoint_ref: attrs.endpoint_ref,
          material_env_profile: attrs.material_env_profile
        })
    }
  end

  defp source_probe_opts(%DataSource{} = source) do
    if metadata_value(source.metadata, :storage) in [:questdb, "questdb"] and
         Enum.any?([:http_endpoint, :material_env_profile, :http_endpoint_env], fn key ->
           metadata_value(source.metadata, key) not in [nil, ""]
         end) do
      [questdb_probe?: true]
    else
      []
    end
  end

  defp write_opts(scope, request) do
    [actor_id: actor_id(scope), payload: action_payload(request)]
  end

  defp action_payload(%ActionRequest{action_id: action_id, idempotency_key: idempotency_key}) do
    %{"source" => "ops_console_data_sources_action", "action_id" => action_id}
    |> maybe_put("idempotency_key", idempotency_key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value), do: map

  defp actor_id(%Scope{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id

  defp actor_id(%Scope{service_identity: %{service_identity_id: service_identity_id}})
       when is_binary(service_identity_id),
       do: service_identity_id

  defp actor_id(_scope), do: nil

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key),
    do: Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))

  defp metadata_value(_metadata, _key), do: nil

  defp payload_value(payload, key) when is_map(payload) and is_atom(key),
    do: Map.get(payload, key, Map.get(payload, Atom.to_string(key)))

  defp payload_value(_payload, _key), do: nil

  defp source_owner(:byo_tsdb), do: :customer
  defp source_owner(:managed_tsdb), do: :cadence

  defp credential_kind(:byo_tsdb), do: :byo_tsdb_connection
  defp credential_kind(:managed_tsdb), do: :managed_tsdb_connection

  defp compact(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp event_id(%SourceHealthEvent{source_health_event_id: event_id}), do: event_id
  defp event_id(%{source_health_event_id: event_id}), do: event_id
  defp event_id(_event), do: nil

  defp probe_event_result(:unchanged), do: "unchanged"

  defp probe_event_result(%SourceHealthEvent{} = event) do
    %{
      "eventId" => event.source_health_event_id,
      "dataSourceId" => event.data_source_id,
      "missionId" => event.mission_id,
      "health" => text(event.source_health),
      "reason" => text_or_nil(event.reason)
    }
  end

  defp probe_event_result(_event), do: nil

  defp probe_status_result(status) when is_map(status) do
    %{
      "health" => text_or_nil(payload_value(status, :source_health)),
      "reason" => text_or_nil(payload_value(status, :reason)),
      "observedAt" => text_or_nil(payload_value(status, :observed_at))
    }
  end

  defp probe_status_result(_status), do: nil

  defp text_or_nil(nil), do: nil
  defp text_or_nil(value), do: text(value)

  defp text(nil), do: "none"
  defp text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(value) when is_float(value), do: Float.to_string(value)
  defp text(value), do: inspect(value)
end
