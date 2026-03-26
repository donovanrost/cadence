defmodule Cadence.Runtime.Contacts.GateEngineTest do
  use Cadence.PureCase, async: true

  alias Cadence.Runtime.Contacts.GateEngine

  test "transport connection transitions emit gate_satisfied once" do
    transport_id = Ecto.UUID.generate()

    state =
      GateEngine.new(
        transport_ids: [transport_id],
        uplink_transport_id: transport_id,
        gates: [:uplink_ready]
      )

    {state, events} = GateEngine.ingest_signal(state, {:transport_connected, transport_id, true})

    assert events == [
             {:gate_satisfied, :uplink_ready, %{transport_id: transport_id, connected: true}}
           ]

    {_state, events} = GateEngine.ingest_signal(state, {:transport_connected, transport_id, true})
    assert events == []
  end
end
