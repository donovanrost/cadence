defmodule Cadence.Procedures.V2.Strategies.Manual do
  @moduledoc """
  Manual execution strategy - operator must explicitly trigger every action.

  In manual mode:
  - Automated blocks do NOT run automatically
  - Operator must click "Execute" for each command/script block
  - Operator must fill all input blocks
  - Operator must provide all required signoffs
  - Operator must click "Complete" to finish each step
  - Operator must click to activate the next step

  This mode is ideal for:
  - Training scenarios
  - Critical operations requiring full operator attention
  - First-time procedure execution for verification
  """

  @behaviour Cadence.Procedures.V2.ExecutionStrategy

  # ============================================================================
  # Step Lifecycle
  # ============================================================================

  @impl true
  def on_step_activated(_step_exec, state) do
    # In manual mode, just activate the step and wait for operator
    {:ok, state}
  end

  @impl true
  def on_automation_complete(_step_exec, _result, state) do
    # Even after automation completes, wait for operator to complete step
    {:wait, state}
  end

  @impl true
  def on_step_ready_to_complete(_step_exec, state) do
    # Always wait for explicit operator action to complete
    {:wait, state}
  end

  # ============================================================================
  # Block Behavior
  # ============================================================================

  @impl true
  def should_auto_run_block?(_block) do
    # Nothing runs automatically in manual mode
    false
  end

  @impl true
  def should_require_confirmation?(_block) do
    # All commands require confirmation in manual mode
    true
  end

  # ============================================================================
  # Input Handling
  # ============================================================================

  @impl true
  def on_all_inputs_filled(_step_exec, state) do
    # Just acknowledge, don't trigger anything automatic
    {:ok, state}
  end

  @impl true
  def get_default_value(_block) do
    # No defaults in manual mode - operator must provide all values
    :no_default
  end

  # ============================================================================
  # Signoff Handling
  # ============================================================================

  @impl true
  def on_signoffs_complete(_step_exec, state) do
    # Just acknowledge, still need operator to click complete
    {:ok, state}
  end

  @impl true
  def should_enforce_signoffs?(_step_exec) do
    # Always enforce signoffs in manual mode
    true
  end
end
