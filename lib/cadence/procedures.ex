defmodule Cadence.Procedures do
  @moduledoc """
  The Procedures context.

  Manages procedure definitions, versions, and executions.
  """

  import Ecto.Query
  alias Cadence.Repo
  alias Cadence.Procedures.{Procedure, ProcedureVersion, ProcedureExecution, ProcedureLog, Parameters}

  # ============================================================================
  # Procedures
  # ============================================================================

  @doc """
  Lists procedures for an organization, optionally filtered by mission.
  """
  def list_procedures(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [p], p.mission_id == ^mission_id or is_nil(p.mission_id))
  end

  @doc """
  Gets a procedure by ID.
  """
  def get_procedure(id), do: Repo.get(Procedure, id)

  @doc """
  Gets a procedure by ID, raises if not found.
  """
  def get_procedure!(id), do: Repo.get!(Procedure, id)

  @doc """
  Gets a procedure by name within a mission.
  """
  def get_procedure_by_name(organization_id, mission_id, name) do
    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> where([p], p.mission_id == ^mission_id or is_nil(p.mission_id))
    |> where([p], p.name == ^name)
    |> Repo.one()
  end

  @doc """
  Creates a procedure with an initial draft version.
  """
  def create_procedure(attrs, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    source = Keyword.get(opts, :source, %{"steps" => []})

    Repo.transaction(fn ->
      # Create procedure
      procedure =
        %Procedure{}
        |> Procedure.changeset(attrs)
        |> Repo.insert!()

      # Create initial version
      version_attrs = %{
        procedure_id: procedure.id,
        version_number: 1,
        source: source,
        parameters_schema: Keyword.get(opts, :parameters_schema, %{}),
        created_by_id: user_id
      }

      version =
        %ProcedureVersion{}
        |> ProcedureVersion.changeset(version_attrs)
        |> Repo.insert!()

      # Update procedure with current version
      procedure
      |> Procedure.changeset(%{current_version_id: version.id})
      |> Repo.update!()
    end)
  end

  @doc """
  Updates a procedure's metadata (not source - use create_version for that).
  """
  def update_procedure(%Procedure{} = procedure, attrs) do
    procedure
    |> Procedure.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a procedure and all its versions/executions.
  """
  def delete_procedure(%Procedure{} = procedure) do
    Repo.delete(procedure)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking procedure changes.
  """
  def change_procedure(%Procedure{} = procedure, attrs \\ %{}) do
    Procedure.changeset(procedure, attrs)
  end

  # ============================================================================
  # Versions
  # ============================================================================

  @doc """
  Lists versions for a procedure.
  """
  def list_versions(procedure_id) do
    ProcedureVersion
    |> where([v], v.procedure_id == ^procedure_id)
    |> order_by([v], desc: v.version_number)
    |> Repo.all()
  end

  @doc """
  Gets a specific version.
  """
  def get_version(id), do: Repo.get(ProcedureVersion, id)
  def get_version!(id), do: Repo.get!(ProcedureVersion, id)

  @doc """
  Gets the current approved version for a procedure.
  """
  def get_approved_version(procedure_id) do
    ProcedureVersion
    |> where([v], v.procedure_id == ^procedure_id)
    |> where([v], v.status == :approved)
    |> order_by([v], desc: v.version_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a new version of a procedure.
  """
  def create_version(procedure_or_id, attrs, opts \\ [])

  def create_version(%Procedure{id: procedure_id}, attrs, opts) do
    create_version(procedure_id, attrs, opts)
  end

  def create_version(procedure_id, attrs, opts) when is_binary(procedure_id) do
    # Get next version number
    max_version =
      ProcedureVersion
      |> where([v], v.procedure_id == ^procedure_id)
      |> select([v], max(v.version_number))
      |> Repo.one() || 0

    # Build version attrs, preserving any passed-in values but ensuring required fields
    version_attrs =
      attrs
      |> Map.put(:procedure_id, procedure_id)
      |> Map.put(:version_number, max_version + 1)
      |> Map.put_new(:status, :draft)

    # Only set created_by_id from opts if not already in attrs
    version_attrs =
      case Keyword.get(opts, :user_id) do
        nil -> version_attrs
        user_id -> Map.put_new(version_attrs, :created_by_id, user_id)
      end

    %ProcedureVersion{}
    |> ProcedureVersion.changeset(version_attrs)
    |> Repo.insert()
  end

  @doc """
  Approves a version.
  """
  def approve_version(%ProcedureVersion{} = version, user_id) do
    Repo.transaction(fn ->
      # Update version status
      updated_version =
        version
        |> ProcedureVersion.approval_changeset(%{
          status: :approved,
          approved_at: DateTime.utc_now(),
          approved_by_id: user_id
        })
        |> Repo.update!()

      # Update procedure's current version
      Procedure
      |> where([p], p.id == ^version.procedure_id)
      |> Repo.update_all(set: [current_version_id: version.id])

      updated_version
    end)
  end

  @doc """
  Deprecates a version.
  """
  def deprecate_version(%ProcedureVersion{} = version) do
    version
    |> ProcedureVersion.approval_changeset(%{status: :deprecated})
    |> Repo.update()
  end

  # ============================================================================
  # Executions
  # ============================================================================

  @doc """
  Lists executions, optionally filtered.
  """
  def list_executions(opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    ProcedureExecution
    |> maybe_filter(:organization_id, organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:procedure_id, procedure_id)
    |> maybe_filter(:status, status)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  @doc """
  Gets an execution by ID.
  """
  def get_execution(id), do: Repo.get(ProcedureExecution, id)

  @doc """
  Gets an execution by ID with preloads.
  """
  def get_execution!(id) do
    ProcedureExecution
    |> Repo.get!(id)
    |> Repo.preload([:procedure, :procedure_version])
  end

  @doc """
  Creates a new execution record.

  Does not start the execution - use `start_execution/2` for that.
  """
  def create_execution(attrs) do
    %ProcedureExecution{}
    |> ProcedureExecution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates execution status.
  """
  def update_execution_status(%ProcedureExecution{} = execution, attrs) do
    execution
    |> ProcedureExecution.status_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Starts a new procedure execution.

  Creates the execution record and starts the ExecutionProcess.

  Parameters are validated against the procedure version's `parameters_schema`
  before execution begins. If validation fails, returns `{:error, {:validation, errors}}`.

  ## Options

  - `:version_id` - Specific version to run (defaults to current version)
  - `:target_id` - Target for the execution
  - `:parameters` - Runtime parameters (validated against schema)
  - `:user_id` - User triggering the execution
  - `:triggered_by` - Trigger source (`:manual`, `:schedule`, `:event`)
  - `:trigger_context` - Context data from trigger (for event-driven executions)
  - `:skip_validation` - Skip parameter validation (use with caution)
  """
  def start_execution(procedure_id, opts \\ []) do
    version_id = Keyword.get(opts, :version_id)
    target_id = Keyword.get(opts, :target_id)
    parameters = Keyword.get(opts, :parameters, %{})
    user_id = Keyword.get(opts, :user_id)
    triggered_by = Keyword.get(opts, :triggered_by, :manual)
    trigger_context = Keyword.get(opts, :trigger_context)
    skip_validation = Keyword.get(opts, :skip_validation, false)

    procedure = get_procedure!(procedure_id)

    # Use specified version or current version
    version =
      if version_id do
        get_version!(version_id)
      else
        if procedure.current_version_id do
          get_version!(procedure.current_version_id)
        else
          raise "No version available for procedure #{procedure_id}"
        end
      end

    # Validate parameters against schema
    validation_context = %{
      mission_id: procedure.mission_id,
      organization_id: procedure.organization_id
    }

    with {:ok, validated_params} <- maybe_validate_params(parameters, version, validation_context, skip_validation) do
      # Create execution record
      execution_attrs = %{
        procedure_id: procedure_id,
        procedure_version_id: version.id,
        organization_id: procedure.organization_id,
        mission_id: procedure.mission_id,
        target_id: target_id,
        parameters: validated_params,
        triggered_by: triggered_by,
        triggered_by_user_id: user_id,
        trigger_context: trigger_context,
        status: :pending
      }

      with {:ok, execution} <- create_execution(execution_attrs),
           {:ok, _pid} <- start_execution_process(execution.id) do
        {:ok, execution}
      end
    end
  end

  defp maybe_validate_params(params, _version, _context, true), do: {:ok, params}

  defp maybe_validate_params(params, version, context, false) do
    case Parameters.validate(params, version.parameters_schema, context) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, {:validation, errors}}
    end
  end

  defp start_execution_process(execution_id) do
    DynamicSupervisor.start_child(
      Cadence.Procedures.ExecutionSupervisor,
      {Cadence.Procedures.Engine.ExecutionProcess, execution_id: execution_id}
    )
  end

  # ============================================================================
  # Logs
  # ============================================================================

  @doc """
  Lists logs for an execution.
  """
  def list_logs(execution_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    level = Keyword.get(opts, :level)

    ProcedureLog
    |> where([l], l.execution_id == ^execution_id)
    |> maybe_filter(:level, level)
    |> order_by([l], asc: l.timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Creates a log entry.
  """
  def create_log(attrs) do
    %ProcedureLog{}
    |> ProcedureLog.changeset(attrs)
    |> Repo.insert()
  end
end
