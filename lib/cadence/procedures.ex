defmodule Cadence.Procedures do
  @moduledoc """
  The Procedures context.

  Manages procedure definitions, versions, and executions.
  """

  import Ecto.Query

  alias Cadence.Procedures.{
    Parameters,
    Procedure,
    ProcedureApproval,
    ProcedureExecution,
    ProcedureLog,
    ProcedureVersion,
    ProcedureVersionEvent
  }

  alias Cadence.Repo
  alias Cadence.Settings

  # ============================================================================
  # Procedures
  # ============================================================================

  @doc """
  Lists all unique tags used in procedures for an organization/mission.
  """
  def list_tags(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> select([p], p.tags)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists procedures for an organization, optionally filtered by mission and tags.

  ## Options

  - `:mission_id` - Filter to procedures in this mission
  - `:tags` - Filter to procedures that have ALL specified tags (AND logic)
  """
  def list_procedures(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    tags = Keyword.get(opts, :tags, [])

    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> maybe_filter_by_tags(tags)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [p], p.mission_id == ^mission_id or is_nil(p.mission_id))
  end

  defp maybe_filter_by_tags(query, []), do: query

  defp maybe_filter_by_tags(query, tags) when is_list(tags) do
    where(query, [p], fragment("? @> ?", p.tags, ^tags))
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
        allow_hazardous_commands: Keyword.get(opts, :allow_hazardous_commands, false),
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
  # Approval Workflow
  # ============================================================================

  @doc """
  Submits a procedure version for review. (draft → in_review)

  Creates an audit event recording the submission.
  """
  def submit_for_review(%ProcedureVersion{} = version, user_id) do
    with :ok <- validate_status(version, :draft) do
      Repo.transaction(fn ->
        updated =
          version
          |> ProcedureVersion.submit_changeset(%{
            status: :in_review,
            submitted_at: DateTime.utc_now(),
            submitted_by_id: user_id
          })
          |> Repo.update!()

        create_version_event!(ProcedureVersionEvent.submitted(updated, user_id))

        updated
      end)
    end
  end

  @doc """
  Withdraws a submission. (in_review → draft)

  Only the author (submitted_by or created_by) can withdraw, and only if
  the `allow_withdrawal` setting is enabled for the mission.

  Deletes any existing approvals and creates an audit event.
  """
  def withdraw_submission(%ProcedureVersion{} = version, user_id) do
    with :ok <- validate_status(version, :in_review),
         :ok <- validate_can_withdraw(version, user_id) do
      Repo.transaction(fn ->
        # Delete any existing approvals
        from(a in ProcedureApproval, where: a.procedure_version_id == ^version.id)
        |> Repo.delete_all()

        updated =
          version
          |> ProcedureVersion.withdrawal_changeset(%{})
          |> Repo.update!()

        create_version_event!(ProcedureVersionEvent.withdrawn(updated, user_id))

        updated
      end)
    end
  end

  @doc """
  Adds an approval or rejection decision to a version in review.

  If this is a rejection, the version immediately returns to draft status.

  If this is an approval and the required approval count is met (with no
  rejections), the version automatically transitions to :approved status.

  ## Options

  - `:comment` - Optional comment explaining the decision
  """
  def add_approval(%ProcedureVersion{} = version, user_id, decision, opts \\ []) do
    comment = Keyword.get(opts, :comment)

    with :ok <- validate_status(version, :in_review),
         :ok <- validate_can_approve(version, user_id),
         :ok <- validate_not_already_decided(version, user_id) do
      Repo.transaction(fn ->
        # Create approval record
        {:ok, approval} =
          %ProcedureApproval{}
          |> ProcedureApproval.changeset(%{
            procedure_version_id: version.id,
            user_id: user_id,
            decision: decision,
            comment: comment
          })
          |> Repo.insert()

        # Record audit event
        create_version_event!(
          ProcedureVersionEvent.approval_added(version, user_id, decision, comment)
        )

        # Handle decision consequences
        updated_version = handle_approval_decision(version, user_id, decision, comment)

        %{approval: approval, version: updated_version}
      end)
    end
  end

  @doc """
  Gets approval status summary for a version.

  Returns a map with:
  - `:required` - Number of approvals required
  - `:approved` - Number of approvals received
  - `:rejected` - Number of rejections received
  - `:pending` - Number of approvals still needed
  - `:can_be_approved` - Whether the version has enough approvals
  - `:is_blocked` - Whether there are any rejections
  - `:approvals` - List of approval records with users preloaded
  """
  def get_approval_status(%ProcedureVersion{} = version) do
    version = Repo.preload(version, procedure: :mission, approvals: :user)
    required = Settings.get(version.procedure.mission, :procedures, :required_approvals)

    approvals = version.approvals
    approved_count = Enum.count(approvals, &(&1.decision == :approved))
    rejected_count = Enum.count(approvals, &(&1.decision == :rejected))

    %{
      required: required,
      approved: approved_count,
      rejected: rejected_count,
      pending: max(0, required - approved_count),
      can_be_approved: approved_count >= required and rejected_count == 0,
      is_blocked: rejected_count > 0,
      approvals: approvals
    }
  end

  @doc """
  Lists all approvals for a version.
  """
  def list_approvals(version_id) do
    from(a in ProcedureApproval,
      where: a.procedure_version_id == ^version_id,
      preload: :user,
      order_by: [asc: a.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all audit events for a version.

  ## Options

  - `:limit` - Maximum number of events to return (default: 100)
  """
  def list_version_events(version_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(e in ProcedureVersionEvent,
      where: e.procedure_version_id == ^version_id,
      preload: :user,
      order_by: [asc: e.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  # Private approval workflow helpers

  defp validate_status(version, expected) do
    if version.status == expected, do: :ok, else: {:error, :invalid_status}
  end

  defp validate_can_withdraw(version, user_id) do
    version = Repo.preload(version, procedure: :mission)

    if Settings.get(version.procedure.mission, :procedures, :allow_withdrawal) do
      if version.submitted_by_id == user_id or version.created_by_id == user_id do
        :ok
      else
        {:error, :not_author}
      end
    else
      {:error, :withdrawal_not_allowed}
    end
  end

  defp validate_can_approve(version, user_id) do
    version = Repo.preload(version, procedure: :mission)
    allow_self = Settings.get(version.procedure.mission, :procedures, :allow_self_approval)

    if not allow_self and version.created_by_id == user_id do
      {:error, :cannot_approve_own_work}
    else
      :ok
    end
  end

  defp validate_not_already_decided(version, user_id) do
    case Repo.get_by(ProcedureApproval, procedure_version_id: version.id, user_id: user_id) do
      nil -> :ok
      _ -> {:error, :already_submitted_decision}
    end
  end

  defp handle_approval_decision(version, user_id, :rejected, reason) do
    updated =
      version
      |> ProcedureVersion.rejection_changeset(%{
        rejected_at: DateTime.utc_now(),
        rejected_by_id: user_id,
        rejection_reason: reason
      })
      |> Repo.update!()

    create_version_event!(ProcedureVersionEvent.rejected(updated, user_id, reason))

    updated
  end

  defp handle_approval_decision(version, user_id, :approved, _comment) do
    version = Repo.preload(version, procedure: :mission)
    required = Settings.get(version.procedure.mission, :procedures, :required_approvals)
    current_approvals = count_approvals(version.id)

    if current_approvals >= required do
      updated =
        version
        |> ProcedureVersion.approval_changeset(%{
          status: :approved,
          approved_at: DateTime.utc_now(),
          approved_by_id: user_id
        })
        |> Repo.update!()

      # Update procedure's current version pointer
      from(p in Procedure, where: p.id == ^version.procedure_id)
      |> Repo.update_all(set: [current_version_id: version.id])

      create_version_event!(ProcedureVersionEvent.approved(updated, user_id))

      updated
    else
      version
    end
  end

  defp count_approvals(version_id) do
    from(a in ProcedureApproval,
      where: a.procedure_version_id == ^version_id and a.decision == :approved
    )
    |> Repo.aggregate(:count)
  end

  defp create_version_event!(attrs) do
    %ProcedureVersionEvent{}
    |> ProcedureVersionEvent.changeset(attrs)
    |> Repo.insert!()
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

    with {:ok, validated_params} <-
           maybe_validate_params(parameters, version, validation_context, skip_validation) do
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

  # ============================================================================
  # Import/Export
  # ============================================================================

  @doc """
  Exports a procedure to a portable JSON-compatible map.

  Exports the current approved version (or latest draft if none approved).
  Does not include version history or execution records.
  """
  def export_procedure(%Procedure{} = procedure) do
    procedure = Repo.preload(procedure, :current_version)

    version_data =
      if procedure.current_version do
        %{
          "version_number" => procedure.current_version.version_number,
          "source" => procedure.current_version.source,
          "parameters_schema" => procedure.current_version.parameters_schema,
          "change_summary" => procedure.current_version.change_summary,
          "allow_hazardous_commands" => procedure.current_version.allow_hazardous_commands
        }
      else
        nil
      end

    %{
      "export_version" => "1.0.0",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source_procedure_id" => procedure.id,
      "source_mission_id" => procedure.mission_id,
      "procedure" => %{
        "name" => procedure.name,
        "description" => procedure.description,
        "type" => to_string(procedure.type),
        "tags" => procedure.tags || [],
        "version" => version_data
      }
    }
  end

  @doc """
  Imports a procedure from an export map into a target mission.

  Creates a new procedure with version 1 in draft status.
  The imported procedure requires approval before use.

  ## Options
  - `:user_id` - User performing the import (required, for audit)
  - `:name` - Override the procedure name (optional)

  ## Returns
  `{:ok, procedure}` or `{:error, reason}`

  ## Error Reasons
  - `:invalid_export_format` - Export data doesn't match expected schema
  - `:name_already_exists` - A procedure with this name already exists
  - `:missing_version_data` - Export has no version data to import
  """
  def import_procedure(organization_id, mission_id, export_data, opts \\ []) do
    user_id = Keyword.fetch!(opts, :user_id)
    name_override = Keyword.get(opts, :name)

    with {:ok, validated} <- validate_export_format(export_data),
         {:ok, name} <- resolve_import_name(organization_id, mission_id, validated, name_override),
         {:ok, version_data} <- extract_version_data(validated) do
      procedure_attrs = %{
        name: name,
        description: validated["procedure"]["description"],
        type: String.to_existing_atom(validated["procedure"]["type"]),
        tags: validated["procedure"]["tags"] || [],
        organization_id: organization_id,
        mission_id: mission_id
      }

      create_procedure(
        procedure_attrs,
        user_id: user_id,
        source: version_data["source"] || %{"steps" => %{}},
        parameters_schema: version_data["parameters_schema"] || %{},
        allow_hazardous_commands: version_data["allow_hazardous_commands"] || false
      )
    end
  end

  defp validate_export_format(%{"export_version" => "1.0.0", "procedure" => proc} = data)
       when is_map(proc) do
    case {proc["name"], proc["type"]} do
      {name, type} when is_binary(name) and is_binary(type) -> {:ok, data}
      _ -> {:error, :invalid_export_format}
    end
  end

  defp validate_export_format(_), do: {:error, :invalid_export_format}

  defp resolve_import_name(org_id, mission_id, validated, nil) do
    name = validated["procedure"]["name"]

    case get_procedure_by_name(org_id, mission_id, name) do
      nil -> {:ok, name}
      _ -> {:error, :name_already_exists}
    end
  end

  defp resolve_import_name(org_id, mission_id, _validated, name_override) do
    case get_procedure_by_name(org_id, mission_id, name_override) do
      nil -> {:ok, name_override}
      _ -> {:error, :name_already_exists}
    end
  end

  defp extract_version_data(%{"procedure" => %{"version" => nil}}),
    do: {:error, :missing_version_data}

  defp extract_version_data(%{"procedure" => %{"version" => v}}) when is_map(v),
    do: {:ok, v}

  defp extract_version_data(_),
    do: {:error, :missing_version_data}
end
