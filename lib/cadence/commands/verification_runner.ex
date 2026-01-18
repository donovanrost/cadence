defmodule Cadence.Commands.VerificationRunner do
  @moduledoc """
  Orchestrates multi-stage command verification using CommandVerifier definitions.

  This module manages the execution of verification stages defined via `CommandVerifier`
  schemas. Each stage can use either simple telemetry checks (telemetry_item_ref + comparison)
  or complex match criteria.

  ## Verification Flow

  1. Runner is created with a list of CommandVerifiers
  2. Verifiers are sorted by stage order
  3. Each stage is started with its timeout
  4. Telemetry updates are checked against the current stage
  5. On success, the next stage starts
  6. On timeout, the `on_timeout_action` determines behavior

  ## Example

      # Create runner with verifiers from a MetaCommand
      {:ok, runner} = VerificationRunner.new(
        command_log_id,
        mission_id,
        target_id,
        command.verifiers
      )

      # Start first stage
      {:ok, runner} = VerificationRunner.start_current_stage(runner)

      # Check telemetry update
      case VerificationRunner.check_update(runner, packet_name, item_name, value) do
        {:stage_complete, updated_runner} -> start next stage
        {:all_complete, final_runner} -> verification succeeded
        {:pending, runner} -> keep waiting
        {:failed, runner, reason} -> verification failed
      end
  """

  require Logger

  alias Cadence.Commands.Verification
  alias Cadence.MissionDatabase.CommandVerifier
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  @stage_order [
    :transferred_to_range,
    :sent_from_range,
    :received,
    :accepted,
    :queued,
    :executing,
    :complete,
    :failed
  ]

  defstruct [
    :command_log_id,
    :mission_id,
    :target_id,
    :verifiers,
    :current_index,
    :timeout_ref,
    :started_at,
    :initial_value,
    stage_results: %{}
  ]

  @type t :: %__MODULE__{
          command_log_id: String.t(),
          mission_id: String.t(),
          target_id: String.t(),
          verifiers: [CommandVerifier.t()],
          current_index: non_neg_integer(),
          timeout_ref: reference() | nil,
          started_at: DateTime.t() | nil,
          initial_value: term() | nil,
          stage_results: map()
        }

  @doc """
  Creates a new verification runner from CommandVerifiers.

  Verifiers are sorted by stage order. Returns an error if no verifiers provided.
  """
  @spec new(String.t(), String.t(), String.t(), [CommandVerifier.t()]) ::
          {:ok, t()} | {:error, :no_verifiers}
  def new(_command_log_id, _mission_id, _target_id, []) do
    {:error, :no_verifiers}
  end

  def new(command_log_id, mission_id, target_id, verifiers) do
    # Sort verifiers by stage order
    sorted =
      Enum.sort_by(verifiers, fn v ->
        Enum.find_index(@stage_order, &(&1 == v.stage)) || 999
      end)

    runner = %__MODULE__{
      command_log_id: command_log_id,
      mission_id: mission_id,
      target_id: target_id,
      verifiers: sorted,
      current_index: 0,
      stage_results: %{}
    }

    {:ok, runner}
  end

  @doc """
  Returns the current verifier being processed.
  """
  @spec current_verifier(t()) :: CommandVerifier.t() | nil
  def current_verifier(%__MODULE__{verifiers: verifiers, current_index: index}) do
    Enum.at(verifiers, index)
  end

  @doc """
  Returns the current stage being verified.
  """
  @spec current_stage(t()) :: atom() | nil
  def current_stage(runner) do
    case current_verifier(runner) do
      nil -> nil
      verifier -> verifier.stage
    end
  end

  @doc """
  Starts verification for the current stage.

  Returns:
  - `{:ok, runner}` - Stage started, runner updated with timeout_ref
  - `{:complete, runner}` - All stages already complete
  """
  @spec start_current_stage(t()) :: {:ok, t()} | {:complete, t()}
  def start_current_stage(%__MODULE__{current_index: index, verifiers: verifiers} = runner)
      when index >= length(verifiers) do
    {:complete, runner}
  end

  def start_current_stage(runner) do
    verifier = current_verifier(runner)

    Logger.info(
      "Starting verification stage #{verifier.stage} for command_log_id=#{runner.command_log_id}"
    )

    # Get initial value if using :changed comparison
    initial_value =
      if verifier.comparison == :changed and verifier.telemetry_item_ref do
        get_current_value(runner.mission_id, runner.target_id, verifier.telemetry_item_ref)
      else
        nil
      end

    updated_runner = %{
      runner
      | started_at: CadenceTime.now(),
        initial_value: initial_value,
        timeout_ref: nil
    }

    {:ok, updated_runner}
  end

  @doc """
  Starts the timeout timer for the current stage.

  Call this after start_current_stage and subscribing to telemetry.
  Returns the runner with timeout_ref set.
  """
  @spec start_timeout(t(), pid()) :: t()
  def start_timeout(runner, dispatcher_pid) do
    verifier = current_verifier(runner)

    if verifier && verifier.timeout_ms do
      timeout_ref =
        TimeTimer.send_after(
          dispatcher_pid,
          {:verification_stage_timeout, runner.command_log_id, verifier.stage},
          verifier.timeout_ms
        )

      %{runner | timeout_ref: timeout_ref}
    else
      runner
    end
  end

  @doc """
  Cancels the current timeout timer if present.
  """
  @spec cancel_timeout(t()) :: t()
  def cancel_timeout(%__MODULE__{timeout_ref: nil} = runner), do: runner

  def cancel_timeout(%__MODULE__{timeout_ref: ref} = runner) do
    TimeTimer.cancel(ref)
    %{runner | timeout_ref: nil}
  end

  @doc """
  Checks a telemetry update against the current verification stage.

  Returns:
  - `{:stage_complete, runner}` - Current stage passed, ready for next
  - `{:all_complete, runner}` - All stages passed
  - `{:pending, runner}` - Update didn't match or didn't satisfy criteria
  - `{:failed, runner, reason}` - Verification failed (non-recoverable)
  """
  @spec check_update(t(), String.t(), String.t(), term()) ::
          {:stage_complete, t()}
          | {:all_complete, t()}
          | {:pending, t()}
          | {:failed, t(), term()}
  def check_update(runner, packet_name, item_name, value) do
    verifier = current_verifier(runner)

    if verifier == nil do
      {:all_complete, runner}
    else
      if matches_verifier?(verifier, packet_name, item_name) do
        check_verifier_condition(runner, verifier, value)
      else
        {:pending, runner}
      end
    end
  end

  @doc """
  Handles a timeout for the current verification stage.

  Returns:
  - `{:continue, runner}` - Move to next stage (on_timeout_action: "continue")
  - `{:retry, runner}` - Retry this stage (on_timeout_action: "retry")
  - `{:abort, runner}` - Abort verification (default or on_timeout_action: "abort")
  """
  @spec handle_timeout(t()) :: {:continue, t()} | {:retry, t()} | {:abort, t()}
  def handle_timeout(runner) do
    verifier = current_verifier(runner)
    action = verifier && verifier.on_timeout_action

    case action do
      "continue" ->
        Logger.warning(
          "Verification stage #{verifier.stage} timeout, continuing to next stage " <>
            "(command_log_id=#{runner.command_log_id})"
        )

        updated_runner = advance_stage(runner, {:timeout, :continued})
        {:continue, updated_runner}

      "retry" ->
        Logger.warning(
          "Verification stage #{verifier.stage} timeout, retrying " <>
            "(command_log_id=#{runner.command_log_id})"
        )

        # Reset started_at for fresh timeout
        {:retry, %{runner | started_at: CadenceTime.now(), timeout_ref: nil}}

      _ ->
        # Default: abort
        Logger.warning(
          "Verification stage #{verifier.stage} timeout, aborting " <>
            "(command_log_id=#{runner.command_log_id})"
        )

        {:abort, runner}
    end
  end

  @doc """
  Returns true if all verification stages have completed.
  """
  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{current_index: index, verifiers: verifiers}) do
    index >= length(verifiers)
  end

  @doc """
  Returns the list of completed stages.
  """
  @spec completed_stages(t()) :: [atom()]
  def completed_stages(%__MODULE__{stage_results: results}) do
    results
    |> Enum.filter(fn {_stage, result} ->
      case result do
        :passed -> true
        {:timeout, :continued} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn {stage, _} -> stage end)
  end

  # Private functions

  defp matches_verifier?(verifier, packet_name, item_name) do
    if verifier.telemetry_item_ref do
      {expected_packet, expected_item} = Verification.parse_item(verifier.telemetry_item_ref)
      expected_packet == packet_name and expected_item == item_name
    else
      # Complex match criteria - we'll evaluate against the full telemetry update
      # For now, return true and let check_verifier_condition handle it
      verifier.match_criteria != nil
    end
  end

  defp check_verifier_condition(runner, verifier, value) do
    result =
      if verifier.telemetry_item_ref do
        check_simple_condition(verifier, value, runner.initial_value)
      else
        check_match_criteria(verifier.match_criteria, runner.mission_id, runner.target_id)
      end

    case result do
      :satisfied ->
        updated_runner = advance_stage(runner, :passed)

        if complete?(updated_runner) do
          {:all_complete, updated_runner}
        else
          {:stage_complete, updated_runner}
        end

      :pending ->
        {:pending, runner}

      other ->
        {:failed, runner, other}
    end
  end

  defp check_simple_condition(verifier, value, initial_value) do
    case verifier.comparison do
      :changed ->
        compare_changed(value, initial_value)

      :equal ->
        compare_equal(value, verifier.expected_value)

      :not_equal ->
        compare_not_equal(value, verifier.expected_value)

      :greater ->
        compare_number(value, verifier.expected_value, &>/2)

      :less ->
        compare_number(value, verifier.expected_value, &</2)

      :greater_equal ->
        compare_number(value, verifier.expected_value, &>=/2)

      :less_equal ->
        compare_number(value, verifier.expected_value, &<=/2)

      _ ->
        # Unknown comparison - any update satisfies
        :satisfied
    end
  end

  defp compare_changed(value, initial_value) do
    if value != initial_value, do: :satisfied, else: :pending
  end

  defp compare_equal(value, expected) do
    if values_match?(value, expected), do: :satisfied, else: :pending
  end

  defp compare_not_equal(value, expected) do
    if values_match?(value, expected), do: :pending, else: :satisfied
  end

  defp compare_number(value, expected, comparator) do
    if is_number(value) and comparator.(value, parse_number(expected)) do
      :satisfied
    else
      :pending
    end
  end

  defp check_match_criteria(_match_criteria, _mission_id, _target_id) do
    # TODO: Implement full MatchCriteria evaluation
    # For now, match criteria verification is not fully implemented
    # This would query the CVT and evaluate compound conditions
    Logger.warning("MatchCriteria evaluation not yet implemented, auto-satisfying")
    :satisfied
  end

  defp advance_stage(runner, result) do
    verifier = current_verifier(runner)

    # Cancel any pending timeout
    runner = cancel_timeout(runner)

    %{
      runner
      | current_index: runner.current_index + 1,
        stage_results: Map.put(runner.stage_results, verifier.stage, result),
        started_at: nil,
        initial_value: nil
    }
  end

  defp get_current_value(mission_id, target_id, item_ref) do
    {packet_name, item_name} = Verification.parse_item(item_ref)

    case CurrentValueTable.get(mission_id, target_id, packet_name, item_name) do
      {:ok, %{value: value}} -> value
      {:error, :not_found} -> nil
    end
  end

  defp values_match?(actual, expected) when is_binary(expected) do
    to_string(actual) == expected or actual == expected
  end

  defp values_match?(actual, expected) when is_number(expected) and is_number(actual) do
    abs(actual - expected) < 0.0001
  end

  defp values_match?(actual, expected) do
    actual == expected
  end

  defp parse_number(nil), do: 0

  defp parse_number(value) when is_number(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} ->
        num

      :error ->
        case Integer.parse(value) do
          {num, _} -> num
          :error -> 0
        end
    end
  end

  defp parse_number(_), do: 0
end
