defmodule Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository do
  @moduledoc """
  Ecto-based implementation of the ProcedureRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for procedures and versions using PostgreSQL.

  ## Status Mapping

  The domain entity uses more granular statuses than the current schema:

  - Domain `:submitted` -> Schema `:in_review`
  - Domain `:withdrawn` -> Schema `:draft` (with cleared submission fields)
  - Domain `:rejected` -> Schema `:draft` (with rejection_reason set)

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :procedure_repository, Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository

  Then accessed via:

      repo = Application.get_env(:cadence, :procedure_repository)
      {:ok, version} = repo.find_version(id)
  """

  @behaviour Cadence.Ports.Repository.Procedures.ProcedureRepository
  @behaviour Cadence.Ports.Repository.Procedures.ApprovalOperations
  @behaviour Cadence.Ports.Repository.Procedures.ExecutionOperations

  import Ecto.Query

  alias Cadence.Domain.Procedures.Entities.Procedure, as: ProcedureEntity
  alias Cadence.Domain.Procedures.Entities.ProcedureVersion, as: ProcedureVersionEntity
  alias Cadence.Procedures.Procedure, as: ProcedureSchema
  alias Cadence.Procedures.ProcedureApproval, as: ProcedureApprovalSchema
  alias Cadence.Procedures.ProcedureExecution, as: ProcedureExecutionSchema
  alias Cadence.Procedures.ProcedureLog, as: ProcedureLogSchema
  alias Cadence.Procedures.ProcedureVersion, as: ProcedureVersionSchema
  alias Cadence.Repo

  # ===========================================================================
  # Procedure Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(ProcedureSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, procedure_to_entity(schema)}
    end
  end

  @impl true
  def find_by_slug(mission_id, slug) do
    query =
      from p in ProcedureSchema,
        where: p.mission_id == ^mission_id,
        where: p.name == ^slug

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, procedure_to_entity(schema)}
    end
  end

  @impl true
  def save(%ProcedureEntity{id: nil} = entity) do
    attrs = procedure_to_schema_attrs(entity)

    %ProcedureSchema{}
    |> ProcedureSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_procedure_result()
  end

  def save(%ProcedureEntity{id: id} = entity) do
    case Repo.get(ProcedureSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> ProcedureSchema.changeset(procedure_to_schema_attrs(entity))
        |> Repo.update()
        |> handle_procedure_result()
    end
  end

  @impl true
  def list(mission_id, opts \\ []) do
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from p in ProcedureSchema,
        where: p.mission_id == ^mission_id,
        order_by: [asc: p.name],
        limit: ^limit,
        offset: ^offset

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from p in query, where: ilike(p.name, ^search_term) or ilike(p.description, ^search_term)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(&procedure_to_entity/1)
  end

  @impl true
  def delete(id) do
    case Repo.get(ProcedureSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, procedure_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  # ===========================================================================
  # ProcedureVersion Operations
  # ===========================================================================

  @impl true
  def find_version(id) do
    query =
      from v in ProcedureVersionSchema,
        where: v.id == ^id,
        preload: [:approvals]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @impl true
  def save_version(%ProcedureVersionEntity{id: nil} = entity) do
    # Insert new version
    attrs = to_schema_attrs(entity)

    %ProcedureVersionSchema{}
    |> ProcedureVersionSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save_version(%ProcedureVersionEntity{id: id} = entity) do
    # Update existing version
    case Repo.get(ProcedureVersionSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> update_changeset(entity)
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def list_versions(procedure_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from v in ProcedureVersionSchema,
        where: v.procedure_id == ^procedure_id,
        order_by: [desc: v.version_number],
        limit: ^limit,
        preload: [:approvals]

    query =
      if status do
        schema_status = domain_status_to_schema(status)
        from v in query, where: v.status == ^schema_status
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(&to_entity/1)
  end

  @impl true
  def get_current_version(procedure_id) do
    query =
      from v in ProcedureVersionSchema,
        where: v.procedure_id == ^procedure_id,
        where: v.status == :approved,
        order_by: [desc: v.version_number],
        limit: 1,
        preload: [:approvals]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end

  @doc """
  Returns the next available version number for a procedure.

  This is a convenience function, not part of the behaviour contract.
  """
  def get_next_version_number(procedure_id) do
    query =
      from v in ProcedureVersionSchema,
        where: v.procedure_id == ^procedure_id,
        select: max(v.version_number)

    case Repo.one(query) do
      nil -> 1
      max_version -> max_version + 1
    end
  end

  @doc """
  Adds an approval record to a version.

  This is a convenience function, not part of the behaviour contract.
  """
  def add_approval(version_id, user_id, comment) do
    Repo.transaction(fn ->
      version = fetch_version_for_update(version_id)
      insert_approval(version, user_id, comment)
    end)
    |> handle_transaction_result()
  end

  @doc """
  Deprecates all approved versions except the specified one.

  This is a convenience function, not part of the behaviour contract.
  """
  def deprecate_other_versions(procedure_id, except_version_id) do
    now = DateTime.utc_now()

    query =
      from v in ProcedureVersionSchema,
        where: v.procedure_id == ^procedure_id,
        where: v.id != ^except_version_id,
        where: v.status == :approved

    {count, _} =
      Repo.update_all(query,
        set: [status: :deprecated, updated_at: now]
      )

    {:ok, count}
  end

  # ===========================================================================
  # ApprovalOperations Implementation
  # ===========================================================================

  defp fetch_version_for_update(version_id) do
    query =
      from v in ProcedureVersionSchema,
        where: v.id == ^version_id,
        lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> Repo.rollback(:not_found)
      version -> version
    end
  end

  defp insert_approval(version, user_id, comment) do
    approval_attrs = %{
      procedure_version_id: version.id,
      user_id: user_id,
      decision: :approved,
      comment: comment
    }

    %ProcedureApprovalSchema{}
    |> ProcedureApprovalSchema.changeset(approval_attrs)
    |> Repo.insert()
    |> case do
      {:ok, _approval} ->
        version = Repo.preload(version, :approvals, force: true)
        {:ok, to_entity(version)}

      {:error, changeset} ->
        Repo.rollback(extract_errors(changeset))
    end
  end

  defp handle_transaction_result({:ok, result}), do: result
  defp handle_transaction_result({:error, reason}), do: {:error, reason}

  @impl Cadence.Ports.Repository.Procedures.ApprovalOperations
  def find_approval(id) do
    case Repo.get(ProcedureApprovalSchema, id) do
      nil -> {:error, :not_found}
      approval -> {:ok, approval}
    end
  end

  @impl Cadence.Ports.Repository.Procedures.ApprovalOperations
  def find_user_approval(version_id, user_id) do
    query =
      from a in ProcedureApprovalSchema,
        where: a.procedure_version_id == ^version_id and a.user_id == ^user_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      approval -> {:ok, approval}
    end
  end

  @impl Cadence.Ports.Repository.Procedures.ApprovalOperations
  def list_approvals(version_id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:user])

    query =
      from a in ProcedureApprovalSchema,
        where: a.procedure_version_id == ^version_id,
        order_by: [asc: a.inserted_at]

    query
    |> preload(^preloads)
    |> Repo.all()
  end

  @impl Cadence.Ports.Repository.Procedures.ApprovalOperations
  def save_approval(attrs) do
    %ProcedureApprovalSchema{}
    |> ProcedureApprovalSchema.changeset(attrs)
    |> Repo.insert()
  end

  @impl Cadence.Ports.Repository.Procedures.ApprovalOperations
  def count_approvals(version_id, decision) do
    query =
      from a in ProcedureApprovalSchema,
        where: a.procedure_version_id == ^version_id and a.decision == ^decision,
        select: count(a.id)

    Repo.one(query) || 0
  end

  @impl Cadence.Ports.Repository.Procedures.ApprovalOperations
  def delete_approvals(version_id) do
    query =
      from a in ProcedureApprovalSchema,
        where: a.procedure_version_id == ^version_id

    {count, _} = Repo.delete_all(query)
    {:ok, count}
  end

  # ===========================================================================
  # ExecutionOperations Implementation
  # ===========================================================================

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def find_execution(id) do
    case Repo.get(ProcedureExecutionSchema, id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def list_executions(opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)
    preloads = Keyword.get(opts, :preload, [])

    query =
      from e in ProcedureExecutionSchema,
        order_by: [desc: e.inserted_at],
        limit: ^limit

    query =
      query
      |> apply_execution_filter(:mission_id, mission_id)
      |> apply_execution_filter(:procedure_id, procedure_id)
      |> apply_execution_filter(:status, status)

    query
    |> preload(^preloads)
    |> Repo.all()
  end

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def create_execution(attrs) do
    %ProcedureExecutionSchema{}
    |> ProcedureExecutionSchema.changeset(attrs)
    |> Repo.insert()
  end

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def update_execution(id, attrs) do
    case Repo.get(ProcedureExecutionSchema, id) do
      nil ->
        {:error, :not_found}

      execution ->
        execution
        |> ProcedureExecutionSchema.status_changeset(attrs)
        |> Repo.update()
    end
  end

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def list_running_executions do
    query =
      from e in ProcedureExecutionSchema,
        where: e.status in [:running, :pausing],
        order_by: [asc: e.started_at]

    Repo.all(query)
  end

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def list_logs(execution_id, opts \\ []) do
    level = Keyword.get(opts, :level)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from l in ProcedureLogSchema,
        where: l.execution_id == ^execution_id,
        order_by: [asc: l.timestamp],
        limit: ^limit,
        offset: ^offset

    query = apply_log_filter(query, :level, level)

    Repo.all(query)
  end

  @impl Cadence.Ports.Repository.Procedures.ExecutionOperations
  def create_log(attrs) do
    %ProcedureLogSchema{}
    |> ProcedureLogSchema.changeset(attrs)
    |> Repo.insert()
  end

  # Private helpers for execution/log filtering
  defp apply_execution_filter(query, _field, nil), do: query

  defp apply_execution_filter(query, field, value),
    do: where(query, [e], field(e, ^field) == ^value)

  defp apply_log_filter(query, _field, nil), do: query
  defp apply_log_filter(query, field, value), do: where(query, [l], field(l, ^field) == ^value)

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec to_entity(ProcedureVersionSchema.t()) :: ProcedureVersionEntity.t()
  def to_entity(%ProcedureVersionSchema{} = schema) do
    # Map schema status to domain status
    status = schema_status_to_domain(schema)

    # Convert approvals from schema records to domain format
    # Only include approvals with :approved decision
    approvals =
      (schema.approvals || [])
      |> Enum.filter(fn approval -> approval.decision == :approved end)
      |> Enum.map(fn approval ->
        %{
          user_id: approval.user_id,
          approved_at: approval.inserted_at,
          comment: approval.comment
        }
      end)

    %ProcedureVersionEntity{
      id: schema.id,
      procedure_id: schema.procedure_id,
      version_number: schema.version_number,
      status: status,
      author_id: schema.created_by_id,
      steps: extract_steps(schema.source),
      parameters: schema.parameters_schema || %{},
      description: nil,
      change_summary: schema.change_summary,
      approvals: approvals,
      required_approvals: 1,
      submitted_at: schema.submitted_at,
      approved_at: schema.approved_at,
      rejected_at: schema.rejected_at,
      rejected_by_id: schema.rejected_by_id,
      rejection_reason: schema.rejection_reason,
      deprecated_at: nil,
      created_at: schema.inserted_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for insertion.
  """
  @spec to_schema_attrs(ProcedureVersionEntity.t()) :: map()
  def to_schema_attrs(%ProcedureVersionEntity{} = entity) do
    %{
      procedure_id: entity.procedure_id,
      version_number: entity.version_number,
      source: %{"steps" => entity.steps},
      parameters_schema: entity.parameters,
      status: domain_status_to_schema(entity.status),
      created_by_id: entity.author_id,
      change_summary: entity.change_summary,
      submitted_at: entity.submitted_at,
      submitted_by_id: if(entity.status == :submitted, do: entity.author_id),
      approved_at: entity.approved_at,
      rejected_at: entity.rejected_at,
      rejected_by_id: entity.rejected_by_id,
      rejection_reason: entity.rejection_reason
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp update_changeset(schema, entity) do
    import Ecto.Changeset

    attrs = %{
      source: %{"steps" => entity.steps},
      parameters_schema: entity.parameters,
      status: domain_status_to_schema(entity.status),
      change_summary: entity.change_summary,
      submitted_at: entity.submitted_at,
      approved_at: entity.approved_at,
      rejected_at: entity.rejected_at,
      rejected_by_id: entity.rejected_by_id,
      rejection_reason: entity.rejection_reason
    }

    schema
    |> cast(attrs, Map.keys(attrs))
  end

  defp handle_result({:ok, schema}) do
    # Reload with approvals for consistent entity representation
    schema = Repo.preload(schema, :approvals)
    {:ok, to_entity(schema)}
  end

  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # Map domain status to schema status
  defp domain_status_to_schema(:draft), do: :draft
  defp domain_status_to_schema(:submitted), do: :in_review
  defp domain_status_to_schema(:approved), do: :approved
  defp domain_status_to_schema(:rejected), do: :draft
  defp domain_status_to_schema(:withdrawn), do: :draft
  defp domain_status_to_schema(:deprecated), do: :deprecated

  # Map schema status to domain status (with context from other fields)
  defp schema_status_to_domain(%{status: :draft, rejected_at: rejected_at})
       when not is_nil(rejected_at),
       do: :rejected

  defp schema_status_to_domain(%{status: :draft}), do: :draft
  defp schema_status_to_domain(%{status: :in_review}), do: :submitted
  defp schema_status_to_domain(%{status: :approved}), do: :approved
  defp schema_status_to_domain(%{status: :deprecated}), do: :deprecated

  # Extract steps from source map
  defp extract_steps(%{"steps" => steps}) when is_map(steps), do: steps
  defp extract_steps(source) when is_map(source), do: source
  defp extract_steps(_), do: %{}

  # ===========================================================================
  # Procedure Entity Conversion
  # ===========================================================================

  defp procedure_to_entity(%ProcedureSchema{} = schema) do
    %ProcedureEntity{
      id: schema.id,
      organization_id: schema.organization_id,
      mission_id: schema.mission_id,
      name: schema.name,
      description: schema.description,
      type: schema.type,
      tags: schema.tags || [],
      current_version_id: schema.current_version_id,
      created_at: schema.inserted_at
    }
  end

  defp procedure_to_schema_attrs(%ProcedureEntity{} = entity) do
    %{
      organization_id: entity.organization_id,
      mission_id: entity.mission_id,
      name: entity.name,
      description: entity.description,
      type: entity.type,
      tags: entity.tags,
      current_version_id: entity.current_version_id
    }
  end

  defp handle_procedure_result({:ok, schema}), do: {:ok, procedure_to_entity(schema)}
  defp handle_procedure_result({:error, changeset}), do: {:error, extract_errors(changeset)}
end
