defmodule Cadence.Procedures.V2.Strategies.Assisted do
  @moduledoc """
  Assisted execution strategy - system helps but operator remains in control.

  In assisted mode:
  - Automated blocks (commands, waits, telemetry checks) run automatically
  - Commands marked with `require_confirmation: true` still need operator approval
  - Operator must fill all input blocks (no defaults)
  - Operator must provide all required signoffs
  - Steps auto-complete when all requirements are met
  - Next step auto-activates when current step completes

  This mode is ideal for:
  - Normal operations with experienced operators
  - Procedures with a mix of automated and interactive steps
  - When operator oversight is needed but automation helps efficiency
  """

  @behaviour Cadence.Procedures.V2.ExecutionStrategy

  # Block types that run automatically in assisted mode
  @automated_block_types [
    :command,
    :command_sequence,
    :wait,
    :wait_for,
    :telemetry_check,
    :telemetry_value,
    :script
  ]

  # ============================================================================
  # Step Lifecycle
  # ============================================================================

  @impl true
  def on_step_activated(step_exec, state) do
    # Get blocks that should run automatically
    automated_blocks =
      step_exec.step.blocks
      |> Enum.filter(&should_auto_run_block?/1)

    if Enum.empty?(automated_blocks) do
      # No automated blocks, just wait for operator
      {:ok, state}
    else
      # Start running automated blocks
      {:run_automation, automated_blocks, state}
    end
  end

  @impl true
  def on_automation_complete(step_exec, _result, state) do
    # Check if we can auto-complete
    if all_requirements_met?(step_exec) do
      {:complete, state}
    else
      {:wait, state}
    end
  end

  @impl true
  def on_step_ready_to_complete(step_exec, state) do
    # In assisted mode, auto-complete if no signoff required
    # or if signoffs are already done
    if requires_signoff?(step_exec) and not signoffs_complete?(step_exec) do
      {:wait, state}
    else
      {:complete, state}
    end
  end

  # ============================================================================
  # Block Behavior
  # ============================================================================

  @impl true
  def should_auto_run_block?(block) do
    # Run automated block types, except those requiring confirmation
    block.block_type in @automated_block_types and
      not requires_explicit_confirmation?(block)
  end

  @impl true
  def should_require_confirmation?(block) do
    # Only require confirmation if explicitly marked
    requires_explicit_confirmation?(block)
  end

  # ============================================================================
  # Input Handling
  # ============================================================================

  @impl true
  def on_all_inputs_filled(step_exec, state) do
    # Check if step can be completed now
    if all_requirements_met?(step_exec) do
      {:check_complete, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def get_default_value(_block) do
    # No defaults in assisted mode - operator must provide values
    :no_default
  end

  # ============================================================================
  # Signoff Handling
  # ============================================================================

  @impl true
  def on_signoffs_complete(_step_exec, state) do
    # Auto-complete when signoffs are done (if other requirements met)
    {:complete, state}
  end

  @impl true
  def should_enforce_signoffs?(step_exec) do
    # Enforce signoffs if step requires them
    requires_signoff?(step_exec)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp requires_explicit_confirmation?(block) do
    get_in(block.content || %{}, ["require_confirmation"]) == true
  end

  defp requires_signoff?(step_exec) do
    step = step_exec.step

    cond do
      is_nil(step) -> false
      is_nil(step.signoff_roles) -> false
      step.signoff_roles == [] -> false
      true -> true
    end
  end

  defp signoffs_complete?(step_exec) do
    step = step_exec.step

    if is_nil(step) or is_nil(step.signoff_roles) or step.signoff_roles == [] do
      true
    else
      required_roles = MapSet.new(step.signoff_roles)
      signed_roles = step_exec.signoffs |> Enum.map(& &1.role) |> MapSet.new()

      case step.signoff_logic do
        :any -> not MapSet.disjoint?(required_roles, signed_roles)
        :all -> MapSet.subset?(required_roles, signed_roles)
        _ -> MapSet.subset?(required_roles, signed_roles)
      end
    end
  end

  defp all_requirements_met?(step_exec) do
    inputs_complete?(step_exec) and
      automation_complete?(step_exec) and
      (not requires_signoff?(step_exec) or signoffs_complete?(step_exec))
  end

  @input_block_types [:text_input, :number_input, :select, :checkbox]

  defp inputs_complete?(step_exec) do
    block_types_complete?(step_exec, @input_block_types, &input_block_complete?/1)
  end

  defp automation_complete?(step_exec) do
    block_types_complete?(step_exec, @automated_block_types, &automation_block_complete?/1)
  end

  defp block_types_complete?(step_exec, block_types, completed?) do
    block_ids =
      step_exec.step.blocks
      |> Enum.filter(&(&1.block_type in block_types))
      |> MapSet.new(& &1.id)

    if MapSet.size(block_ids) == 0 do
      true
    else
      block_execs = step_exec.block_executions || []

      Enum.all?(block_execs, fn be ->
        if MapSet.member?(block_ids, be.block_id) do
          completed?.(be)
        else
          true
        end
      end)
    end
  end

  defp input_block_complete?(block_exec) do
    block_exec.status == :completed and not is_nil(block_exec.value)
  end

  defp automation_block_complete?(block_exec) do
    block_exec.status in [:completed, :skipped]
  end
end
