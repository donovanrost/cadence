defmodule Cadence.Telemetry.Events.TelemetryLimitEvent do
  @moduledoc """
  Event emitted when a telemetry item's limit state changes.

  Limit events are broadcast via PubSub when:
  - An item transitions from one limit state to another
  - An item becomes stale (transitions to :blue)
  - An item recovers from a violation (returns to :green)

  ## Event Structure

  - `id` - Unique event identifier
  - `mission_id` - Mission this event belongs to
  - `target_id` - Target (spacecraft/entity) identifier
  - `item_name` - Fully qualified item name (e.g., "HEALTH.cpu_temp")
  - `previous_state` - State before transition
  - `new_state` - State after transition
  - `value` - The telemetry value that triggered the transition (nil for stale transitions)
  - `limit_set` - Active limit set name when transition occurred
  - `timestamp` - When the transition occurred

  ## Limit States

  - `:green` - Within all limits
  - `:yellow` - Warning threshold violated
  - `:red` - Critical threshold violated
  - `:blue` - Stale data (no update within timeout)

  ## PubSub Topic

  Events are broadcast to: `mission:<mission_id>:events`

  ## Usage

      # Subscribe to limit events
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:\#{mission_id}:events")

      # Handle events
      def handle_info({:limit_event, %TelemetryLimitEvent{} = event}, state) do
        Logger.warning("Limit violation: \#{event.item_name} -> \#{event.new_state}")
        {:noreply, state}
      end
  """

  @type t :: %__MODULE__{
          id: String.t(),
          mission_id: String.t(),
          target_id: String.t(),
          item_name: String.t(),
          previous_state: :green | :yellow | :red | :blue,
          new_state: :green | :yellow | :red | :blue,
          value: any() | nil,
          limit_set: String.t(),
          timestamp: DateTime.t()
        }

  alias Cadence.Time, as: CadenceTime

  @derive Jason.Encoder
  defstruct [
    :id,
    :mission_id,
    :target_id,
    :item_name,
    :previous_state,
    :new_state,
    :value,
    :limit_set,
    :timestamp
  ]

  @doc """
  Creates a new TelemetryLimitEvent.

  ## Parameters

  - `attrs` - Map of event attributes

  ## Example

      event = TelemetryLimitEvent.new(%{
        mission_id: "mission-123",
        target_id: "SAT-1",
        item_name: "HEALTH.cpu_temp",
        previous_state: :green,
        new_state: :red,
        value: 105.0,
        limit_set: "NOMINAL"
      })
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      mission_id: attrs[:mission_id],
      target_id: attrs[:target_id],
      item_name: attrs[:item_name],
      previous_state: attrs[:previous_state],
      new_state: attrs[:new_state],
      value: attrs[:value],
      limit_set: attrs[:limit_set] || "UNKNOWN",
      timestamp: attrs[:timestamp] || CadenceTime.now()
    }
  end

  @doc """
  Returns true if this event represents an escalation (more severe state).

  ## Examples

      iex> TelemetryLimitEvent.escalation?(%TelemetryLimitEvent{previous_state: :green, new_state: :red})
      true

      iex> TelemetryLimitEvent.escalation?(%TelemetryLimitEvent{previous_state: :red, new_state: :green})
      false
  """
  @spec escalation?(t()) :: boolean()
  def escalation?(%__MODULE__{previous_state: prev, new_state: new}) do
    severity(new) > severity(prev)
  end

  @doc """
  Returns true if this event represents a recovery (less severe state).

  ## Examples

      iex> TelemetryLimitEvent.recovery?(%TelemetryLimitEvent{previous_state: :red, new_state: :green})
      true

      iex> TelemetryLimitEvent.recovery?(%TelemetryLimitEvent{previous_state: :green, new_state: :red})
      false
  """
  @spec recovery?(t()) :: boolean()
  def recovery?(%__MODULE__{previous_state: prev, new_state: new}) do
    severity(new) < severity(prev)
  end

  @doc """
  Returns true if this event represents a stale data condition.
  """
  @spec stale?(t()) :: boolean()
  def stale?(%__MODULE__{new_state: :blue}), do: true
  def stale?(_), do: false

  @doc """
  Returns a human-readable description of the event.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = event) do
    direction =
      cond do
        escalation?(event) -> "ESCALATED"
        recovery?(event) -> "RECOVERED"
        stale?(event) -> "STALE"
        true -> "CHANGED"
      end

    "#{event.item_name}: #{event.previous_state} -> #{event.new_state} (#{direction})"
  end

  # Private functions

  defp severity(:green), do: 0
  defp severity(:blue), do: 0
  defp severity(:yellow), do: 1
  defp severity(:red), do: 2

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
