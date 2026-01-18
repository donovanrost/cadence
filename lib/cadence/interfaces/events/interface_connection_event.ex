defmodule Cadence.Interfaces.Events.InterfaceConnectionEvent do
  @moduledoc """
  Event emitted when an interface's connection state changes.

  Connection events are broadcast via PubSub when:
  - An interface goes from disconnected to connected (first client connects)
  - An interface goes from connected to disconnected (last client disconnects)

  These events can trigger alarms to alert operators of communication loss.

  ## Event Structure

  - `id` - Unique event identifier
  - `mission_id` - Mission this event belongs to
  - `interface_id` - Interface that changed state
  - `interface_name` - Human-readable interface name
  - `previous_state` - State before transition (:connected or :disconnected)
  - `new_state` - State after transition (:connected or :disconnected)
  - `client_count` - Number of connected clients after the change
  - `client_info` - Info about the client that triggered the change (optional)
  - `timestamp` - When the transition occurred

  ## Connection States

  - `:connected` - At least one client is connected
  - `:disconnected` - No clients connected

  ## PubSub Topic

  Events are broadcast to: `mission:<mission_id>:events`

  ## Usage

      # Subscribe to connection events
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:\#{mission_id}:events")

      # Handle events
      def handle_info({:interface_connection_event, %InterfaceConnectionEvent{} = event}, state) do
        if event.new_state == :disconnected do
          Logger.warning("Interface \#{event.interface_name} lost all connections")
        end
        {:noreply, state}
      end
  """

  alias Cadence.Time, as: CadenceTime

  @type connection_state :: :connected | :disconnected

  @type t :: %__MODULE__{
          id: String.t(),
          mission_id: String.t(),
          interface_id: String.t(),
          interface_name: String.t() | nil,
          previous_state: connection_state(),
          new_state: connection_state(),
          client_count: non_neg_integer(),
          client_info: map() | nil,
          timestamp: DateTime.t()
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :mission_id,
    :interface_id,
    :interface_name,
    :previous_state,
    :new_state,
    :client_count,
    :client_info,
    :timestamp
  ]

  @doc """
  Creates a new InterfaceConnectionEvent.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      mission_id: attrs[:mission_id],
      interface_id: attrs[:interface_id],
      interface_name: attrs[:interface_name],
      previous_state: attrs[:previous_state],
      new_state: attrs[:new_state],
      client_count: attrs[:client_count] || 0,
      client_info: attrs[:client_info],
      timestamp: attrs[:timestamp] || CadenceTime.now()
    }
  end

  @doc """
  Returns true if this event represents a connection (recovery from disconnected).
  """
  @spec connected?(t()) :: boolean()
  def connected?(%__MODULE__{new_state: :connected}), do: true
  def connected?(_), do: false

  @doc """
  Returns true if this event represents a disconnection.
  """
  @spec disconnected?(t()) :: boolean()
  def disconnected?(%__MODULE__{new_state: :disconnected}), do: true
  def disconnected?(_), do: false

  @doc """
  Returns a human-readable description of the event.
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = event) do
    name = event.interface_name || event.interface_id

    case event.new_state do
      :connected ->
        "Interface #{name}: CONNECTED (#{event.client_count} client(s))"

      :disconnected ->
        "Interface #{name}: DISCONNECTED"
    end
  end

  @doc """
  Broadcasts this event to the mission's event topic.
  """
  @spec broadcast(t()) :: :ok
  def broadcast(%__MODULE__{} = event) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "mission:#{event.mission_id}:events",
      {:interface_connection_event, event}
    )
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
