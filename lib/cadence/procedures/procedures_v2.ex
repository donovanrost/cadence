defmodule Cadence.Procedures.V2 do
  @moduledoc """
  Context functions for Procedures V2 (block-based steps).

  This module provides the public API for the normalized procedure
  model with sections, steps, and blocks.

  ## Key Capabilities

  - **Normalized structure** - Sections, steps, and blocks are separate records
  - **Block-based content** - Steps contain typed blocks (text, inputs, telemetry, commands)
  - **Operator-paced execution** - Steps require explicit signoff
  - **Rich collaboration** - Comments and suggested edits during execution

  ## Usage

      # Create a section with steps and blocks
      {:ok, section} = V2.create_section(version_id, %{name: "Pre-Flight", position: 1})
      {:ok, step} = V2.create_step(section.id, %{name: "power_check", position: 1})
      {:ok, block} = V2.create_block(step.id, %{block_type: :telemetry_check, ...})

      # Start v2 execution
      {:ok, execution} = V2.start_execution(version, params, opts)

      # Operator interactions
      :ok = V2.submit_block_input(execution.id, step_id, block_id, value, user_id: user.id)
      :ok = V2.sign_off_step_v2(execution.id, step_id, "operator", nil, user_id: user.id)
  """

  import Ecto.Query

  alias Cadence.Procedures.{
    DataSourceConfig,
    ExecutionComment,
    Parameters,
    ProcedureBlock,
    ProcedureExecution,
    ProcedureSection,
    ProcedureStep,
    ProcedureVersion,
    Snippet,
    StepExecution,
    StepSignoff,
    SuggestedEdit
  }

  alias Cadence.Repo
  alias Cadence.Targets

  # ============================================================================
  # Sections
  # ============================================================================

  @doc """
  Lists sections for a procedure version.
  """
  def list_sections(procedure_version_id) do
    ProcedureSection
    |> where([s], s.procedure_version_id == ^procedure_version_id)
    |> order_by([s], s.position)
    |> Repo.all()
  end

  @doc """
  Lists sections with steps and blocks preloaded.
  """
  def list_sections_with_steps(procedure_version_id) do
    ProcedureSection
    |> where([s], s.procedure_version_id == ^procedure_version_id)
    |> order_by([s], s.position)
    |> preload(
      steps:
        ^from(st in ProcedureStep,
          order_by: st.position,
          preload: [blocks: ^from(b in ProcedureBlock, order_by: b.position)]
        )
    )
    |> Repo.all()
  end

  @doc """
  Gets a section by ID.
  """
  def get_section(id), do: Repo.get(ProcedureSection, id)
  def get_section!(id), do: Repo.get!(ProcedureSection, id)

  @doc """
  Creates a section in a procedure version.
  """
  def create_section(procedure_version_id, attrs) do
    attrs = Map.put(attrs, :procedure_version_id, procedure_version_id)

    %ProcedureSection{}
    |> ProcedureSection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a section.
  """
  def update_section(%ProcedureSection{} = section, attrs) do
    section
    |> ProcedureSection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a section and all its steps/blocks.
  """
  def delete_section(%ProcedureSection{} = section) do
    Repo.delete(section)
  end

  @doc """
  Reorders sections within a version.

  Takes a list of section IDs in the desired order.
  """
  def reorder_sections(procedure_version_id, section_ids) do
    Repo.transaction(fn ->
      section_ids
      |> Enum.with_index()
      |> Enum.each(fn {section_id, index} ->
        from(s in ProcedureSection,
          where: s.id == ^section_id and s.procedure_version_id == ^procedure_version_id
        )
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  # ============================================================================
  # Steps
  # ============================================================================

  @doc """
  Lists steps for a section.
  """
  def list_steps(section_id) do
    ProcedureStep
    |> where([s], s.section_id == ^section_id)
    |> order_by([s], s.position)
    |> Repo.all()
  end

  @doc """
  Gets a step by ID.
  """
  def get_step(id), do: Repo.get(ProcedureStep, id)
  def get_step!(id), do: Repo.get!(ProcedureStep, id)

  @doc """
  Gets a step with blocks preloaded.
  """
  def get_step_with_blocks!(id) do
    ProcedureStep
    |> Repo.get!(id)
    |> Repo.preload(blocks: from(b in ProcedureBlock, order_by: b.position))
  end

  @doc """
  Creates a step in a section.
  """
  def create_step(section_id, attrs) do
    attrs = Map.put(attrs, :section_id, section_id)

    %ProcedureStep{}
    |> ProcedureStep.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a step.
  """
  def update_step(%ProcedureStep{} = step, attrs) do
    step
    |> ProcedureStep.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a step and all its blocks.
  """
  def delete_step(%ProcedureStep{} = step) do
    Repo.delete(step)
  end

  @doc """
  Reorders steps within a section.
  """
  def reorder_steps(section_id, step_ids) do
    Repo.transaction(fn ->
      step_ids
      |> Enum.with_index()
      |> Enum.each(fn {step_id, index} ->
        from(s in ProcedureStep,
          where: s.id == ^step_id and s.section_id == ^section_id
        )
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  @doc """
  Moves a step to a different section.
  """
  def move_step(%ProcedureStep{} = step, new_section_id, new_position) do
    step
    |> Ecto.Changeset.change(%{section_id: new_section_id, position: new_position})
    |> Repo.update()
  end

  # ============================================================================
  # Blocks
  # ============================================================================

  @doc """
  Lists blocks for a step.
  """
  def list_blocks(step_id) do
    ProcedureBlock
    |> where([b], b.step_id == ^step_id)
    |> order_by([b], b.position)
    |> Repo.all()
  end

  @doc """
  Gets a block by ID.
  """
  def get_block(id), do: Repo.get(ProcedureBlock, id)
  def get_block!(id), do: Repo.get!(ProcedureBlock, id)

  @doc """
  Creates a block in a step.
  """
  def create_block(step_id, attrs) do
    attrs = Map.put(attrs, :step_id, step_id)

    %ProcedureBlock{}
    |> ProcedureBlock.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a block.
  """
  def update_block(%ProcedureBlock{} = block, attrs) do
    block
    |> ProcedureBlock.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a block.
  """
  def delete_block(%ProcedureBlock{} = block) do
    Repo.delete(block)
  end

  @doc """
  Reorders blocks within a step.
  """
  def reorder_blocks(step_id, block_ids) do
    Repo.transaction(fn ->
      block_ids
      |> Enum.with_index()
      |> Enum.each(fn {block_id, index} ->
        from(b in ProcedureBlock,
          where: b.id == ^block_id and b.step_id == ^step_id
        )
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  # ============================================================================
  # Execution (V2 - Operator-Paced)
  # ============================================================================

  @doc """
  Starts a v2 procedure execution.

  This uses the new step-by-step executor with operator signoffs.

  ## Options

  - `:target_id` - Target spacecraft
  - `:user_id` - User starting execution
  - `:triggered_by` - Trigger type (:manual, :schedule, :event)
  - `:trigger_context` - Additional trigger context
  """
  def start_execution(%ProcedureVersion{} = version, params \\ %{}, opts \\ []) do
    version = Repo.preload(version, :procedure)
    skip_validation = Keyword.get(opts, :skip_validation, false)
    mission_id = version.procedure.mission_id

    validation_context = %{
      mission_id: mission_id,
      organization_id: version.procedure.organization_id
    }

    with {:ok, validated_params} <-
           maybe_validate_params(params, version, validation_context, skip_validation),
         {:ok, target_id} <- resolve_target_id(opts[:target_id], mission_id),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             Cadence.Procedures.ExecutionSupervisor,
             {Cadence.Procedures.V2.ExecutionProcess,
              [
                procedure_version: version,
                params: validated_params,
                target_id: target_id,
                user_id: opts[:user_id],
                triggered_by: opts[:triggered_by],
                trigger_context: opts[:trigger_context]
              ]}
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

  @doc """
  Gets a v2 execution with step executions preloaded.
  """
  def get_execution_with_steps(execution_id) do
    ProcedureExecution
    |> Repo.get(execution_id)
    |> Repo.preload([
      :procedure_version,
      step_executions: [step: [:section, :blocks], signoffs: :user, block_executions: :block]
    ])
  end

  @doc """
  Lists step executions for a procedure execution.
  """
  def list_step_executions(execution_id) do
    StepExecution
    |> where([se], se.procedure_execution_id == ^execution_id)
    |> preload([:step, :signoffs])
    |> Repo.all()
  end

  @doc """
  Gets a step execution by ID.
  """
  def get_step_execution(id), do: Repo.get(StepExecution, id)
  def get_step_execution!(id), do: Repo.get!(StepExecution, id)

  # ============================================================================
  # V2 Runtime Execution Operations (via ExecutionProcess)
  # ============================================================================
  # These functions provide the public API for interacting with running
  # V2 procedure executions. They coordinate between the persistence layer
  # and the runtime ExecutionProcess GenServer.
  # ============================================================================

  alias Cadence.Procedures.V2.{ExecutionProcess, ExecutionQueries}

  @doc """
  Submits an input value for a block during execution.

  Finds or starts the ExecutionProcess and delegates to it.

  ## Returns
  - `:ok` on success
  - `{:error, :not_found}` if execution not found
  - `{:error, reason}` on failure
  """
  def submit_block_input(execution_id, step_id, block_id, value, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.submit_input(pid, step_id, block_id, value, user_id)
    end
  end

  @doc """
  Signs off a step with the given role.

  ## Options
  - `:user_id` - User ID for context (required if process not already started)
  """
  def sign_off_step_v2(execution_id, step_id, role, note \\ nil, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.sign_off(pid, step_id, role, note, user_id)
    end
  end

  @doc """
  Marks a step as complete (for manual mode).
  """
  def complete_step_v2(execution_id, step_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.complete_step(pid, step_id)
    end
  end

  @doc """
  Skips a step with a reason.
  """
  def skip_step_v2(execution_id, step_id, reason, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.skip_step(pid, step_id, reason, user_id)
    end
  end

  @doc """
  Executes a command block manually.
  """
  def execute_block(execution_id, step_id, block_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.execute_block(pid, step_id, block_id)
    end
  end

  @doc """
  Retries a failed block.
  """
  def retry_block(execution_id, step_id, block_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.retry_block(pid, step_id, block_id)
    end
  end

  @doc """
  Retries all automation in a step.
  """
  def retry_step(execution_id, step_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.retry_step(pid, step_id)
    end
  end

  @doc """
  Pauses an execution.
  """
  def pause_execution_v2(execution_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.pause(pid)
    end
  end

  @doc """
  Resumes a paused execution.
  """
  def resume_execution_v2(execution_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.resume(pid)
    end
  end

  @doc """
  Aborts an execution with a reason.
  """
  def abort_execution(execution_id, reason, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      ExecutionProcess.abort(pid, reason)
    end
  end

  @doc """
  Gets the current execution state from the running process.
  """
  def get_execution_state(execution_id, opts \\ []) do
    with {:ok, pid} <- get_or_start_process(execution_id, opts) do
      {:ok, ExecutionProcess.get_execution(pid)}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp get_or_start_process(execution_id, opts) do
    case ExecutionProcess.whereis(execution_id) do
      nil ->
        # Verify execution exists before starting
        case ExecutionQueries.get_execution(execution_id) do
          nil -> {:error, :not_found}
          _execution -> ExecutionProcess.start_or_attach(execution_id, opts)
        end

      pid ->
        {:ok, pid}
    end
  end

  # ============================================================================
  # Comments
  # ============================================================================

  @doc """
  Lists comments for an execution.
  """
  def list_comments(execution_id, opts \\ []) do
    step_execution_id = Keyword.get(opts, :step_execution_id)
    include_replies = Keyword.get(opts, :include_replies, true)

    query =
      ExecutionComment
      |> where([c], c.procedure_execution_id == ^execution_id)
      |> order_by([c], asc: c.inserted_at)
      |> preload(:user)

    query =
      if step_execution_id do
        where(query, [c], c.step_execution_id == ^step_execution_id)
      else
        query
      end

    query =
      if include_replies do
        query
      else
        where(query, [c], is_nil(c.parent_comment_id))
      end

    Repo.all(query)
  end

  @doc """
  Creates a comment on an execution or step.
  """
  def create_comment(attrs) do
    %ExecutionComment{}
    |> ExecutionComment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Replies to a comment.
  """
  def reply_to_comment(%ExecutionComment{} = parent, attrs) do
    attrs =
      attrs
      |> Map.put(:parent_comment_id, parent.id)
      |> Map.put(:procedure_execution_id, parent.procedure_execution_id)
      |> Map.put(:step_execution_id, parent.step_execution_id)

    parent
    |> ExecutionComment.reply_changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Suggested Edits (Redlines)
  # ============================================================================

  @doc """
  Gets a suggested edit by ID.
  """
  def get_suggested_edit(id), do: Repo.get(SuggestedEdit, id)
  def get_suggested_edit!(id), do: Repo.get!(SuggestedEdit, id)

  @doc """
  Lists suggested edits for an execution.
  """
  def list_suggested_edits(execution_id, opts \\ []) do
    status = Keyword.get(opts, :status)

    query =
      SuggestedEdit
      |> where([se], se.procedure_execution_id == ^execution_id)
      |> order_by([se], asc: se.inserted_at)
      |> preload([:suggested_by, :resolved_by])

    query =
      if status do
        where(query, [se], se.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Creates a suggested edit.
  """
  def create_suggested_edit(attrs) do
    %SuggestedEdit{}
    |> SuggestedEdit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Accepts a suggested edit.
  """
  def accept_suggested_edit(%SuggestedEdit{} = edit, user_id, note \\ nil) do
    edit
    |> SuggestedEdit.accept_changeset(user_id, note)
    |> Repo.update()
  end

  @doc """
  Rejects a suggested edit.
  """
  def reject_suggested_edit(%SuggestedEdit{} = edit, user_id, note) do
    edit
    |> SuggestedEdit.reject_changeset(user_id, note)
    |> Repo.update()
  end

  # ============================================================================
  # Snippets
  # ============================================================================

  @doc """
  Lists snippets for an organization.
  """
  def list_snippets(organization_id, opts \\ []) do
    snippet_type = Keyword.get(opts, :type)
    tags = Keyword.get(opts, :tags, [])

    query =
      Snippet
      |> where([s], s.organization_id == ^organization_id)
      |> order_by([s], asc: s.name)

    query =
      if snippet_type do
        where(query, [s], s.snippet_type == ^snippet_type)
      else
        query
      end

    query =
      if length(tags) > 0 do
        where(query, [s], fragment("? && ?", s.tags, ^tags))
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a snippet by ID.
  """
  def get_snippet(id), do: Repo.get(Snippet, id)
  def get_snippet!(id), do: Repo.get!(Snippet, id)

  @doc """
  Creates a snippet.
  """
  def create_snippet(attrs) do
    %Snippet{}
    |> Snippet.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a snippet.
  """
  def update_snippet(%Snippet{} = snippet, attrs) do
    snippet
    |> Snippet.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a snippet.
  """
  def delete_snippet(%Snippet{} = snippet) do
    Repo.delete(snippet)
  end

  @doc """
  Creates a snippet from an existing step.
  """
  def create_snippet_from_step(%ProcedureStep{} = step, organization_id, user_id, attrs) do
    step = Repo.preload(step, :blocks)

    content = %{
      "name" => step.name,
      "title" => step.title,
      "requires_signoff" => step.requires_signoff,
      "required_roles" => step.required_roles,
      "signoff_logic" => to_string(step.signoff_logic),
      "depends_on" => step.depends_on,
      "dependency_logic" => to_string(step.dependency_logic),
      "condition" => step.condition,
      "on_fail" => to_string(step.on_fail),
      "blocks" => Enum.map(step.blocks, &block_to_map/1)
    }

    snippet_attrs =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:created_by_id, user_id)
      |> Map.put(:snippet_type, :step)
      |> Map.put(:content, content)

    create_snippet(snippet_attrs)
  end

  defp block_to_map(block) do
    %{
      "block_type" => to_string(block.block_type),
      "name" => block.name,
      "label" => block.label,
      "required" => block.required,
      "content" => block.content
    }
  end

  @doc """
  Inserts a snippet into a section as a new step.
  """
  def insert_snippet(%Snippet{snippet_type: :step} = snippet, section_id, position) do
    Repo.transaction(fn ->
      {:ok, step} = create_step(section_id, build_step_attrs(snippet, section_id, position))
      insert_blocks(step, snippet.content)
      Repo.preload(step, :blocks)
    end)
  end

  defp build_step_attrs(snippet, section_id, position) do
    content = snippet.content

    %{
      section_id: section_id,
      name: content["name"],
      title: content["title"],
      position: position,
      requires_signoff: content["requires_signoff"] || true,
      required_roles: content["required_roles"] || [],
      signoff_logic: String.to_existing_atom(content["signoff_logic"] || "any"),
      depends_on: content["depends_on"] || [],
      dependency_logic: String.to_existing_atom(content["dependency_logic"] || "all"),
      condition: content["condition"],
      on_fail: String.to_existing_atom(content["on_fail"] || "abort")
    }
  end

  defp insert_blocks(step, content) do
    content
    |> Map.get("blocks", [])
    |> Enum.each(&create_step_block(step, &1))
  end

  defp create_step_block(step, block_data) do
    block_attrs = %{
      step_id: step.id,
      block_type: String.to_existing_atom(block_data["block_type"]),
      position: block_data["position"] || 0,
      name: block_data["name"],
      label: block_data["label"],
      required: block_data["required"] || false,
      content: block_data["content"] || %{}
    }

    create_block(step.id, block_attrs)
  end

  # ============================================================================
  # Data Source Configs
  # ============================================================================

  @doc """
  Lists data source configs for a mission.
  """
  def list_data_source_configs(mission_id) do
    DataSourceConfig
    |> where([d], d.mission_id == ^mission_id)
    |> order_by([d], desc: d.priority)
    |> Repo.all()
  end

  @doc """
  Gets a data source config by ID.
  """
  def get_data_source_config(id), do: Repo.get(DataSourceConfig, id)

  @doc """
  Creates a data source config.
  """
  def create_data_source_config(attrs) do
    %DataSourceConfig{}
    |> DataSourceConfig.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a data source config.
  """
  def update_data_source_config(%DataSourceConfig{} = config, attrs) do
    config
    |> DataSourceConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a data source config.
  """
  def delete_data_source_config(%DataSourceConfig{} = config) do
    Repo.delete(config)
  end

  @doc """
  Gets the default data source for a mission.
  """
  def get_default_data_source(mission_id) do
    DataSourceConfig
    |> where([d], d.mission_id == ^mission_id and d.is_default == true)
    |> Repo.one()
  end

  # ============================================================================
  # Signoffs
  # ============================================================================

  @doc """
  Lists signoffs for a step execution.
  """
  def list_signoffs(step_execution_id) do
    StepSignoff
    |> where([s], s.step_execution_id == ^step_execution_id)
    |> preload(:user)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets signoff summary for a step execution.
  """
  def get_signoff_summary(step_execution_id) do
    step_execution =
      StepExecution
      |> Repo.get!(step_execution_id)
      |> Repo.preload([:step, :signoffs])

    step = step_execution.step
    signoffs = step_execution.signoffs
    required_roles = step.required_roles || []

    %{
      required_roles: required_roles,
      signoff_logic: step.signoff_logic,
      signoffs: signoffs,
      is_complete: StepSignoff.requirements_met?(signoffs, required_roles, step.signoff_logic),
      missing_roles: StepSignoff.missing_roles(signoffs, required_roles, step.signoff_logic)
    }
  end
end
