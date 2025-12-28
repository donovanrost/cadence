defmodule Cadence.Procedures.V2.ExecutionProcess do
  @moduledoc """
  GenServer managing a single V2 procedure execution.

  The ExecutionProcess is the runtime coordinator for operator-paced procedures.
  It manages the execution lifecycle, delegates to the strategy for mode-specific
  behavior, and coordinates between the UI (LiveView) and automation (AutomationRunner).

  ## Responsibilities

  - Start execution and create step/block executions
  - Activate steps based on dependencies
  - Delegate to strategy for mode-specific decisions
  - Spawn AutomationRunner for automated blocks
  - Handle user interactions (input values, signoffs)
  - Handle control signals (pause, abort, resume)
  - Broadcast state changes via PubSub
  - Persist state to database

  ## Starting an Execution

      {:ok, pid} = ExecutionProcess.start_link(
        procedure_version: version,
        params: %{},
        target_id: "sat-1",
        user_id: user.id
      )

  ## User Interactions

      # Submit an input value
      :ok = ExecutionProcess.submit_input(pid, step_id, block_id, value, user_id)

      # Sign off a step
      :ok = ExecutionProcess.sign_off(pid, step_id, role, note, user_id)

      # Mark step complete (manual mode)
      :ok = ExecutionProcess.complete_step(pid, step_id)

  ## Control Signals

      :ok = ExecutionProcess.pause(pid)
      :ok = ExecutionProcess.resume(pid)
      :ok = ExecutionProcess.abort(pid, reason)

  ## PubSub Events

  Subscribe to `"execution:<execution_id>"` to receive:

  - `{:step_activated, step_execution}`
  - `{:step_completed, step_execution}`
  - `{:block_updated, block_execution}`
  - `{:automation_progress, block, status, data}`
  - `{:execution_paused, execution}`
  - `{:execution_resumed, execution}`
  - `{:execution_completed, execution}`
  - `{:execution_failed, execution, reason}`
  """

  use GenServer

  require Logger

  alias Cadence.Procedures.V2.{
    AutomationRunner,
    ExecutionPersistence,
    ExecutionQueries,
    ExecutionStrategy
  }

  alias Cadence.Procedures.{ProcedureExecution, ProcedureVersion}
  alias Cadence.Repo

  @type start_opts :: [
          procedure_version: ProcedureVersion.t(),
          params: map(),
          target_id: String.t(),
          user_id: String.t(),
          triggered_by: atom(),
          trigger_context: map(),
          # For attaching to existing execution
          execution_id: String.t()
        ]

  @type state :: %{
          execution: ProcedureExecution.t(),
          strategy: module(),
          control_signal: nil | :pause | :abort,
          automation_task: nil | Task.t(),
          automation_step_id: nil | String.t(),
          context: map()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts an ExecutionProcess for a procedure version.

  ## Options

  For creating a new execution:
  - `:procedure_version` - The procedure version to execute (required)
  - `:params` - Execution parameters
  - `:target_id` - Target spacecraft
  - `:user_id` - User starting execution
  - `:triggered_by` - Trigger type
  - `:trigger_context` - Additional trigger context

  For attaching to an existing execution:
  - `:execution_id` - ID of existing execution to attach to
  - `:user_id` - User ID for context
  """
  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(opts) do
    execution_id = opts[:execution_id]
    name = if execution_id, do: via_tuple(execution_id), else: nil
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Finds or starts an ExecutionProcess for the given execution ID.

  If a process is already running for this execution, returns its pid.
  Otherwise, starts a new process attached to the existing execution.
  """
  @spec start_or_attach(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_or_attach(execution_id, opts \\ []) do
    case whereis(execution_id) do
      nil ->
        # Start new process attached to existing execution
        start_link(Keyword.merge(opts, execution_id: execution_id))

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Finds the ExecutionProcess for a given execution ID.
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(execution_id) do
    case Registry.lookup(Cadence.Procedures.V2.ExecutionRegistry, execution_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(execution_id) do
    {:via, Registry, {Cadence.Procedures.V2.ExecutionRegistry, execution_id}}
  end

  @doc """
  Gets the current execution state.
  """
  @spec get_execution(GenServer.server()) :: ProcedureExecution.t()
  def get_execution(server) do
    GenServer.call(server, :get_execution)
  end

  @doc """
  Gets the current control signal (:pause | :abort | nil).
  """
  @spec get_control_signal(GenServer.server()) :: :pause | :abort | nil
  def get_control_signal(server) do
    GenServer.call(server, :get_control_signal)
  end

  @doc """
  Submits an input value for a block.
  """
  @spec submit_input(GenServer.server(), String.t(), String.t(), term(), String.t() | nil) ::
          :ok | {:error, term()}
  def submit_input(server, step_id, block_id, value, user_id \\ nil) do
    GenServer.call(server, {:submit_input, step_id, block_id, value, user_id})
  end

  @doc """
  Triggers execution of an automated block (for manual mode).
  """
  @spec execute_block(GenServer.server(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def execute_block(server, step_id, block_id) do
    GenServer.call(server, {:execute_block, step_id, block_id})
  end

  @doc """
  Signs off a step with the given role.
  """
  @spec sign_off(GenServer.server(), String.t(), String.t(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, term()}
  def sign_off(server, step_id, role, note \\ nil, user_id \\ nil) do
    GenServer.call(server, {:sign_off, step_id, role, note, user_id})
  end

  @doc """
  Marks a step as complete (for manual mode).
  """
  @spec complete_step(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def complete_step(server, step_id) do
    GenServer.call(server, {:complete_step, step_id})
  end

  @doc """
  Skips a step with the given reason.
  """
  @spec skip_step(GenServer.server(), String.t(), String.t(), String.t() | nil) ::
          :ok | {:error, term()}
  def skip_step(server, step_id, reason, user_id \\ nil) do
    GenServer.call(server, {:skip_step, step_id, reason, user_id})
  end

  @doc """
  Retries a failed block.
  """
  @spec retry_block(GenServer.server(), String.t(), String.t()) :: :ok | {:error, term()}
  def retry_block(server, step_id, block_id) do
    GenServer.call(server, {:retry_block, step_id, block_id})
  end

  @doc """
  Retries all automation in a step.
  """
  @spec retry_step(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def retry_step(server, step_id) do
    GenServer.call(server, {:retry_step, step_id})
  end

  @doc """
  Pauses the execution.
  """
  @spec pause(GenServer.server()) :: :ok
  def pause(server) do
    GenServer.cast(server, :pause)
  end

  @doc """
  Resumes a paused execution.
  """
  @spec resume(GenServer.server()) :: :ok
  def resume(server) do
    GenServer.cast(server, :resume)
  end

  @doc """
  Aborts the execution with a reason.
  """
  @spec abort(GenServer.server(), String.t()) :: :ok
  def abort(server, reason) do
    GenServer.cast(server, {:abort, reason})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    # Check if we're attaching to an existing execution or creating new
    case opts[:execution_id] do
      nil ->
        init_new_execution(opts)

      execution_id ->
        init_existing_execution(execution_id, opts)
    end
  end

  defp init_new_execution(opts) do
    procedure_version = opts[:procedure_version]
    params = opts[:params] || %{}

    # Determine strategy from execution mode
    mode = procedure_version.execution_mode || :manual
    strategy = ExecutionStrategy.for_mode(mode)

    # Create execution via persistence layer
    case ExecutionPersistence.create_execution(procedure_version, params, opts) do
      {:ok, execution} ->
        # Build execution context
        context = build_context(execution, procedure_version, opts)

        state = %{
          execution: execution,
          strategy: strategy,
          control_signal: nil,
          automation_task: nil,
          automation_step_id: nil,
          context: context
        }

        # Activate initial steps
        {:ok, state, {:continue, :activate_ready_steps}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp init_existing_execution(execution_id, opts) do
    case ExecutionQueries.get_execution(execution_id) do
      nil ->
        {:stop, :execution_not_found}

      execution ->
        procedure_version = execution.procedure_version
        procedure = procedure_version.procedure

        # Determine strategy from execution mode
        mode = procedure_version.execution_mode || :manual
        strategy = ExecutionStrategy.for_mode(mode)

        # Build execution context from existing execution
        context = %{
          mission_id: procedure.mission_id,
          target_id: execution.target_id,
          organization_id: procedure.organization_id,
          execution_id: execution.id,
          user_id: opts[:user_id],
          params: execution.parameters || %{},
          vars: %{},
          trigger: execution.trigger_context || %{}
        }

        # Set control signal based on current status
        control_signal =
          case execution.status do
            :paused -> :pause
            _ -> nil
          end

        state = %{
          execution: execution,
          strategy: strategy,
          control_signal: control_signal,
          automation_task: nil,
          automation_step_id: nil,
          context: context
        }

        # Check if we need to activate any steps or resume automation
        {:ok, state, {:continue, :check_execution_state}}
    end
  end

  @impl true
  def handle_continue(:activate_ready_steps, state) do
    state = activate_ready_steps(state)
    {:noreply, state}
  end

  @impl true
  def handle_continue(:check_execution_state, state) do
    # When attaching to an existing execution, check current state
    execution = ExecutionQueries.reload_execution(state.execution.id)
    state = %{state | execution: execution}

    # If execution is completed or failed, nothing to do
    case execution.status do
      status when status in [:completed, :failed, :cancelled] ->
        {:noreply, state}

      :paused ->
        # Stay paused, don't activate anything
        {:noreply, state}

      _running_status ->
        # Check for pending steps that need activation
        state = activate_ready_steps(state)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_execution, _from, state) do
    # Reload execution with associations
    execution = ExecutionQueries.reload_execution(state.execution.id)
    {:reply, execution, %{state | execution: execution}}
  end

  @impl true
  def handle_call({:submit_input, step_id, block_id, value, user_id}, _from, state) do
    case do_submit_input(step_id, block_id, value, user_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:execute_block, step_id, block_id}, _from, state) do
    case do_execute_block(step_id, block_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:sign_off, step_id, role, note, user_id}, _from, state) do
    case do_sign_off(step_id, role, note, user_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:complete_step, step_id}, _from, state) do
    case do_complete_step(step_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:skip_step, step_id, reason, user_id}, _from, state) do
    case do_skip_step(step_id, reason, user_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_control_signal, _from, state) do
    {:reply, state.control_signal, state}
  end

  @impl true
  def handle_call({:retry_block, step_id, block_id}, _from, state) do
    case do_retry_block(step_id, block_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:retry_step, step_id}, _from, state) do
    case do_retry_step(step_id, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:pause, state) do
    # Persistence layer handles broadcast after commit
    case ExecutionPersistence.update_execution_status(state.execution, :paused) do
      {:ok, updated_execution} ->
        {:noreply, %{state | execution: updated_execution, control_signal: :pause}}

      {:error, changeset} ->
        # State may be stale - reload from DB and log warning
        Logger.warning(
          "Failed to pause execution #{state.execution.id}: #{inspect(changeset.errors)}"
        )

        reloaded = ExecutionQueries.get_execution!(state.execution.id)
        {:noreply, %{state | execution: reloaded}}
    end
  end

  @impl true
  def handle_cast(:resume, state) do
    # Persistence layer handles broadcast after commit
    case ExecutionPersistence.update_execution_status(state.execution, :running) do
      {:ok, updated_execution} ->
        state = %{state | execution: updated_execution, control_signal: nil}
        # Resume automation if it was paused
        state = maybe_resume_automation(state)
        {:noreply, state}

      {:error, changeset} ->
        # State may be stale - reload from DB and log warning
        Logger.warning(
          "Failed to resume execution #{state.execution.id}: #{inspect(changeset.errors)}"
        )

        reloaded = ExecutionQueries.get_execution!(state.execution.id)
        {:noreply, %{state | execution: reloaded}}
    end
  end

  @impl true
  def handle_cast({:abort, reason}, state) do
    state = %{state | control_signal: :abort}

    # Shutdown any running automation
    if state.automation_task do
      Task.shutdown(state.automation_task, :brutal_kill)
    end

    # Persistence layer handles broadcast after commit
    case ExecutionPersistence.update_execution_status(state.execution, :failed,
           error_message: reason
         ) do
      {:ok, _updated_execution} ->
        {:stop, :normal, state}

      {:error, changeset} ->
        # Already in a terminal state, just log and stop
        Logger.warning(
          "Failed to abort execution #{state.execution.id}: #{inspect(changeset.errors)}"
        )

        {:stop, :normal, state}
    end
  end

  # Handle automation task completion
  @impl true
  def handle_info({ref, result}, %{automation_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = handle_automation_complete(result, state)
    {:noreply, %{state | automation_task: nil, automation_step_id: nil}}
  end

  # Handle automation task crash
  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{automation_task: %Task{ref: ref}} = state
      ) do
    Logger.error("Automation task crashed: #{inspect(reason)}")
    state = handle_automation_failed(reason, state)
    {:noreply, %{state | automation_task: nil, automation_step_id: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Step Activation
  # ============================================================================

  defp activate_ready_steps(state) do
    execution = ExecutionQueries.reload_execution(state.execution.id)

    # Find pending steps with satisfied dependencies
    ready_steps =
      execution.step_executions
      |> Enum.filter(fn step_exec ->
        step_exec.status == :pending and ExecutionQueries.dependencies_satisfied?(step_exec, execution)
      end)

    # Activate each ready step
    Enum.reduce(ready_steps, %{state | execution: execution}, fn step_exec, acc_state ->
      activate_step(step_exec, acc_state)
    end)
  end

  defp activate_step(step_exec, state) do
    # Persistence layer handles broadcast after commit
    {:ok, step_exec} = ExecutionPersistence.activate_step(step_exec)

    # Ask strategy what to do
    case state.strategy.on_step_activated(step_exec, state) do
      {:ok, state} ->
        state

      {:run_automation, blocks, state} ->
        start_automation(step_exec, blocks, state)
    end
  end

  # ============================================================================
  # Automation
  # ============================================================================

  defp start_automation(step_exec, blocks, state) do
    # Build callbacks
    execution_id = state.execution.id
    step_exec_id = step_exec.id

    on_progress = fn block, status, data ->
      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "execution:#{execution_id}",
        {:automation_progress, block, status, data}
      )
    end

    on_block_complete = fn block, result ->
      # Update block execution via persistence layer
      update_block_execution_from_result(step_exec_id, block.id, result)
    end

    server = self()

    check_signal = fn ->
      case get_control_signal(server) do
        :pause -> :pause
        :abort -> :abort
        nil -> :continue
      end
    end

    # Start automation in a Task
    context = state.context
    strategy = state.strategy

    task =
      Task.async(fn ->
        AutomationRunner.run(blocks, context,
          on_progress: on_progress,
          on_block_complete: on_block_complete,
          check_signal: check_signal,
          strategy: strategy
        )
      end)

    %{state | automation_task: task, automation_step_id: step_exec.id}
  end

  defp handle_automation_complete(result, state) do
    step_exec = ExecutionQueries.get_step_execution!(state.automation_step_id)

    case result do
      {:ok, _results} ->
        # All blocks completed successfully
        case state.strategy.on_automation_complete(step_exec, result, state) do
          {:complete, state} ->
            do_complete_step_internal(step_exec, state)

          {:wait, state} ->
            # Broadcast manually since this is a composite event
            broadcast(state, {:step_awaiting_input, step_exec})
            state
        end

      {:error, block, reason} ->
        # A block failed - broadcast manually for this error case
        Logger.error("Automation failed on block #{block.id}: #{inspect(reason)}")
        broadcast(state, {:block_failed, block, reason})
        state

      {:paused, _results, _remaining} ->
        # Automation was paused
        state

      {:aborted, _results} ->
        # Automation was aborted
        state
    end
  end

  defp handle_automation_failed(reason, state) do
    Logger.error("Automation task failed: #{inspect(reason)}")
    state
  end

  defp maybe_resume_automation(state) do
    # TODO: Resume paused automation
    state
  end

  # ============================================================================
  # User Interactions
  # ============================================================================

  defp do_submit_input(step_id, block_id, value, user_id, state) do
    with :ok <- validate_control_signal(state),
         {:ok, block_exec} <- ExecutionQueries.get_block_execution(step_id, block_id) do
      block = block_exec.block
      wrapped_value = wrap_input_value(block.block_type, value)
      user_id = user_id || state.context[:user_id]

      # Persistence layer handles broadcast after commit
      {:ok, _block_exec} =
        ExecutionPersistence.update_block_value(block_exec, wrapped_value, user_id)

      # Check if step can be completed
      step_exec = ExecutionQueries.get_step_execution!(step_id)
      state = check_step_completion(step_exec, state)

      {:ok, state}
    end
  end

  # Wrap raw input value in appropriate map structure based on block type
  defp wrap_input_value(:text_input, value), do: %{text: value}

  defp wrap_input_value(:number_input, value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> %{number: num}
      _ -> %{number: value}
    end
  end

  defp wrap_input_value(:number_input, value) when is_number(value), do: %{number: value}
  defp wrap_input_value(:checkbox, value), do: %{checked: value}
  defp wrap_input_value(:select, value), do: %{selected: value}
  defp wrap_input_value(_block_type, value) when is_map(value), do: value
  defp wrap_input_value(_block_type, value), do: %{value: value}

  defp do_execute_block(step_id, block_id, state) do
    with :ok <- validate_control_signal(state),
         {:ok, block_exec} <- ExecutionQueries.get_block_execution(step_id, block_id) do
      block = block_exec.block

      # Execute single block
      case AutomationRunner.execute_block(block, state.context, strategy: state.strategy) do
        {:ok, result} ->
          # Persistence layer handles broadcast
          {:ok, _} = update_block_execution_from_result(step_id, block.id, {:ok, result})
          {:ok, state}

        {:error, reason} ->
          {:ok, _} = update_block_execution_from_result(step_id, block.id, {:error, reason})
          {:error, reason}

        {:skip, reason} ->
          {:ok, _} = update_block_execution_from_result(step_id, block.id, {:skip, reason})
          {:ok, state}
      end
    end
  end

  defp do_sign_off(step_id, role, note, user_id, state) do
    with :ok <- validate_control_signal(state) do
      step_exec = ExecutionQueries.get_step_execution!(step_id)
      user_id = user_id || state.context[:user_id]

      # Persistence layer handles broadcast after commit
      case ExecutionPersistence.create_signoff(step_exec, user_id, role, note) do
        {:ok, _signoff} ->
          # Reload step and check if signoffs are complete
          step_exec = ExecutionQueries.get_step_execution!(step_id)

          case state.strategy.on_signoffs_complete(step_exec, state) do
            {:complete, state} ->
              {:ok, do_complete_step_internal(step_exec, state)}

            {:ok, state} ->
              {:ok, state}
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp do_complete_step(step_id, state) do
    with :ok <- validate_control_signal(state) do
      step_exec = ExecutionQueries.get_step_execution!(step_id)
      {:ok, do_complete_step_internal(step_exec, state)}
    end
  end

  defp do_complete_step_internal(step_exec, state) do
    # Persistence layer handles broadcast after commit
    {:ok, _step_exec} = ExecutionPersistence.complete_step(step_exec)

    # Check if execution is complete
    state = check_execution_completion(state)

    # Activate next steps
    activate_ready_steps(state)
  end

  defp do_skip_step(step_id, reason, user_id, state) do
    with :ok <- validate_control_signal(state) do
      step_exec = ExecutionQueries.get_step_execution!(step_id)

      skip_attrs = %{
        skipped_reason: reason,
        skipped_by_id: user_id || state.context[:user_id]
      }

      # Persistence layer handles broadcast after commit
      {:ok, _step_exec} = ExecutionPersistence.skip_step(step_exec, skip_attrs)

      state = check_execution_completion(state)
      {:ok, activate_ready_steps(state)}
    end
  end

  defp do_retry_block(step_id, block_id, state) do
    with :ok <- validate_control_signal(state),
         {:ok, block_exec} <- ExecutionQueries.get_block_execution(step_id, block_id) do
      # Reset block via persistence layer
      {:ok, _block_exec} = ExecutionPersistence.reset_block_for_retry(block_exec)

      # Execute single block
      do_execute_block(step_id, block_id, state)
    end
  end

  defp do_retry_step(step_id, state) do
    with :ok <- validate_control_signal(state) do
      step_exec = ExecutionQueries.get_step_execution!(step_id)

      # Reset step and all blocks via persistence layer
      {:ok, step_exec} = ExecutionPersistence.reset_step_for_retry(step_exec)

      # Reload with associations
      step_exec = ExecutionQueries.get_step_execution!(step_exec.id)

      # Ask strategy what to do
      case state.strategy.on_step_activated(step_exec, state) do
        {:ok, state} ->
          {:ok, state}

        {:run_automation, blocks, state} ->
          {:ok, start_automation(step_exec, blocks, state)}
      end
    end
  end

  defp validate_control_signal(%{control_signal: :pause}), do: {:error, :paused}
  defp validate_control_signal(%{control_signal: :abort}), do: {:error, :aborted}
  defp validate_control_signal(_state), do: :ok

  defp check_step_completion(step_exec, state) do
    case state.strategy.on_step_ready_to_complete(step_exec, state) do
      {:complete, state} ->
        do_complete_step_internal(step_exec, state)

      {:wait, state} ->
        state
    end
  end

  defp check_execution_completion(state) do
    execution = ExecutionQueries.reload_execution(state.execution.id)

    all_done =
      Enum.all?(execution.step_executions, fn se ->
        se.status in [:completed, :skipped]
      end)

    execution =
      if all_done do
        # Persistence layer handles broadcast after commit
        {:ok, updated_execution} =
          ExecutionPersistence.update_execution_status(execution, :completed)

        updated_execution
      else
        execution
      end

    %{state | execution: execution}
  end

  # ============================================================================
  # Block Update Helper
  # ============================================================================

  # Updates a block execution based on automation result
  defp update_block_execution_from_result(step_exec_id, block_id, result) do
    case ExecutionQueries.get_block_execution(step_exec_id, block_id) do
      {:ok, block_exec} ->
        handle_block_result(block_exec, result)

      {:error, :not_found} ->
        {:ok, nil}
    end
  end

  defp handle_block_result(block_exec, {:ok, data}) when is_map(data) do
    handle_block_result_map(block_exec, data)
  end

  defp handle_block_result(block_exec, {:ok, _other}) do
    ExecutionPersistence.update_block_value(block_exec, %{}, nil)
  end

  defp handle_block_result(block_exec, {:error, reason}) do
    ExecutionPersistence.fail_block(block_exec, inspect(reason))
  end

  defp handle_block_result(block_exec, {:skip, reason}) do
    _ = ExecutionPersistence.fail_block(block_exec, inspect(reason))
    ExecutionPersistence.skip_block(block_exec)
  end

  defp handle_block_result_map(block_exec, %{command_name: _} = data) do
    ExecutionPersistence.update_block_command_result(block_exec, data)
  end

  defp handle_block_result_map(block_exec, %{item: _, value: _} = data) do
    ExecutionPersistence.update_block_telemetry_reading(block_exec, data)
  end

  defp handle_block_result_map(block_exec, %{condition: _} = data) do
    passed = Map.get(data, :passed, true)
    ExecutionPersistence.update_block_telemetry_check(block_exec, data, passed)
  end

  defp handle_block_result_map(block_exec, data) do
    ExecutionPersistence.update_block_value(block_exec, data, nil)
  end

  # ============================================================================
  # Context & Broadcasting
  # ============================================================================

  defp build_context(execution, procedure_version, opts) do
    # Ensure procedure is loaded
    procedure_version = Repo.preload(procedure_version, :procedure)
    procedure = procedure_version.procedure

    # Extract target from opts, execution record, or parameters
    params = execution.parameters || %{}
    target_id = opts[:target_id] || execution.target_id || extract_target_from_params(params)

    %{
      mission_id: procedure.mission_id,
      target_id: target_id,
      organization_id: procedure.organization_id,
      execution_id: execution.id,
      user_id: opts[:user_id],
      params: params,
      vars: %{},
      trigger: opts[:trigger_context] || %{}
    }
  end

  defp extract_target_from_params(params) when is_map(params) do
    params["target"] || params["target_id"]
  end

  defp extract_target_from_params(_), do: nil

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "execution:#{state.execution.id}",
      message
    )
  end
end
