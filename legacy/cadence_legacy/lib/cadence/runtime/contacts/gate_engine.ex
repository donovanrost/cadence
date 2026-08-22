defmodule Cadence.Runtime.Contacts.GateEngine do
  @moduledoc """
  Pure gate evaluation engine for contact readiness.
  """

  @type gate :: :active | :uplink_ready
  @type signal :: {:transport_connected, String.t(), boolean()}

  @type t :: %__MODULE__{
          gate_states: map(),
          transport_connected: map(),
          transport_ids: [String.t()],
          uplink_transport_id: String.t() | nil
        }

  defstruct gate_states: %{},
            transport_connected: %{},
            transport_ids: [],
            uplink_transport_id: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    transport_ids = Keyword.get(opts, :transport_ids, [])
    uplink_transport_id = Keyword.get(opts, :uplink_transport_id)
    gates = Keyword.get(opts, :gates, [:uplink_ready])

    gate_states =
      Enum.reduce(gates, %{}, fn gate, acc ->
        Map.put(acc, gate, initial_gate_state(gate))
      end)

    %__MODULE__{
      gate_states: gate_states,
      transport_connected: %{},
      transport_ids: transport_ids,
      uplink_transport_id: uplink_transport_id
    }
  end

  @spec ingest_signal(t(), signal()) :: {t(), list()}
  def ingest_signal(%__MODULE__{} = state, {:transport_connected, transport_id, connected?}) do
    transport_connected = Map.put(state.transport_connected, transport_id, connected?)
    state = %{state | transport_connected: transport_connected}

    update_gate(state, :uplink_ready, %{transport_id: transport_id, connected: connected?})
  end

  @spec gate_satisfied?(t(), gate()) :: boolean()
  def gate_satisfied?(%__MODULE__{} = state, gate) do
    Map.get(state.gate_states, gate, false)
  end

  defp initial_gate_state(:active), do: true
  defp initial_gate_state(_), do: false

  defp update_gate(%__MODULE__{} = state, gate, details) do
    previous = Map.get(state.gate_states, gate, false)
    current = evaluate_gate(state, gate)
    state = put_in(state.gate_states[gate], current)

    events =
      if current == true and previous == false do
        [{:gate_satisfied, gate, details}]
      else
        []
      end

    {state, events}
  end

  defp evaluate_gate(%__MODULE__{} = state, :uplink_ready) do
    case state.uplink_transport_id do
      nil ->
        Enum.any?(state.transport_ids, fn id -> Map.get(state.transport_connected, id, false) end)

      uplink_id ->
        Map.get(state.transport_connected, uplink_id, false)
    end
  end

  defp evaluate_gate(_state, _gate), do: false
end
