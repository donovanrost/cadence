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
    ProcedureVersion,
    V2
  }

  alias Cadence.Outbox
  alias Cadence.Recordings
  alias Cadence.Repo
  alias Cadence.Targets
  alias Cadence.Settings

  alias Cadence.Recordings.Recordables.{
    ProcedureApprovalAdded,
    ProcedureVersionApproved,
    ProcedureVersionCreated,
    ProcedureVersionRejected,
    ProcedureVersionSubmitted,
    ProcedureVersionWithdrawn
  }

  alias Ecto.Multi

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
  Creates a new V2 procedure with initial block-based structure.

  This creates:
  - Procedure record
  - Initial ProcedureVersion (draft, manual execution mode)
  - Default ProcedureSection named "Main"
  - Starter ProcedureStep
  - Welcome text block

  Returns `{:ok, {procedure, version}}` on success.

  ## Options

  - `:user_id` - User creating the procedure (required)
  """
  def create_procedure_v2(attrs, opts \\ []) do
    user_id = Keyword.fetch!(opts, :user_id)

    Repo.transaction(fn ->
      # 1. Create procedure
      procedure_attrs =
        attrs
        |> Map.take([:name, :description, :tags, :organization_id, :mission_id])
        |> Map.put(:type, :dag)

      procedure =
        %Procedure{}
        |> Procedure.changeset(procedure_attrs)
        |> Repo.insert!()

      # 2. Create initial version (empty source - V2 uses sections/steps/blocks)
      version_attrs = %{
        procedure_id: procedure.id,
        version_number: 1,
        source: %{},
        execution_mode: :manual,
        created_by_id: user_id
      }

      version =
        %ProcedureVersion{}
        |> ProcedureVersion.changeset(version_attrs)
        |> Repo.insert!()

      # Update procedure with current version
      procedure =
        procedure
        |> Procedure.changeset(%{current_version_id: version.id})
        |> Repo.update!()

      # 3. Create default section
      {:ok, section} =
        V2.create_section(version.id, %{
          name: "Main",
          position: 0
        })

      # 4. Create starter step
      {:ok, step} =
        V2.create_step(section.id, %{
          name: "start",
          title: "Getting Started",
          position: 0,
          requires_signoff: true
        })

      # 5. Create welcome block
      {:ok, _block} =
        V2.create_block(step.id, %{
          block_type: :text,
          position: 0,
          content: %{"markdown" => "Add your procedure steps here."}
        })

      {procedure, version}
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
    procedure = get_procedure!(procedure_id)
    user_id = Keyword.get(opts, :user_id)

    version_number = next_version_number(procedure_id)
    version_attrs = build_version_attrs(attrs, procedure_id, version_number, user_id)
    version_created_attrs = build_version_created_attrs(attrs, procedure_id, version_number)

    Multi.new()
    |> Multi.insert(:version, ProcedureVersion.changeset(%ProcedureVersion{}, version_attrs))
    |> Recordings.append(:created, ProcedureVersionCreated, version_created_attrs, fn %{
                                                                                        version: v
                                                                                      } ->
      version_recording_attrs(procedure, user_id, v.id)
    end)
    |> Repo.transaction()
    |> normalize_version_result()
  end

  defp next_version_number(procedure_id) do
    ProcedureVersion
    |> where([v], v.procedure_id == ^procedure_id)
    |> select([v], max(v.version_number))
    |> Repo.one()
    |> case do
      nil -> 1
      max_version -> max_version + 1
    end
  end

  defp build_version_attrs(attrs, procedure_id, version_number, user_id) do
    attrs
    |> Map.put(:procedure_id, procedure_id)
    |> Map.put(:version_number, version_number)
    |> Map.put_new(:status, :draft)
    |> maybe_put_created_by(user_id)
  end

  defp maybe_put_created_by(attrs, nil), do: attrs
  defp maybe_put_created_by(attrs, user_id), do: Map.put_new(attrs, :created_by_id, user_id)

  defp build_version_created_attrs(attrs, procedure_id, version_number) do
    source_code = get_in(attrs, [:source]) || get_in(attrs, ["source"])

    %{
      procedure_id: procedure_id,
      version_number: version_number,
      source_code: snippet_source(source_code)
    }
  end

  defp snippet_source(source_code) when is_map(source_code) do
    source_code
    |> Jason.encode!()
    |> String.slice(0, 500)
  end

  defp snippet_source(_source_code), do: nil

  defp version_recording_attrs(procedure, user_id, version_id) do
    %{
      organization_id: procedure.organization_id,
      mission_id: procedure.mission_id,
      bucket_id: get_mission_bucket_id(procedure.mission_id),
      aggregate_type: "ProcedureVersion",
      aggregate_id: version_id,
      actor_id: user_id,
      actor_type: if(user_id, do: "user", else: "system"),
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize_version_result({:ok, %{version: version}}), do: {:ok, version}
  defp normalize_version_result({:error, :version, changeset, _}), do: {:error, changeset}
  defp normalize_version_result({:error, _step, changeset, _}), do: {:error, changeset}

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
      version = Repo.preload(version, :procedure)

      Multi.new()
      |> Multi.update(
        :version,
        ProcedureVersion.submit_changeset(version, %{
          status: :in_review,
          submitted_at: DateTime.utc_now(),
          submitted_by_id: user_id
        })
      )
      |> Outbox.append(:outbox, fn %{version: v} ->
        %{
          organization_id: version.procedure.organization_id,
          mission_id: version.procedure.mission_id,
          event_type: "procedure_submitted",
          aggregate_type: "procedure_version",
          aggregate_id: v.id,
          actor_id: user_id,
          actor_type: "user",
          payload: %{
            procedure_id: version.procedure_id,
            procedure_name: version.procedure.name,
            version_number: version.version_number
          }
        }
      end)
      |> Recordings.append(:submitted, ProcedureVersionSubmitted, %{note: nil}, fn %{version: v} ->
        %{
          organization_id: version.procedure.organization_id,
          mission_id: version.procedure.mission_id,
          bucket_id: get_mission_bucket_id(version.procedure.mission_id),
          aggregate_type: "ProcedureVersion",
          aggregate_id: v.id,
          actor_id: user_id,
          actor_type: "user",
          timestamp: DateTime.utc_now()
        }
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{version: updated}} -> {:ok, updated}
        {:error, _step, changeset, _} -> {:error, changeset}
      end
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
      version = Repo.preload(version, :procedure)

      Repo.transaction(fn ->
        # Delete any existing approvals
        from(a in ProcedureApproval, where: a.procedure_version_id == ^version.id)
        |> Repo.delete_all()

        updated =
          version
          |> ProcedureVersion.withdrawal_changeset(%{})
          |> Repo.update!()

        # Record the withdrawal
        record_version_event(updated, user_id, ProcedureVersionWithdrawn, %{})

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
    version = Repo.preload(version, :procedure)

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
        record_version_event(version, user_id, ProcedureApprovalAdded, %{
          decision: to_string(decision),
          comment: comment
        })

        # Handle decision consequences and emit outbox event
        updated_version = handle_approval_decision(version, user_id, decision, comment)

        # Emit outbox event for the approval/rejection
        event_type =
          if decision == :approved, do: "procedure_approved", else: "procedure_rejected"

        {:ok, _} =
          Outbox.insert(%{
            organization_id: version.procedure.organization_id,
            mission_id: version.procedure.mission_id,
            event_type: event_type,
            aggregate_type: "procedure_version",
            aggregate_id: version.id,
            actor_id: user_id,
            actor_type: "user",
            payload: %{
              procedure_id: version.procedure_id,
              procedure_name: version.procedure.name,
              version_number: version.version_number,
              reason: comment
            }
          })

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

  Returns recordings for the version aggregate with their recordables loaded.

  ## Options

  - `:limit` - Maximum number of events to return (default: 100)
  """
  def list_version_events(version_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Recordings.list_aggregate_recordings(
      "ProcedureVersion",
      nil,
      Keyword.merge(opts, aggregate_id: version_id, limit: limit)
    )
    |> Recordings.load_recordables_for_recordings()
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

    record_version_event(updated, user_id, ProcedureVersionRejected, %{reason: reason})

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

      record_version_event(updated, user_id, ProcedureVersionApproved, %{})

      # Emit outbox event for finalization
      {:ok, _} =
        Outbox.insert(%{
          organization_id: version.procedure.organization_id,
          mission_id: version.procedure.mission_id,
          event_type: "procedure_finalized",
          aggregate_type: "procedure_version",
          aggregate_id: version.id,
          actor_id: user_id,
          actor_type: "user",
          payload: %{
            procedure_id: version.procedure_id,
            procedure_name: version.procedure.name,
            version_number: version.version_number
          }
        })

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

  defp record_version_event(
         %ProcedureVersion{} = version,
         user_id,
         recordable_module,
         recordable_attrs
       ) do
    version = Repo.preload(version, :procedure)

    # Look up the mission's bucket (procedures are scoped to missions)
    bucket_id = get_mission_bucket_id(version.procedure.mission_id)

    recording_attrs = %{
      organization_id: version.procedure.organization_id,
      bucket_id: bucket_id,
      aggregate_type: "ProcedureVersion",
      aggregate_id: version.id,
      actor_id: user_id,
      actor_type: if(user_id, do: "user", else: "system"),
      timestamp: DateTime.utc_now()
    }

    case Recordings.create(recordable_module, recordable_attrs, recording_attrs) do
      {:ok, _} -> :ok
      # Don't fail for recording errors
      {:error, _, _, _} -> :ok
    end
  end

  defp get_mission_bucket_id(nil), do: nil

  defp get_mission_bucket_id(mission_id) do
    case Cadence.Buckets.get_bucket_by_bucketable("Mission", mission_id) do
      nil -> nil
      bucket -> bucket.id
    end
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
  Starts a new procedure execution.

  Starts a V2 ExecutionProcess, which creates the execution record.

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
           maybe_validate_params(parameters, version, validation_context, skip_validation),
         {:ok, resolved_target_id} <- resolve_target_id(target_id, procedure.mission_id),
         {:ok, pid} <-
           start_execution_process(
             version,
             validated_params,
             target_id: resolved_target_id,
             user_id: user_id,
             triggered_by: triggered_by,
             trigger_context: trigger_context
           ) do
      {:ok, Cadence.Procedures.V2.ExecutionProcess.get_execution(pid)}
    end
  end

  defp maybe_validate_params(params, _version, _context, true), do: {:ok, params}

  defp maybe_validate_params(params, version, context, false) do
    case Parameters.validate(params, version.parameters_schema, context) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, {:validation, errors}}
    end
  end

  defp resolve_target_id(nil, _mission_id), do: {:ok, nil}

  defp resolve_target_id(target_id, mission_id) when is_binary(target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        {:ok, uuid}

      :error ->
        case Targets.get_target_by_identifier(mission_id, target_id) do
          {:ok, target} -> {:ok, target.id}
          {:error, :not_found} -> {:error, {:target_not_found, target_id}}
        end
    end
  end

  defp start_execution_process(version, params, opts) do
    DynamicSupervisor.start_child(
      Cadence.Procedures.ExecutionSupervisor,
      {Cadence.Procedures.V2.ExecutionProcess,
       [
         procedure_version: version,
         params: params,
         target_id: opts[:target_id],
         user_id: opts[:user_id],
         triggered_by: opts[:triggered_by],
         trigger_context: opts[:trigger_context]
       ]}
    )
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
         {:ok, name} <-
           resolve_import_name(organization_id, mission_id, validated, name_override),
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
