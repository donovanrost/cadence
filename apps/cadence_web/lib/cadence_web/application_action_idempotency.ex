defmodule CadenceWeb.ApplicationActionIdempotency do
  @moduledoc "Durable, fail-closed idempotency for authenticated application-host actions."

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    HostContext,
    SurfaceDefinition
  }

  alias Cadence.Auth.Scope
  alias Cadence.Repo
  alias CadenceWeb.ApplicationActionInput

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @namespace_fields [
    :organization_id,
    :actor_kind,
    :actor_id,
    :idempotency_key_digest
  ]

  @bound_identity_fields [
    :mission_id,
    :scope_kind,
    :scope_id,
    :application_key,
    :application_version,
    :surface_id,
    :surface_version,
    :operation,
    :operation_version,
    :generation_id,
    :release_id
  ]

  @identity_fields @namespace_fields ++ @bound_identity_fields

  @states [:in_progress, :completed, :failed, :indeterminate]
  @json_content_type "application/json; charset=utf-8"
  @max_idempotency_key_bytes 128
  @max_response_bytes 16_384
  @lease_seconds 30
  @retention_seconds 90 * 24 * 60 * 60
  @identity_index :faaid_logical_identity_idx

  schema "federated_application_action_idempotencies" do
    field(:organization_id, :string)
    field(:actor_kind, :string)
    field(:actor_id, :string)
    field(:mission_id, :string)
    field(:scope_kind, :string)
    field(:scope_id, :string)
    field(:application_key, :string)
    field(:application_version, :integer)
    field(:surface_id, :string)
    field(:surface_version, :integer)
    field(:operation, :string)
    field(:operation_version, :integer)
    field(:generation_id, :string)
    field(:release_id, :string)
    field(:idempotency_key_digest, :string)
    field(:request_digest, :string)
    field(:state, Ecto.Enum, values: @states)
    field(:claim_token, :string)
    field(:lease_expires_at, :utc_datetime_usec)
    field(:response_status, :integer)
    field(:response_content_type, :string)
    field(:response_body, :binary)
    field(:completed_at, :utc_datetime_usec)
    field(:retention_expires_at, :utc_datetime_usec)
    field(:retention_reference, :string)

    timestamps()
  end

  @type t :: %__MODULE__{}

  @spec identity(Scope.t(), HostContext.t(), map(), ActionDefinition.t()) ::
          {:ok, map()} | {:error, term()}
  def identity(
        %Scope{} = current_scope,
        %HostContext{placement: placement} = host_context,
        %{
          definition: %ApplicationDefinition{} = definition,
          surface: %SurfaceDefinition{} = surface,
          release: %{release_id: release_id},
          generation_id: generation_id
        },
        %ActionDefinition{} = action
      )
      when placement in [:organization, :user, :admin] do
    with {:ok, actor_id} <- user_actor_id(current_scope),
         {:ok, {organization_id, scope_id}} <- generic_scope_identity(current_scope, host_context),
         :ok <- required_identity(generation_id),
         :ok <- required_identity(release_id),
         :ok <- required_identity(definition.application_key),
         :ok <- required_identity(surface.surface_id),
         :ok <- required_identity(action.action_id) do
      {:ok,
       %{
         organization_id: organization_id,
         actor_kind: "user",
         actor_id: actor_id,
         mission_id: "application-host:" <> Atom.to_string(placement) <> ":" <> scope_id,
         scope_kind: Atom.to_string(placement),
         scope_id: scope_id,
         application_key: definition.application_key,
         application_version: definition.version,
         surface_id: surface.surface_id,
         surface_version: surface.version,
         operation: action.action_id,
         operation_version: action.version,
         generation_id: generation_id,
         release_id: release_id
       }}
    end
  end

  def identity(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %{
          definition: %ApplicationDefinition{} = definition,
          surface: %SurfaceDefinition{} = surface,
          release: %{release_id: release_id},
          generation_id: generation_id
        },
        %ActionDefinition{} = action
      ) do
    with {:ok, actor_id} <- user_actor_id(current_scope),
         :ok <- required_identity(generation_id),
         :ok <- required_identity(release_id),
         :ok <- required_identity(current_scope.organization_id),
         :ok <- required_identity(host_context.mission_id),
         :ok <- required_identity(host_context.spacecraft_id || host_context.mission_id),
         :ok <- required_identity(definition.application_key),
         :ok <- required_identity(surface.surface_id),
         :ok <- required_identity(action.action_id) do
      {:ok,
       %{
         organization_id: current_scope.organization_id,
         actor_kind: "user",
         actor_id: actor_id,
         mission_id: host_context.mission_id,
         scope_kind: Atom.to_string(host_context.placement),
         scope_id: host_context.spacecraft_id || host_context.mission_id,
         application_key: definition.application_key,
         application_version: definition.version,
         surface_id: surface.surface_id,
         surface_version: surface.version,
         operation: action.action_id,
         operation_version: action.version,
         generation_id: generation_id,
         release_id: release_id
       }}
    end
  end

  def identity(%Scope{}, %HostContext{}, _admission, %ActionDefinition{}),
    do: {:error, :active_generation_unavailable}

  @spec key_digest(binary()) :: {:ok, binary()} | {:error, term()}
  def key_digest(key)
      when is_binary(key) and byte_size(key) >= 1 and byte_size(key) <= @max_idempotency_key_bytes do
    with {:ok, secret} <- server_secret() do
      {:ok, digest(secret, "idempotency-key:" <> key)}
    end
  end

  def key_digest(_key), do: {:error, :malformed_idempotency_key}

  @spec request_digest(map()) :: {:ok, binary()} | {:error, term()}
  def request_digest(request) when is_map(request) do
    with {:ok, normalized} <- ApplicationActionInput.safe(request),
         {:ok, secret} <- server_secret() do
      {:ok, digest(secret, "application-action-request:" <> canonical_json(normalized))}
    else
      _invalid -> {:error, :invalid_application_request}
    end
  end

  def request_digest(_request), do: {:error, :invalid_application_request}

  @spec run(Scope.t(), map(), binary(), map(), (-> term()), keyword()) ::
          {:ok, {:executed | :replayed, map()}} | {:error, term()}
  def run(
        %Scope{} = current_scope,
        identity,
        raw_key,
        request_document,
        fun,
        opts \\ []
      )
      when is_map(identity) and is_binary(raw_key) and is_map(request_document) and
             is_function(fun, 0) and is_list(opts) do
    with :ok <- validate_identity_scope(current_scope, identity),
         {:ok, key_digest} <- key_digest(raw_key),
         {:ok, request_digest} <- request_digest(request_document),
         {:ok, claim} <- claim(identity, key_digest, request_digest, opts) do
      execute_claim(claim, fun, opts)
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error, Ecto.ConstraintError] ->
      {:error, {:idempotency_persistence_failure, error}}
  end

  @doc false
  @spec claim(map(), binary(), binary(), keyword()) ::
          {:ok, {:claimed, t()} | {:replay, map()}} | {:error, term()}
  def claim(identity, key_digest, request_digest, opts \\ [])
      when is_map(identity) and is_binary(key_digest) and is_binary(request_digest) and
             is_list(opts) do
    now = now(opts)

    attrs =
      identity
      |> Map.take(@identity_fields -- [:idempotency_key_digest])
      |> Map.merge(%{
        idempotency_key_digest: key_digest,
        request_digest: request_digest,
        state: :in_progress,
        claim_token: claim_token(),
        lease_expires_at: DateTime.add(now, lease_seconds(opts), :second),
        retention_expires_at: DateTime.add(now, @retention_seconds, :second),
        retention_reference: retention_reference(identity)
      })

    case Repo.insert(insert_changeset(attrs)) do
      {:ok, row} ->
        {:ok, {:claimed, row}}

      {:error, changeset} ->
        duplicate_claim(identity, key_digest, request_digest, changeset, opts)
    end
  end

  @spec indeterminate_response() :: map()
  def indeterminate_response do
    %{
      status: 409,
      content_type: @json_content_type,
      body:
        Jason.encode!(%{
          "schema" => "cadence.application-host-problem.v1",
          "code" => "action_indeterminate",
          "message" =>
            "The action may have executed, but its durable result is unavailable. Operator action is required."
        })
    }
  end

  @spec complete(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def complete(%__MODULE__{} = row, response, opts \\ []) when is_map(response) and is_list(opts),
    do: terminal_update(row, :completed, response, opts)

  @spec fail(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def fail(%__MODULE__{} = row, response, opts \\ []) when is_map(response) and is_list(opts),
    do: terminal_update(row, :failed, response, opts)

  @spec mark_indeterminate(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def mark_indeterminate(%__MODULE__{} = row, opts \\ []) when is_list(opts),
    do: terminal_update(row, :indeterminate, indeterminate_response(), opts)

  defp execute_claim({:claimed, %__MODULE__{} = row}, fun, opts) do
    case safe_execute(fun) do
      {:completed, response} -> finalize_claim(row, :completed, response, opts)
      {:failed, response} -> finalize_claim(row, :failed, response, opts)
      {:indeterminate, response} -> finalize_claim(row, :indeterminate, response, opts)
      :indeterminate -> finalize_claim(row, :indeterminate, indeterminate_response(), opts)
    end
  end

  defp execute_claim({:replay, response}, _fun, _opts), do: {:ok, {:replayed, response}}
  defp execute_claim({:error, reason}, _fun, _opts), do: {:error, reason}

  defp safe_execute(fun) do
    case fun.() do
      {:ok, response} when is_map(response) -> {:completed, response}
      {:error, response} when is_map(response) -> {:failed, response}
      {:indeterminate, response} when is_map(response) -> {:indeterminate, response}
      _invalid -> :indeterminate
    end
  rescue
    _error -> :indeterminate
  catch
    _kind, _value -> :indeterminate
  end

  defp finalize_claim(%__MODULE__{} = row, state, response, opts) do
    case terminal_update(row, state, response, opts) do
      {:ok, response} ->
        {:ok, {:executed, response}}

      {:error, :invalid_response} when state != :indeterminate ->
        finalize_claim(row, :indeterminate, indeterminate_response(), opts)

      {:error, :invalid_response} ->
        finalize_claim(row, :indeterminate, indeterminate_response(), opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp terminal_update(%__MODULE__{} = row, state, response, opts)
       when state in [:completed, :failed, :indeterminate] do
    with {:ok, response_attrs} <- response_attrs(response, response_limit(row.application_key)),
         now <- now(opts),
         {1, _} <-
           Repo.update_all(
             from(stored in __MODULE__,
               where:
                 stored.id == ^row.id and stored.state == :in_progress and
                   stored.claim_token == ^row.claim_token
             ),
             set: [
               state: state,
               claim_token: nil,
               lease_expires_at: nil,
               response_status: response_attrs.status,
               response_content_type: response_attrs.content_type,
               response_body: response_attrs.body,
               completed_at: now,
               updated_at: now
             ]
           ) do
      {:ok, response}
    else
      {0, _} -> {:error, :claim_lost}
      {:error, :invalid_response} -> {:error, :invalid_response}
    end
  end

  defp response_attrs(%{status: status, content_type: content_type, body: body}, limit)
       when is_integer(status) and status >= 100 and status <= 599 and
              content_type == @json_content_type and is_binary(body) and
              byte_size(body) >= 1 and byte_size(body) <= limit do
    {:ok, %{status: status, content_type: content_type, body: body}}
  end

  defp response_attrs(_response, _limit), do: {:error, :invalid_response}

  defp duplicate_claim(identity, key_digest, request_digest, changeset, opts) do
    if duplicate_constraint?(changeset) do
      case Repo.get_by(__MODULE__, duplicate_lookup(identity, key_digest)) do
        %__MODULE__{} = row -> resolve_duplicate(row, identity, request_digest, opts)
        nil -> {:error, {:idempotency_persistence_failure, :claim_row_missing}}
      end
    else
      {:error, {:idempotency_persistence_failure, changeset}}
    end
  end

  defp duplicate_constraint?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:idempotency_key_digest, {_message, metadata}} ->
        metadata[:constraint] == :unique and
          metadata[:constraint_name] in [@identity_index, Atom.to_string(@identity_index)]

      _error ->
        false
    end)
  end

  defp duplicate_lookup(identity, key_digest) do
    identity
    |> Map.take(@namespace_fields -- [:idempotency_key_digest])
    |> Map.put(:idempotency_key_digest, key_digest)
  end

  defp resolve_duplicate(%__MODULE__{} = row, identity, request_digest, opts) do
    if collision?(row, identity, request_digest) do
      {:error, :idempotency_key_collision}
    else
      resolve_duplicate_state(row, identity, request_digest, opts)
    end
  end

  defp resolve_duplicate_state(
         %__MODULE__{state: :completed} = row,
         _identity,
         _request_digest,
         _opts
       ),
       do: replay_response(row)

  defp resolve_duplicate_state(
         %__MODULE__{state: :failed} = row,
         _identity,
         _request_digest,
         _opts
       ),
       do: replay_response(row)

  defp resolve_duplicate_state(
         %__MODULE__{state: :indeterminate} = row,
         _identity,
         _request_digest,
         _opts
       ),
       do: replay_response(row)

  defp resolve_duplicate_state(
         %__MODULE__{state: :in_progress} = row,
         identity,
         request_digest,
         opts
       ) do
    if expired?(row, now(opts)) do
      case terminal_update(row, :indeterminate, indeterminate_response(), opts) do
        {:ok, response} -> {:ok, {:replay, response}}
        {:error, :claim_lost} -> resolve_after_race(row, identity, request_digest, opts)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :idempotency_in_progress}
    end
  end

  defp collision?(%__MODULE__{} = row, identity, request_digest) do
    row.request_digest != request_digest or
      Map.take(row, @bound_identity_fields) != Map.take(identity, @bound_identity_fields)
  end

  defp resolve_after_race(%__MODULE__{} = stale_row, identity, request_digest, opts) do
    case Repo.get(__MODULE__, stale_row.id) do
      %__MODULE__{} = row -> resolve_duplicate(row, identity, request_digest, opts)
      nil -> {:error, {:idempotency_persistence_failure, :claim_row_missing}}
    end
  end

  defp replay_response(%__MODULE__{} = row) do
    with {:ok, status} <- response_status(row.response_status),
         {:ok, content_type} <- response_content_type(row.response_content_type),
         {:ok, body} <- response_body(row.response_body, response_limit(row.application_key)) do
      {:ok, {:replay, %{status: status, content_type: content_type, body: body}}}
    else
      _invalid -> {:error, {:idempotency_persistence_failure, :stored_response_invalid}}
    end
  end

  defp response_status(status) when is_integer(status) and status >= 100 and status <= 599,
    do: {:ok, status}

  defp response_status(_status), do: :error

  defp response_content_type(@json_content_type), do: {:ok, @json_content_type}
  defp response_content_type(_content_type), do: :error

  defp response_body(body, limit) when is_binary(body) and byte_size(body) <= limit,
    do: {:ok, body}

  defp response_body(_body, _limit), do: :error

  # The definition receipt includes an 8 KB expression, including JSON escaping.
  defp response_limit("derived_telemetry"), do: 65_536
  defp response_limit(_application_key), do: @max_response_bytes

  defp insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(
      attrs,
      @identity_fields ++
        [
          :request_digest,
          :state,
          :claim_token,
          :lease_expires_at,
          :retention_expires_at,
          :retention_reference
        ]
    )
    |> validate_required(
      @identity_fields ++
        [
          :request_digest,
          :state,
          :claim_token,
          :lease_expires_at,
          :retention_expires_at,
          :retention_reference
        ]
    )
    |> unique_constraint(:idempotency_key_digest, name: @identity_index)
  end

  defp validate_identity_scope(
         %Scope{actor_kind: :user, user: %{user_id: actor_id}} = scope,
         %{
           organization_id: organization_id,
           actor_kind: "user",
           actor_id: actor_id,
           scope_kind: "organization",
           scope_id: scope_id
         }
       )
       when is_binary(actor_id) and is_binary(organization_id) and is_binary(scope_id),
       do: generic_identity_scope(scope, organization_id, scope_id, "organization")

  defp validate_identity_scope(
         %Scope{actor_kind: :user, user: %{user_id: actor_id}},
         %{
           organization_id: organization_id,
           actor_kind: "user",
           actor_id: identity_actor_id,
           scope_kind: "user",
           scope_id: identity_scope_id
         }
       )
       when is_binary(actor_id) and is_binary(organization_id) and
              is_binary(identity_actor_id) and is_binary(identity_scope_id) do
    if organization_id == "user:" <> actor_id and identity_actor_id == actor_id and
         identity_scope_id == actor_id,
       do: :ok,
       else: {:error, :application_action_scope_required}
  end

  defp validate_identity_scope(
         %Scope{actor_kind: :user, user: %{user_id: actor_id}},
         %{
           organization_id: organization_id,
           actor_kind: "user",
           actor_id: identity_actor_id,
           scope_kind: "admin",
           scope_id: identity_scope_id
         }
       )
       when is_binary(actor_id) and is_binary(organization_id) and
              is_binary(identity_actor_id) and is_binary(identity_scope_id) do
    if organization_id == "admin:" <> actor_id and identity_actor_id == actor_id and
         identity_scope_id == actor_id,
       do: :ok,
       else: {:error, :application_action_scope_required}
  end

  defp validate_identity_scope(
         %Scope{actor_kind: :user, organization_id: organization_id, user: %{user_id: actor_id}},
         %{organization_id: organization_id, actor_kind: "user", actor_id: actor_id}
       )
       when is_binary(organization_id) and is_binary(actor_id),
       do: :ok

  defp validate_identity_scope(%Scope{}, _identity),
    do: {:error, :application_action_scope_required}

  defp user_actor_id(%Scope{actor_kind: :user, user: %{user_id: actor_id}})
       when is_binary(actor_id) and actor_id != "",
       do: {:ok, actor_id}

  defp user_actor_id(%Scope{}), do: {:error, :application_action_scope_required}

  defp generic_scope_identity(
         %Scope{organization_id: organization_id},
         %HostContext{placement: :organization, organization_id: organization_id}
       )
       when is_binary(organization_id),
       do: {:ok, {organization_id, organization_id}}

  defp generic_scope_identity(
         %Scope{user: %{user_id: user_id}},
         %HostContext{placement: :user, user_id: user_id}
       )
       when is_binary(user_id),
       do: {:ok, {"user:" <> user_id, user_id}}

  defp generic_scope_identity(
         %Scope{user: %{user_id: user_id}},
         %HostContext{placement: :admin}
       )
       when is_binary(user_id),
       do: {:ok, {"admin:" <> user_id, user_id}}

  defp generic_scope_identity(_scope, _host_context),
    do: {:error, :application_action_scope_required}

  defp generic_identity_scope(scope, organization_id, scope_id, "organization") do
    if scope.organization_id == organization_id and scope.organization_id == scope_id,
      do: :ok,
      else: {:error, :application_action_scope_required}
  end

  defp required_identity(value) when is_binary(value) and value != "", do: :ok
  defp required_identity(_value), do: {:error, :active_generation_unavailable}

  defp retention_reference(%{release_id: release_id, generation_id: generation_id}),
    do: "frontend-release:" <> release_id <> ":generation:" <> generation_id

  defp claim_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp expired?(%__MODULE__{lease_expires_at: %DateTime{} = expires_at}, %DateTime{} = now),
    do: DateTime.compare(expires_at, now) != :gt

  defp expired?(%__MODULE__{}, %DateTime{}), do: true

  defp now(opts) do
    case Keyword.get(opts, :now) do
      %DateTime{} = value -> value
      _missing -> DateTime.utc_now()
    end
  end

  defp lease_seconds(opts) do
    case Keyword.get(opts, :lease_seconds, @lease_seconds) do
      value when is_integer(value) and value in 1..300 -> value
      _invalid -> @lease_seconds
    end
  end

  defp server_secret do
    endpoint_config = Application.get_env(:cadence_web, CadenceWeb.Endpoint, [])
    configured = Application.get_env(:cadence_web, :application_host_idempotency_secret)
    secret = configured || Keyword.get(endpoint_config, :secret_key_base)

    if is_binary(secret) and byte_size(secret) >= 32,
      do: {:ok, secret},
      else: {:error, :idempotency_secret_unavailable}
  end

  defp digest(secret, value) do
    "hmac-sha256:" <> (:crypto.mac(:hmac, :sha256, secret, value) |> Base.encode16(case: :lower))
  end

  defp canonical_json(value) when is_map(value) do
    keys = Map.keys(value)

    if Enum.all?(keys, &is_binary/1) do
      keys
      |> Enum.sort()
      |> Enum.map_join(",", fn key ->
        Jason.encode!(key) <> ":" <> canonical_json(Map.fetch!(value, key))
      end)
      |> then(&("{" <> &1 <> "}"))
    else
      raise ArgumentError, "canonical request maps require string keys"
    end
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_binary(value), do: Jason.encode!(value)
  defp canonical_json(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical_json(value) when is_float(value), do: Jason.encode!(value)
  defp canonical_json(true), do: "true"
  defp canonical_json(false), do: "false"
  defp canonical_json(nil), do: "null"
end
