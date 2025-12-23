defmodule Cadence.Commands.Verification do
  @moduledoc """
  Command verification logic.

  Handles automatic verification of commands by monitoring the CVT
  for expected telemetry changes after command execution.

  ## Verification Modes

  - `:any_update` - Verify when the item receives any update
  - `:value_match` - Verify when the item matches an expected value
  - `:count_increment` - Verify when a counter increments
  - `:range` - Verify when value falls within a range

  ## Example

      # Simple verification - any update to the item
      Verification.start(command_log_id, %{
        mission_id: mission_id,
        target_id: target_id,
        item: "HEALTH.CMD_ACK",
        timeout_ms: 5000
      })

      # Value match verification
      Verification.start(command_log_id, %{
        mission_id: mission_id,
        target_id: target_id,
        item: "THERMAL.MODE",
        expected_value: "HEATING",
        timeout_ms: 5000
      })
  """

  require Logger

  alias Cadence.Runtime.Telemetry.CurrentValueTable

  @doc """
  Verification configuration struct.
  """
  defstruct [
    :command_log_id,
    :mission_id,
    :target_id,
    :item,
    :expected_value,
    :mode,
    :timeout_ms,
    :started_at,
    :initial_value,
    :timeout_ref,
    callback: nil
  ]

  @type t :: %__MODULE__{
          command_log_id: String.t(),
          mission_id: String.t(),
          target_id: String.t(),
          item: String.t(),
          expected_value: term(),
          mode: :any_update | :value_match | :count_increment | :range,
          timeout_ms: non_neg_integer(),
          started_at: DateTime.t(),
          initial_value: term(),
          timeout_ref: reference() | nil,
          callback: (result :: term() -> :ok) | nil
        }

  @doc """
  Creates a new verification configuration.

  ## Options

  - `:item` - The CVT item to watch (e.g., "HEALTH.CMD_ACK")
  - `:expected_value` - Expected value for :value_match mode
  - `:mode` - Verification mode (default: :any_update)
  - `:timeout_ms` - Timeout in milliseconds (default: 5000)
  - `:callback` - Optional callback function called on completion
  """
  def new(command_log_id, mission_id, target_id, opts) do
    item = Keyword.fetch!(opts, :item)
    expected_value = Keyword.get(opts, :expected_value)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    callback = Keyword.get(opts, :callback)

    mode =
      cond do
        Keyword.has_key?(opts, :expected_value) -> :value_match
        Keyword.get(opts, :count_increment) -> :count_increment
        Keyword.has_key?(opts, :range) -> :range
        true -> :any_update
      end

    # Get initial value if in count_increment mode
    initial_value =
      if mode == :count_increment do
        get_current_value(mission_id, target_id, item)
      else
        nil
      end

    %__MODULE__{
      command_log_id: command_log_id,
      mission_id: mission_id,
      target_id: target_id,
      item: item,
      expected_value: expected_value,
      mode: mode,
      timeout_ms: timeout_ms,
      started_at: DateTime.utc_now(),
      initial_value: initial_value,
      callback: callback
    }
  end

  @doc """
  Checks if a telemetry update satisfies the verification criteria.

  Returns:
  - `{:verified, actual_value}` - Verification succeeded
  - `:pending` - Keep waiting
  - `{:failed, reason}` - Verification failed (won't retry)
  """
  @spec check_update(t(), term()) :: {:verified, term()} | :pending | {:failed, term()}
  def check_update(%__MODULE__{mode: :any_update}, value) do
    {:verified, value}
  end

  def check_update(%__MODULE__{mode: :value_match, expected_value: expected}, value) do
    if values_match?(value, expected) do
      {:verified, value}
    else
      :pending
    end
  end

  def check_update(%__MODULE__{mode: :count_increment, initial_value: initial}, value)
      when is_number(value) and is_number(initial) do
    if value > initial do
      {:verified, value}
    else
      :pending
    end
  end

  def check_update(%__MODULE__{mode: :count_increment, initial_value: nil}, value) do
    # No initial value - any value counts as increment
    {:verified, value}
  end

  def check_update(%__MODULE__{mode: :range, expected_value: {min, max}}, value)
      when is_number(value) do
    if value >= min and value <= max do
      {:verified, value}
    else
      :pending
    end
  end

  def check_update(_verification, _value) do
    :pending
  end

  @doc """
  Checks if the verification has timed out.
  """
  @spec timed_out?(t()) :: boolean()
  def timed_out?(%__MODULE__{started_at: started_at, timeout_ms: timeout_ms}) do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    elapsed_ms >= timeout_ms
  end

  @doc """
  Parses an item string into packet_name and item_name.

  ## Examples

      iex> Verification.parse_item("HEALTH.CMD_ACK")
      {"HEALTH", "CMD_ACK"}

      iex> Verification.parse_item("THERMAL.TEMP.SENSOR_1")
      {"THERMAL", "TEMP.SENSOR_1"}
  """
  @spec parse_item(String.t()) :: {String.t(), String.t()}
  def parse_item(item) when is_binary(item) do
    case String.split(item, ".", parts: 2) do
      [packet, item_name] -> {packet, item_name}
      [item_name] -> {"", item_name}
    end
  end

  @doc """
  Matches a telemetry update against a verification.

  Returns true if the update is for the item being verified.
  """
  @spec matches_update?(t(), String.t(), String.t(), String.t()) :: boolean()
  def matches_update?(%__MODULE__{} = verification, target_id, packet_name, item_name) do
    {expected_packet, expected_item} = parse_item(verification.item)

    verification.target_id == target_id and
      expected_packet == packet_name and
      expected_item == item_name
  end

  # Private functions

  defp get_current_value(mission_id, target_id, item) do
    {packet_name, item_name} = parse_item(item)

    case CurrentValueTable.get(mission_id, target_id, packet_name, item_name) do
      {:ok, %{value: value}} -> value
      {:error, :not_found} -> nil
    end
  end

  defp values_match?(actual, expected) when is_binary(expected) do
    to_string(actual) == expected or actual == expected
  end

  defp values_match?(actual, expected) when is_number(expected) and is_number(actual) do
    # Allow for floating point comparison
    abs(actual - expected) < 0.0001
  end

  defp values_match?(actual, expected) do
    actual == expected
  end
end
