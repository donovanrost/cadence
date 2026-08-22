defmodule Cadence.Procedures.V2.Strategies.Automatic do
  @moduledoc """
  Automatic execution strategy - runs to completion with minimal operator interaction.

  In automatic mode:
  - All automated blocks run automatically
  - Commands do NOT require confirmation (even if marked)
  - Input blocks use default values if available
  - Signoff requirements are auto-satisfied (system signoff)
  - Steps auto-complete immediately when blocks finish
  - Next step auto-activates immediately

  This mode is ideal for:
  - Fully automated procedures (e.g., scheduled maintenance)
  - Testing procedure logic
  - Batch operations where operator oversight isn't required
  - Migration from DAG-style execution to V2 format

  ## Caution

  Automatic mode bypasses many safety checks. Use with care for:
  - Hazardous commands
  - Critical operations
  - Procedures that modify important state
  """

  @behaviour Cadence.Procedures.V2.ExecutionStrategy

  # All block types that can be automated
  @automated_block_types [
    :command,
    :command_sequence,
    :telemetry_check,
    :telemetry_value,
    :telemetry_wait,
    :script,
    :text_input,
    :number_input,
    :select_input,
    :checkbox_input,
    :timestamp_input,
    :duration_input,
    :attachment_input,
    :signature_input
  ]

  # ============================================================================
  # Step Lifecycle
  # ============================================================================

  @impl true
  def on_step_activated(step_exec, state) do
    # Get all blocks - we'll try to run everything automatically
    blocks = step_exec.step.blocks || []

    if Enum.empty?(blocks) do
      # No blocks, complete immediately
      {:complete, state}
    else
      # Run all automated blocks
      {:run_automation, blocks, state}
    end
  end

  @impl true
  def on_automation_complete(_step_exec, _result, state) do
    # Always auto-complete in automatic mode
    {:complete, state}
  end

  @impl true
  def on_step_ready_to_complete(_step_exec, state) do
    # Always auto-complete in automatic mode
    {:complete, state}
  end

  # ============================================================================
  # Block Behavior
  # ============================================================================

  @impl true
  def should_auto_run_block?(block) do
    # Run everything automatically
    block.block_type in @automated_block_types
  end

  @impl true
  def should_require_confirmation?(_block) do
    # Never require confirmation in automatic mode
    false
  end

  # ============================================================================
  # Input Handling
  # ============================================================================

  @impl true
  def on_all_inputs_filled(_step_exec, state) do
    # Auto-complete when inputs filled
    {:check_complete, state}
  end

  @impl true
  def get_default_value(block) do
    # Try to get default from block content
    content = block.content || %{}

    with :no_default <- default_from_content(content),
         :no_default <- default_for_block_type(block, content) do
      :no_default
    else
      {:ok, value} -> {:ok, value}
    end
  end

  defp default_from_content(content) do
    cond do
      Map.has_key?(content, "default") -> {:ok, content["default"]}
      Map.has_key?(content, "default_value") -> {:ok, content["default_value"]}
      true -> :no_default
    end
  end

  defp default_for_block_type(%{block_type: :checkbox}, _content), do: {:ok, false}

  defp default_for_block_type(%{block_type: :select}, content) do
    if is_list(content["options"]) do
      default_from_options(content["options"])
    else
      :no_default
    end
  end

  defp default_for_block_type(_block, _content), do: :no_default

  defp default_from_options([first | _]), do: {:ok, Map.get(first, "value", first)}
  defp default_from_options(_), do: :no_default

  # ============================================================================
  # Signoff Handling
  # ============================================================================

  @impl true
  def on_signoffs_complete(_step_exec, state) do
    # Auto-complete (though signoffs are typically auto-satisfied)
    {:complete, state}
  end

  @impl true
  def should_enforce_signoffs?(_step_exec) do
    # Don't enforce signoffs in automatic mode - they're auto-satisfied
    false
  end
end
