defmodule Cadence.Procedures.V2.ExecutionStrategy do
  @moduledoc """
  Behaviour defining how execution modes handle procedure execution events.

  This strategy pattern allows different execution modes (manual, assisted, automatic)
  to have distinct behaviors without scattering mode checks throughout the codebase.

  ## Execution Modes

  - `:manual` - Operator must explicitly trigger each action and confirm each step
  - `:assisted` - System auto-runs automated blocks but waits for inputs and signoffs
  - `:automatic` - Full automatic execution, using defaults for inputs, skipping signoffs

  ## Implementation

  Each strategy implements callbacks that the ExecutionProcess calls at key decision
  points. The strategy returns instructions that the ExecutionProcess follows.

  ## Example

      defmodule MyCustomStrategy do
        @behaviour Cadence.Procedures.V2.ExecutionStrategy

        @impl true
        def on_step_activated(step_exec, state) do
          # Custom logic for when a step becomes active
          {:run_automation, get_automated_blocks(step_exec), state}
        end

        # ... other callbacks
      end
  """

  alias Cadence.Procedures.Schemas.ProcedureBlock
  alias Cadence.Procedures.Schemas.StepExecution

  @type state :: map()
  @type step_exec :: StepExecution.t()
  @type block :: ProcedureBlock.t()
  @type blocks :: [block()]

  # ============================================================================
  # Step Lifecycle Callbacks
  # ============================================================================

  @doc """
  Called when a step is activated (transitions to :active status).

  Returns:
  - `{:ok, state}` - Just mark step as active, wait for user actions
  - `{:run_automation, blocks, state}` - Start running the specified automated blocks
  """
  @callback on_step_activated(step_exec(), state()) ::
              {:ok, state()} | {:run_automation, blocks(), state()}

  @doc """
  Called when all automated blocks in a step have completed.

  Returns:
  - `{:complete, state}` - Auto-complete the step and activate next
  - `{:wait, state}` - Wait for operator action (inputs, signoffs, manual complete)
  """
  @callback on_automation_complete(step_exec(), result :: map(), state()) ::
              {:complete, state()} | {:wait, state()}

  @doc """
  Called when checking if a step can be auto-completed.

  This is called when all requirements might be satisfied to determine
  if the step should auto-complete or wait for explicit operator action.

  Returns:
  - `{:complete, state}` - Auto-complete the step
  - `{:wait, state}` - Wait for operator to click "Complete"
  """
  @callback on_step_ready_to_complete(step_exec(), state()) ::
              {:complete, state()} | {:wait, state()}

  # ============================================================================
  # Block Behavior Callbacks
  # ============================================================================

  @doc """
  Determines if a block should be automatically executed when step is activated.

  For `:manual` mode, typically returns false (operator must click execute).
  For `:assisted` and `:automatic` modes, typically returns true for non-interactive blocks.
  """
  @callback should_auto_run_block?(block()) :: boolean()

  @doc """
  Determines if a command block requires operator confirmation before execution.

  Even in `:assisted` mode, some commands may be marked as requiring confirmation.
  In `:automatic` mode, confirmations are typically skipped.
  """
  @callback should_require_confirmation?(block()) :: boolean()

  # ============================================================================
  # Input Handling Callbacks
  # ============================================================================

  @doc """
  Called when all input blocks in a step have been filled.

  Returns:
  - `{:ok, state}` - Just acknowledge, wait for other requirements
  - `{:check_complete, state}` - Check if step can now be completed
  """
  @callback on_all_inputs_filled(step_exec(), state()) ::
              {:ok, state()} | {:check_complete, state()}

  @doc """
  Gets the default value for an input block (used in automatic mode).

  Returns:
  - `{:ok, value}` - Use this default value
  - `:no_default` - No default available, will fail in automatic mode
  """
  @callback get_default_value(block()) :: {:ok, term()} | :no_default

  # ============================================================================
  # Signoff Handling Callbacks
  # ============================================================================

  @doc """
  Called when all required signoffs for a step have been collected.

  Returns:
  - `{:complete, state}` - Auto-complete the step
  - `{:ok, state}` - Just acknowledge, wait for other requirements or explicit complete
  """
  @callback on_signoffs_complete(step_exec(), state()) ::
              {:complete, state()} | {:ok, state()}

  @doc """
  Determines if signoff requirements should be enforced for a step.

  In `:automatic` mode, signoffs are typically auto-satisfied.
  """
  @callback should_enforce_signoffs?(step_exec()) :: boolean()

  # ============================================================================
  # Helper for Strategy Selection
  # ============================================================================

  @doc """
  Returns the strategy module for the given execution mode.
  """
  @spec for_mode(atom()) :: module()
  def for_mode(:manual), do: Cadence.Procedures.V2.Strategies.Manual
  def for_mode(:assisted), do: Cadence.Procedures.V2.Strategies.Assisted
  def for_mode(:automatic), do: Cadence.Procedures.V2.Strategies.Automatic
  def for_mode(_), do: Cadence.Procedures.V2.Strategies.Manual
end
