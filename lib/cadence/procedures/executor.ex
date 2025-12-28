defmodule Cadence.Procedures.Executor do
  @moduledoc """
  Step-by-step procedure executor with operator interaction.

  Unlike the DAG executor which runs automatically, this executor is
  operator-paced. Steps are activated when dependencies are satisfied,
  but require explicit signoff before completing.

  ## Execution Modes

  - `:manual` - Operator must explicitly advance each step
  - `:assisted` - Auto-advance through non-signoff steps, pause at signoffs
  - `:automatic` - Full automatic execution (legacy DAG behavior)

  ## Step Lifecycle

  1. Step becomes **ready** when dependencies are satisfied
  2. Step is **activated** - operator can interact with blocks
  3. Operator fills inputs, telemetry is evaluated
  4. Step enters **awaiting_signoff** when work is complete
  5. Operator **signs off** with appropriate role
  6. Step is **completed** and dependent steps become ready

  ## Events

  The executor broadcasts events via PubSub for real-time UI updates:

  - `{:step_activated, step_execution}`
  - `{:step_completed, step_execution}`
  - `{:block_value_entered, block_execution}`
  - `{:signoff_added, signoff}`
  - `{:execution_completed, execution}`
  - `{:execution_failed, execution, error}`

  ## Usage

      # Start a procedure
      {:ok, execution} = Executor.start(procedure_version, params, opts)

      # Enter a value in an input block
      {:ok, block_exec} = Executor.enter_block_value(execution, step_exec, block, value, user)

      # Sign off a step
      {:ok, signoff} = Executor.sign_off_step(execution, step_exec, user, "operator")

      # Skip a step
      {:ok, step_exec} = Executor.skip_step(execution, step_exec, user, "Not applicable")
  """

  require Logger

  alias Cadence.Procedures.{
    BlockExecution,
    ProcedureBlock,
    ProcedureExecution,
    ProcedureSection,
    ProcedureStep,
    ProcedureVersion,
    StepExecution,
    StepSignoff
  }

  alias Cadence.Procedures.DataSources.{CVT, TelemetryResolver}

  alias Cadence.Repo

  import Ecto.Query

  @type execution_opts :: [
          target_id: String.t(),
          triggered_by: atom(),
          trigger_context: map(),
          user_id: String.t()
        ]

  # ─────────────────────────────────────────────────────────────
  # Starting Execution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Starts execution of a procedure version.

  Creates a ProcedureExecution record, initializes StepExecution records
  for all steps, and activates steps with no dependencies.

  ## Options

  - `:target_id` - Target spacecraft for telemetry/commands
  - `:triggered_by` - How execution was triggered (:manual, :schedule, :event)
  - `:trigger_context` - Additional context about trigger
  - `:user_id` - User starting the execution
  """
  @spec start(ProcedureVersion.t(), map(), execution_opts()) ::
          {:ok, ProcedureExecution.t()} | {:error, term()}
  def start(procedure_version, params \\ %{}, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, execution} <- create_execution(procedure_version, params, opts),
           {:ok, execution} <- create_step_executions(execution, procedure_version),
           {:ok, execution} <- activate_ready_steps(execution) do
        broadcast_started(execution)
        execution
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_execution(procedure_version, params, opts) do
    # Extract target from params if not explicitly provided in opts
    target_id = opts[:target_id] || extract_target_from_params(params)

    attrs = %{
      procedure_id: procedure_version.procedure_id,
      procedure_version_id: procedure_version.id,
      organization_id: get_organization_id(procedure_version),
      mission_id: get_mission_id(procedure_version),
      target_id: target_id,
      started_by_id: opts[:user_id],
      parameters: params,
      status: :running,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      triggered_by: opts[:triggered_by] || :manual,
      trigger_context: opts[:trigger_context] || %{},
      # V2 executor - always recoverable, not subject to orphaned cleanup
      execution_version: :v2
    }

    %ProcedureExecution{}
    |> ProcedureExecution.changeset(attrs)
    |> Repo.insert()
  end

  defp create_step_executions(execution, procedure_version) do
    # Load all sections and steps
    sections =
      ProcedureSection
      |> where([s], s.procedure_version_id == ^procedure_version.id)
      |> order_by([s], s.position)
      |> preload(steps: ^from(st in ProcedureStep, order_by: st.position))
      |> Repo.all()

    # Create StepExecution for each step
    step_executions =
      sections
      |> Enum.flat_map(& &1.steps)
      |> Enum.map(fn step ->
        %{
          procedure_execution_id: execution.id,
          step_id: step.id,
          status: :pending,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      end)

    {_count, _} = Repo.insert_all(StepExecution, step_executions)

    {:ok, Repo.preload(execution, :step_executions)}
  end

  # ─────────────────────────────────────────────────────────────
  # Step Activation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Activates all steps whose dependencies are satisfied.
  """
  @spec activate_ready_steps(ProcedureExecution.t()) :: {:ok, ProcedureExecution.t()}
  def activate_ready_steps(execution) do
    ready_steps = find_ready_steps(execution)

    Enum.each(ready_steps, fn step_exec ->
      activate_step(execution, step_exec)
    end)

    {:ok, reload_execution(execution)}
  end

  @doc """
  Activates a specific step for operator interaction.
  """
  @spec activate_step(ProcedureExecution.t(), StepExecution.t()) ::
          {:ok, StepExecution.t()} | {:error, term()}
  def activate_step(execution, step_execution) do
    step_execution = Repo.preload(step_execution, :step)

    # Check if step should be skipped due to condition
    case evaluate_step_condition(step_execution.step, execution) do
      {:ok, true} ->
        # Condition passed, activate the step
        do_activate_step(execution, step_execution)

      {:ok, false} ->
        # Condition failed, skip the step
        do_skip_step_for_condition(execution, step_execution)

      {:error, reason} ->
        Logger.warning("Failed to evaluate step condition: #{inspect(reason)}")
        # Default to activating on condition error
        do_activate_step(execution, step_execution)
    end
  end

  defp do_activate_step(execution, step_execution) do
    step_execution = Repo.preload(step_execution, step: :blocks)

    with {:ok, step_exec} <- update_step_status(step_execution, :active),
         {:ok, step_exec} <- create_block_executions(step_exec) do
      broadcast_step_activated(execution, step_exec)
      {:ok, step_exec}
    end
  end

  defp do_skip_step_for_condition(execution, step_execution) do
    changeset =
      step_execution
      |> StepExecution.skip_changeset(%{
        skipped_reason: "Step condition evaluated to false"
      })

    with {:ok, step_exec} <- Repo.update(changeset) do
      broadcast_step_skipped(execution, step_exec)
      # Activate next steps
      activate_ready_steps(execution)
      {:ok, step_exec}
    end
  end

  defp update_step_status(step_execution, :active) do
    step_execution
    |> StepExecution.activate_changeset()
    |> Repo.update()
  end

  defp create_block_executions(step_execution) do
    blocks = step_execution.step.blocks

    block_executions =
      Enum.map(blocks, fn block ->
        %{
          step_execution_id: step_execution.id,
          block_id: block.id,
          status: :pending,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      end)

    if length(block_executions) > 0 do
      {_count, _} = Repo.insert_all(BlockExecution, block_executions)
    end

    {:ok, Repo.preload(step_execution, :block_executions, force: true)}
  end

  # ─────────────────────────────────────────────────────────────
  # Block Value Entry
  # ─────────────────────────────────────────────────────────────

  @doc """
  Enters a value into an input block.

  ## Parameters

  - `execution` - The procedure execution
  - `step_execution` - The step containing the block
  - `block` - The block to enter value into
  - `value` - The value to enter (structure depends on block type)
  - `user` - The user entering the value
  """
  @spec enter_block_value(
          ProcedureExecution.t(),
          StepExecution.t(),
          ProcedureBlock.t(),
          map(),
          map()
        ) :: {:ok, BlockExecution.t()} | {:error, term()}
  def enter_block_value(execution, step_execution, block, value, user) do
    with :ok <- validate_step_active(step_execution),
         :ok <- validate_block_accepts_input(block),
         {:ok, validated_value} <- validate_block_value(block, value),
         {:ok, block_exec} <- find_block_execution(step_execution, block),
         {:ok, block_exec} <- save_block_value(block_exec, validated_value, user) do
      broadcast_block_value_entered(execution, step_execution, block_exec)

      # Handle step progression based on execution mode
      handle_step_progression_after_input(execution, step_execution)

      {:ok, block_exec}
    end
  end

  defp handle_step_progression_after_input(execution, step_execution) do
    execution = Repo.preload(execution, :procedure_version)
    execution_mode = execution.procedure_version.execution_mode || :manual
    step_execution = Repo.preload(step_execution, [:step, :block_executions, :signoffs])

    case execution_mode do
      :manual ->
        maybe_transition_to_awaiting_signoff(execution, step_execution)

      mode when mode in [:assisted, :automatic] ->
        handle_auto_progression(execution, step_execution)

      _ ->
        :ok
    end
  end

  defp handle_auto_progression(execution, step_execution) do
    case all_required_complete?(step_execution) do
      true -> maybe_complete_after_inputs(execution, step_execution)
      false -> :ok
    end
  end

  defp maybe_complete_after_inputs(execution, step_execution) do
    if step_execution.step.requires_signoff do
      maybe_transition_to_awaiting_signoff(execution, step_execution)
    else
      complete_step(execution, step_execution)
    end
  end

  defp validate_step_active(%StepExecution{status: status})
       when status in [:active, :awaiting_signoff] do
    :ok
  end

  defp validate_step_active(%StepExecution{status: status}) do
    {:error, {:step_not_active, status}}
  end

  defp validate_block_accepts_input(block) do
    if ProcedureBlock.input_block?(block) do
      :ok
    else
      {:error, {:block_not_input, block.block_type}}
    end
  end

  defp validate_block_value(block, value) do
    # First normalize the value into the expected map format
    normalized_value = normalize_input_value(block.block_type, value)

    # Then validate based on block type
    case block.block_type do
      :number_input ->
        validate_number_input(block, normalized_value)

      :text_input ->
        validate_text_input(block, normalized_value)

      _ ->
        {:ok, normalized_value}
    end
  end

  # Normalize raw input values into the expected map structure
  defp normalize_input_value(:text_input, value) when is_binary(value), do: %{text: value}
  defp normalize_input_value(:text_input, %{text: _} = value), do: value
  defp normalize_input_value(:text_input, %{"text" => text}), do: %{text: text}

  defp normalize_input_value(:number_input, value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> %{number: num}
      {num, _} -> %{number: num}
      :error -> %{number: nil}
    end
  end

  defp normalize_input_value(:number_input, value) when is_number(value), do: %{number: value}
  defp normalize_input_value(:number_input, %{number: _} = value), do: value
  defp normalize_input_value(:number_input, %{"number" => num}), do: %{number: num}

  defp normalize_input_value(:select_input, value) when is_binary(value), do: %{selected: value}
  defp normalize_input_value(:select_input, %{selected: _} = value), do: value
  defp normalize_input_value(:select_input, %{"selected" => sel}), do: %{selected: sel}

  defp normalize_input_value(:checkbox_input, value) when is_boolean(value), do: %{checked: value}
  defp normalize_input_value(:checkbox_input, "true"), do: %{checked: true}
  defp normalize_input_value(:checkbox_input, "false"), do: %{checked: false}
  defp normalize_input_value(:checkbox_input, %{checked: _} = value), do: value
  defp normalize_input_value(:checkbox_input, %{"checked" => checked}), do: %{checked: checked}

  # For other input types or already normalized values, pass through as map
  defp normalize_input_value(_block_type, value) when is_map(value), do: value
  defp normalize_input_value(_block_type, value) when is_binary(value), do: %{value: value}
  defp normalize_input_value(_block_type, value), do: %{value: value}

  defp validate_number_input(block, %{number: num} = value) when is_number(num) do
    content = block.content
    min = content["min"] || content[:min]
    max = content["max"] || content[:max]

    cond do
      min && num < min -> {:error, {:below_minimum, min}}
      max && num > max -> {:error, {:above_maximum, max}}
      true -> {:ok, value}
    end
  end

  defp validate_number_input(_block, value), do: {:ok, value}

  defp validate_text_input(block, %{text: text} = value) when is_binary(text) do
    content = block.content
    max_length = content["max_length"] || content[:max_length]

    if max_length && String.length(text) > max_length do
      {:error, {:exceeds_max_length, max_length}}
    else
      {:ok, value}
    end
  end

  defp validate_text_input(_block, value), do: {:ok, value}

  defp find_block_execution(step_execution, block) do
    step_execution = Repo.preload(step_execution, :block_executions)

    case Enum.find(step_execution.block_executions, &(&1.block_id == block.id)) do
      nil -> {:error, :block_execution_not_found}
      block_exec -> {:ok, block_exec}
    end
  end

  defp save_block_value(block_exec, value, user) do
    block_exec
    |> BlockExecution.enter_value_changeset(value, user.id)
    |> Repo.update()
  end

  # ─────────────────────────────────────────────────────────────
  # Telemetry Evaluation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Evaluates telemetry blocks in a step and records results.
  """
  @spec evaluate_telemetry_blocks(ProcedureExecution.t(), StepExecution.t()) ::
          {:ok, [BlockExecution.t()]} | {:error, term()}
  def evaluate_telemetry_blocks(execution, step_execution) do
    step_execution = Repo.preload(step_execution, step: :blocks, block_executions: [])

    context = build_execution_context(execution)

    telemetry_blocks =
      step_execution.step.blocks
      |> Enum.filter(&ProcedureBlock.telemetry_block?/1)

    results =
      Enum.map(telemetry_blocks, fn block ->
        block_exec = Enum.find(step_execution.block_executions, &(&1.block_id == block.id))
        evaluate_telemetry_block(block, block_exec, context)
      end)

    {:ok, results}
  end

  defp evaluate_telemetry_block(block, block_exec, context) do
    case block.block_type do
      :telemetry_value ->
        evaluate_telemetry_value(block, block_exec, context)

      :telemetry_check ->
        evaluate_telemetry_check(block, block_exec, context)

      _ ->
        {:ok, block_exec}
    end
  end

  defp evaluate_telemetry_value(block, block_exec, context) do
    item_path = block.content["item"] || block.content[:item]

    case resolve_and_fetch(item_path, context) do
      {:ok, reading} ->
        block_exec
        |> BlockExecution.telemetry_reading_changeset(reading)
        |> Repo.update()

      {:error, reason} ->
        Logger.warning("Failed to fetch telemetry #{item_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp evaluate_telemetry_check(block, block_exec, context) do
    item_path = block.content["item"] || block.content[:item]
    pass_criteria = block.content["pass_criteria"] || block.content[:pass_criteria]

    with {:ok, reading} <- resolve_and_fetch(item_path, context),
         {:ok, passed} <- evaluate_pass_criteria(reading.value, pass_criteria) do
      message =
        if passed, do: nil, else: "Value #{reading.value} does not satisfy: #{pass_criteria}"

      block_exec
      |> BlockExecution.telemetry_check_changeset(reading, passed, message)
      |> Repo.update()
    else
      {:error, reason} ->
        Logger.warning("Failed to evaluate telemetry check #{item_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp resolve_and_fetch(item_path, context) do
    case TelemetryResolver.resolve(item_path, context) do
      {:ok, resolved_path} ->
        CVT.get_value(resolved_path, context, [])

      {:error, _} = error ->
        error
    end
  end

  defp evaluate_pass_criteria(value, criteria) when is_number(value) and is_binary(criteria) do
    # Simple evaluation - extend as needed
    CVT.evaluate_condition("#{value} #{criteria}", %{})
    |> case do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:ok, false}
  end

  defp evaluate_pass_criteria(_value, _criteria), do: {:ok, true}

  # ─────────────────────────────────────────────────────────────
  # Step Signoff
  # ─────────────────────────────────────────────────────────────

  @doc """
  Signs off a step with the given role.

  If signoff requirements are met, the step is completed and
  dependent steps are activated.
  """
  @spec sign_off_step(
          ProcedureExecution.t(),
          StepExecution.t(),
          map(),
          String.t(),
          String.t() | nil
        ) ::
          {:ok, StepSignoff.t()} | {:error, term()}
  def sign_off_step(execution, step_execution, user, role, note \\ nil) do
    step_execution = Repo.preload(step_execution, [:step, :signoffs])
    execution = Repo.preload(execution, :procedure_version)
    execution_mode = execution.procedure_version.execution_mode || :manual

    with :ok <- validate_can_sign_off(step_execution, user, role),
         :ok <- validate_required_inputs_complete(step_execution),
         :ok <- validate_checks_passed(step_execution),
         {:ok, signoff} <- create_signoff(step_execution, user, role, note) do
      broadcast_signoff_added(execution, step_execution, signoff)

      # In assisted/automatic modes, auto-complete when signoff requirements are met
      # In manual mode, user must explicitly click "Mark Complete"
      if execution_mode in [:assisted, :automatic] and signoff_requirements_met?(step_execution) do
        complete_step(execution, step_execution)
      end

      {:ok, signoff}
    end
  end

  defp validate_can_sign_off(step_execution, _user, role) do
    step = step_execution.step
    required_roles = step.required_roles || []

    cond do
      not step.requires_signoff ->
        {:error, :signoff_not_required}

      length(required_roles) > 0 and role not in required_roles ->
        {:error, {:invalid_role, role, required_roles}}

      already_signed_off?(step_execution, role) ->
        {:error, :already_signed_off}

      true ->
        :ok
    end
  end

  defp already_signed_off?(step_execution, role) do
    Enum.any?(step_execution.signoffs, &(&1.role == role))
  end

  defp validate_required_inputs_complete(step_execution) do
    step_execution = Repo.preload(step_execution, step: :blocks, block_executions: [])

    required_blocks =
      step_execution.step.blocks
      |> Enum.filter(&(&1.required && ProcedureBlock.input_block?(&1)))

    incomplete =
      Enum.filter(required_blocks, fn block ->
        block_exec = Enum.find(step_execution.block_executions, &(&1.block_id == block.id))
        is_nil(block_exec) or is_nil(block_exec.value)
      end)

    if length(incomplete) > 0 do
      {:error, {:incomplete_required_inputs, Enum.map(incomplete, & &1.name)}}
    else
      :ok
    end
  end

  defp validate_checks_passed(step_execution) do
    step_execution = Repo.preload(step_execution, step: :blocks, block_executions: [])

    failed_checks =
      step_execution.step.blocks
      |> Enum.filter(fn block ->
        block_exec = Enum.find(step_execution.block_executions, &(&1.block_id == block.id))
        block.block_type == :telemetry_check and block_exec != nil and block_exec.passed == false
      end)

    # Check if any failed checks block signoff
    blocking_failures =
      Enum.filter(failed_checks, fn block ->
        fail_action = block.content["fail_action"] || block.content[:fail_action]
        fail_action in ["block_signoff", :block_signoff]
      end)

    if length(blocking_failures) > 0 do
      {:error, {:failed_checks, Enum.map(blocking_failures, & &1.name)}}
    else
      :ok
    end
  end

  defp create_signoff(step_execution, user, role, note) do
    %StepSignoff{}
    |> StepSignoff.changeset(%{
      step_execution_id: step_execution.id,
      user_id: user.id,
      role: role,
      note: note
    })
    |> Repo.insert()
  end

  defp signoff_requirements_met?(step_execution) do
    # Force reload to get the newly created signoff
    step_execution = Repo.preload(step_execution, [:step, :signoffs], force: true)
    step = step_execution.step

    if step.requires_signoff do
      required_roles = step.required_roles || []
      logic = step.signoff_logic || :any

      StepSignoff.requirements_met?(step_execution.signoffs, required_roles, logic)
    else
      true
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Step Completion
  # ─────────────────────────────────────────────────────────────

  @doc """
  Completes a step and activates dependent steps.

  Validates that:
  - Step is in a completable state (active or awaiting_signoff)
  - All required inputs are filled
  - All telemetry checks pass (or don't block completion)
  - Signoff requirements are met (if signoff is required)
  """
  @spec complete_step(ProcedureExecution.t(), StepExecution.t()) ::
          {:ok, StepExecution.t()} | {:error, term()}
  def complete_step(execution, step_execution) do
    step_execution = Repo.preload(step_execution, [:step, :signoffs, :block_executions])

    with :ok <- validate_step_completable(step_execution),
         :ok <- validate_required_inputs_complete(step_execution),
         :ok <- validate_checks_passed(step_execution),
         :ok <- validate_signoff_complete(step_execution),
         {:ok, step_exec} <- mark_step_completed(step_execution),
         {:ok, _execution} <- activate_ready_steps(execution) do
      broadcast_step_completed(execution, step_exec)

      # Check if all steps are complete
      if all_steps_complete?(execution) do
        complete_execution(execution)
      end

      {:ok, step_exec}
    end
  end

  defp validate_step_completable(%StepExecution{status: status})
       when status in [:active, :awaiting_signoff] do
    :ok
  end

  defp validate_step_completable(%StepExecution{status: status}) do
    {:error, {:step_not_completable, status}}
  end

  defp validate_signoff_complete(step_execution) do
    if signoff_requirements_met?(step_execution) do
      :ok
    else
      {:error, :signoff_requirements_not_met}
    end
  end

  defp mark_step_completed(step_execution) do
    step_execution
    |> StepExecution.complete_changeset(:pass)
    |> Repo.update()
  end

  # ─────────────────────────────────────────────────────────────
  # Skip Step
  # ─────────────────────────────────────────────────────────────

  @doc """
  Skips a step with the given reason.
  """
  @spec skip_step(ProcedureExecution.t(), StepExecution.t(), map(), String.t()) ::
          {:ok, StepExecution.t()} | {:error, term()}
  def skip_step(execution, step_execution, user, reason) do
    with :ok <- validate_can_skip(step_execution) do
      changeset =
        step_execution
        |> StepExecution.skip_changeset(%{
          skipped_reason: reason,
          skipped_by_id: user.id
        })

      case Repo.update(changeset) do
        {:ok, step_exec} ->
          broadcast_step_skipped(execution, step_exec)
          activate_ready_steps(execution)

          if all_steps_complete?(execution) do
            complete_execution(execution)
          end

          {:ok, step_exec}

        {:error, _} = error ->
          error
      end
    end
  end

  defp validate_can_skip(%StepExecution{status: status})
       when status in [:pending, :active, :blocked] do
    :ok
  end

  defp validate_can_skip(%StepExecution{status: status}) do
    {:error, {:cannot_skip, status}}
  end

  # ─────────────────────────────────────────────────────────────
  # Execution Completion
  # ─────────────────────────────────────────────────────────────

  defp complete_execution(execution) do
    execution
    |> Ecto.Changeset.change(%{
      status: :completed,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, execution} ->
        broadcast_execution_completed(execution)
        {:ok, execution}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fails the execution with an error.
  """
  @spec fail_execution(ProcedureExecution.t(), String.t(), StepExecution.t() | nil) ::
          {:ok, ProcedureExecution.t()}
  def fail_execution(execution, error_message, failed_step \\ nil) do
    attrs = %{
      status: :failed,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      error_message: error_message
    }

    attrs =
      if failed_step do
        Map.put(attrs, :error_step_id, failed_step.step_id)
      else
        attrs
      end

    execution
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
    |> case do
      {:ok, execution} ->
        broadcast_execution_failed(execution, error_message)
        {:ok, execution}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Pauses the execution.
  """
  @spec pause_execution(ProcedureExecution.t()) :: {:ok, ProcedureExecution.t()}
  def pause_execution(execution) do
    execution
    |> Ecto.Changeset.change(%{status: :paused})
    |> Repo.update()
    |> case do
      {:ok, execution} ->
        broadcast_execution_paused(execution)
        {:ok, execution}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Resumes a paused execution.
  """
  @spec resume_execution(ProcedureExecution.t()) :: {:ok, ProcedureExecution.t()}
  def resume_execution(execution) do
    execution
    |> Ecto.Changeset.change(%{status: :running})
    |> Repo.update()
    |> case do
      {:ok, execution} ->
        broadcast_execution_resumed(execution)
        activate_ready_steps(execution)

      {:error, _} = error ->
        error
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Helper Functions
  # ─────────────────────────────────────────────────────────────

  defp find_ready_steps(execution) do
    execution = Repo.preload(execution, step_executions: [step: :section])

    completed_step_names = get_completed_step_names(execution)

    execution.step_executions
    |> Enum.filter(fn step_exec ->
      step_exec.status == :pending and
        dependencies_satisfied?(step_exec.step, completed_step_names)
    end)
  end

  defp get_completed_step_names(execution) do
    execution.step_executions
    |> Enum.filter(&(&1.status in [:completed, :skipped]))
    |> Enum.map(& &1.step.name)
    |> MapSet.new()
  end

  defp dependencies_satisfied?(step, completed_step_names) do
    depends_on = step.depends_on || []

    if Enum.empty?(depends_on) do
      true
    else
      case step.dependency_logic do
        :all -> Enum.all?(depends_on, &MapSet.member?(completed_step_names, &1))
        :any -> Enum.any?(depends_on, &MapSet.member?(completed_step_names, &1))
      end
    end
  end

  defp evaluate_step_condition(step, execution) do
    condition = step.condition

    if is_nil(condition) or condition == "" do
      {:ok, true}
    else
      context = build_execution_context(execution)

      CVT.evaluate_condition(condition, context)
      |> case do
        {:ok, %{result: result}} -> {:ok, result}
        {:error, _} = error -> error
      end
    end
  end

  defp maybe_transition_to_awaiting_signoff(execution, step_execution) do
    step_execution = Repo.preload(step_execution, [:step, :block_executions])

    # Check if all required inputs are filled and step requires signoff
    if step_execution.step.requires_signoff and all_required_complete?(step_execution) do
      step_execution
      |> StepExecution.awaiting_signoff_changeset()
      |> Repo.update()
      |> case do
        {:ok, step_exec} ->
          broadcast_step_awaiting_signoff(execution, step_exec)

        _ ->
          :ok
      end
    end
  end

  defp all_required_complete?(step_execution) do
    step_execution = Repo.preload(step_execution, step: :blocks)

    required_input_blocks =
      step_execution.step.blocks
      |> Enum.filter(&(&1.required && ProcedureBlock.input_block?(&1)))

    Enum.all?(required_input_blocks, fn block ->
      block_exec = Enum.find(step_execution.block_executions, &(&1.block_id == block.id))
      block_exec && block_exec.status == :completed
    end)
  end

  defp all_steps_complete?(execution) do
    execution = Repo.preload(execution, :step_executions, force: true)

    Enum.all?(execution.step_executions, fn step_exec ->
      step_exec.status in [:completed, :skipped]
    end)
  end

  defp build_execution_context(execution) do
    %{
      execution_id: execution.id,
      mission_id: execution.mission_id,
      target_id: execution.target_id,
      organization_id: execution.organization_id,
      parameters: execution.parameters || %{}
    }
  end

  defp reload_execution(execution) do
    Repo.get!(ProcedureExecution, execution.id)
    |> Repo.preload(:step_executions, force: true)
  end

  defp get_organization_id(procedure_version) do
    procedure_version = Repo.preload(procedure_version, :procedure)
    procedure_version.procedure.organization_id
  end

  defp get_mission_id(procedure_version) do
    procedure_version = Repo.preload(procedure_version, :procedure)
    procedure_version.procedure.mission_id
  end

  defp extract_target_from_params(params) when is_map(params) do
    params["target"] || params["target_id"]
  end

  defp extract_target_from_params(_), do: nil

  # ─────────────────────────────────────────────────────────────
  # Broadcasting
  # ─────────────────────────────────────────────────────────────

  defp broadcast_started(execution) do
    broadcast(execution, {:procedure_started, execution})
  end

  defp broadcast_step_activated(execution, step_exec) do
    broadcast(execution, {:step_activated, step_exec})
  end

  defp broadcast_step_completed(execution, step_exec) do
    broadcast(execution, {:step_completed, step_exec})
  end

  defp broadcast_step_skipped(execution, step_exec) do
    broadcast(execution, {:step_skipped, step_exec})
  end

  defp broadcast_step_awaiting_signoff(execution, step_exec) do
    broadcast(execution, {:step_awaiting_signoff, step_exec})
  end

  defp broadcast_block_value_entered(execution, step_exec, block_exec) do
    broadcast(execution, {:block_value_entered, step_exec, block_exec})
  end

  defp broadcast_signoff_added(execution, step_exec, signoff) do
    broadcast(execution, {:signoff_added, step_exec, signoff})
  end

  defp broadcast_execution_completed(execution) do
    broadcast(execution, {:procedure_completed, execution})
  end

  defp broadcast_execution_failed(execution, error) do
    broadcast(execution, {:procedure_failed, execution, error})
  end

  defp broadcast_execution_paused(execution) do
    broadcast(execution, {:procedure_paused, execution})
  end

  defp broadcast_execution_resumed(execution) do
    broadcast(execution, {:procedure_resumed, execution})
  end

  defp broadcast(execution, message) do
    topic = "procedure_execution:#{execution.id}"
    Phoenix.PubSub.broadcast(Cadence.PubSub, topic, message)
  end
end
