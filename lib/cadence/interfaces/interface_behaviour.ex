defmodule Cadence.Interfaces.Interface do
  @moduledoc """
  Behaviour for telemetry/command interfaces.

  An interface represents a communication channel to/from spacecraft or ground systems.
  Common interface types:
  - TCP Client: Connect to a spacecraft simulator or ground station
  - TCP Server: Accept connections from spacecraft
  - UDP: Send/receive datagrams
  - Serial: Direct serial port communication

  Each interface implementation must:
  - Handle connection lifecycle (connect, disconnect, reconnect)
  - Send raw data to the target
  - Receive raw data and forward to telemetry pipeline
  - Report connection status
  """

  @type interface_config :: %{
          required(:type) => :tcp_client | :tcp_server | :udp | :serial,
          required(:target_id) => binary(),
          optional(:host) => String.t(),
          optional(:port) => integer(),
          optional(:device) => String.t(),
          optional(:baud_rate) => integer(),
          optional(atom()) => any()
        }

  @type interface_state :: %{
          config: interface_config(),
          connected: boolean(),
          connection: any(),
          stats: map()
        }

  @doc """
  Invoked when the interface is started.
  Should establish the connection and return initial state.
  """
  @callback init(config :: interface_config()) ::
              {:ok, state :: interface_state()} | {:error, reason :: any()}

  @doc """
  Sends data through the interface.
  """
  @callback send_data(data :: binary(), state :: interface_state()) ::
              {:ok, state :: interface_state()}
              | {:error, reason :: any(), state :: interface_state()}

  @doc """
  Handles received data from the interface.
  """
  @callback handle_data(data :: binary(), state :: interface_state()) ::
              {:ok, state :: interface_state()}

  @doc """
  Returns the current connection status.
  """
  @callback connected?(state :: interface_state()) :: boolean()

  @doc """
  Disconnects the interface.
  """
  @callback disconnect(state :: interface_state()) :: {:ok, state :: interface_state()}
end
