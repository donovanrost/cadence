defmodule Cadence.CCSDS.Transport.COP1.FOPLowerLayerTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Test.COP1FOPFixtures
  alias Cadence.CCSDS.Transport.COP1.FOP

  test "E41 makes AD output ready and continues queued retransmission work" do
    state = COP1FOPFixtures.sent_state(:retransmit_without_wait, [7, 8], ad_out_ready: false)

    sent_queue =
      Enum.map(state.sent_queue, fn entry -> %{entry | retransmit?: true} end)

    assert {:ok, transition} =
             FOP.lower_layer_response(%{state | sent_queue: sent_queue}, :ad_accept)

    assert transition.event == :e41
    refute transition.state.ad_out_ready
    assert [%{frame: %{seq: 7}}] = transition.transmit_requests
    assert Enum.at(transition.state.sent_queue, 0).retransmit? == false
    assert Enum.at(transition.state.sent_queue, 1).retransmit? == true
  end

  test "E42 generates Alert[LLIF] in every FOP state" do
    for state_name <- state_names() do
      state = COP1FOPFixtures.state(state: state_name)
      assert {:ok, transition} = FOP.lower_layer_response(state, :ad_reject)
      assert transition.event == :e42
      assert transition.alerts == [:llif]
      assert transition.state.state == :initial
    end
  end

  test "E43 makes BC output ready and sends a marked retransmission" do
    state = COP1FOPFixtures.bc_state(bc_out_ready: false)
    [entry] = state.sent_queue

    assert {:ok, transition} =
             FOP.lower_layer_response(
               %{state | sent_queue: [%{entry | retransmit?: true}]},
               :bc_accept
             )

    assert transition.event == :e43
    refute transition.state.bc_out_ready
    assert transition.transmit_bc_commands == [:unlock]
    assert [%{retransmit?: false}] = transition.state.sent_queue
  end

  test "E44 generates Alert[LLIF] in every FOP state" do
    for state_name <- state_names() do
      state = COP1FOPFixtures.state(state: state_name)
      assert {:ok, transition} = FOP.lower_layer_response(state, :bc_reject)
      assert transition.event == :e44
      assert transition.alerts == [:llif]
      assert transition.state.state == :initial
    end
  end

  test "E21, E22, and E45 implement expedited BD service in every state" do
    for state_name <- state_names() do
      state = COP1FOPFixtures.state(state: state_name)
      frame = %{frame_base64: Base.encode64(<<1, 2, 3>>)}

      assert {:ok, transmitted} = FOP.request_bd(state, frame, {:bd, state_name})
      assert transmitted.event == :e21
      assert {:fdu, :accept, {:bd, state_name}} in transmitted.notifications

      assert [%{frame_type: :bd, frame: %{frame_base64: "AQID", retries: 0}}] =
               transmitted.transmit_requests

      refute transmitted.state.bd_out_ready

      assert {:ok, busy} = FOP.request_bd(transmitted.state, frame, :second)
      assert busy.event == :e22
      assert busy.notifications == [{:fdu, :reject, :second}]

      assert {:ok, accepted} = FOP.lower_layer_response(transmitted.state, :bd_accept)
      assert accepted.event == :e45
      assert accepted.state.bd_out_ready
      assert {:fdu, :positive_confirm, {:bd, state_name}} in accepted.notifications
    end
  end

  test "synchronous BD service confirms immediately without a lower-layer callback" do
    state = COP1FOPFixtures.state(lower_layer_mode: :synchronous)
    frame = %{frame_base64: Base.encode64(<<9>>)}

    assert {:ok, transition} = FOP.request_bd(state, frame, :bd)
    assert transition.state.bd_out_ready

    assert transition.notifications == [
             {:fdu, :accept, :bd},
             {:fdu, :positive_confirm, :bd}
           ]
  end

  test "E46 generates Alert[LLIF] in every FOP state" do
    for state_name <- state_names() do
      state = COP1FOPFixtures.state(state: state_name)
      assert {:ok, transition} = FOP.lower_layer_response(state, :bd_reject)
      assert transition.event == :e46
      assert transition.alerts == [:llif]
      assert transition.state.state == :initial
    end
  end

  defp state_names do
    [
      :active,
      :retransmit_without_wait,
      :retransmit_with_wait,
      :initializing_without_bc,
      :initializing_with_bc,
      :initial
    ]
  end
end
