defmodule CCSDS.Transport.COP1.FARMTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.LinkFrame
  alias CCSDS.Transport.COP1.FARM

  test "accepts the expected Type-AD frame and reports the next sequence number" do
    farm = farm!(vcid: 3, receiver_frame_sequence_number: 255)

    assert {:ok, transition} = FARM.process_frame(farm, frame(:ad, 255))
    assert transition.event == :e1
    assert transition.disposition == :accept
    assert transition.deliver?
    assert transition.state.state == :open
    assert transition.state.receiver_frame_sequence_number == 0
    refute transition.state.retransmit

    clcw = FARM.clcw(transition.state)
    assert clcw.vcid == 3
    assert clcw.report_value == 0
    assert clcw.lockout == 0
    assert clcw.wait == 0
    assert clcw.retransmit == 0
  end

  test "enters Wait when the expected Type-AD frame has no receive buffer" do
    farm = farm!(receiver_frame_sequence_number: 12)

    assert {:ok, transition} =
             FARM.process_frame(farm, frame(:ad, 12), buffer_available?: false)

    assert transition.event == :e2
    assert transition.disposition == :discard
    refute transition.deliver?
    assert transition.state.state == :wait
    assert transition.state.retransmit
    assert transition.state.receiver_frame_sequence_number == 12

    clcw = FARM.clcw(transition.state)
    assert clcw.wait == 1
    assert clcw.retransmit == 1

    release = FARM.buffer_released(transition.state)
    assert release.event == :e10
    assert release.state.state == :open
    assert release.state.retransmit
  end

  test "sets Retransmit for an ahead Type-AD frame inside the positive window" do
    farm = farm!(receiver_frame_sequence_number: 250)

    assert {:ok, transition} = FARM.process_frame(farm, frame(:ad, 2))
    assert transition.event == :e3
    assert transition.disposition == :discard
    assert transition.state.state == :open
    assert transition.state.retransmit
    assert transition.state.receiver_frame_sequence_number == 250
  end

  test "silently discards a duplicate Type-AD frame inside the negative window" do
    farm = farm!(receiver_frame_sequence_number: 2, retransmit: true)

    assert {:ok, transition} = FARM.process_frame(farm, frame(:ad, 250))
    assert transition.event == :e4
    assert transition.disposition == :discard
    assert transition.state.state == :open
    assert transition.state.retransmit
  end

  test "enters Lockout for a Type-AD frame outside the sliding window" do
    farm =
      farm!(
        receiver_frame_sequence_number: 0,
        positive_window_width: 2,
        negative_window_width: 2
      )

    assert {:ok, transition} = FARM.process_frame(farm, frame(:ad, 3))
    assert transition.event == :e5
    assert transition.disposition == :discard
    assert transition.state.state == :lockout

    clcw = FARM.clcw(transition.state)
    assert clcw.lockout == 1
    assert clcw.report_value == 0
  end

  test "accepts Type-BD data and increments FARM-B in every state" do
    farm = farm!(state: :lockout, farm_b_counter: 3)

    assert {:ok, transition} = FARM.process_frame(farm, frame(:bd, 88))
    assert transition.event == :e6
    assert transition.disposition == :accept
    assert transition.deliver?
    assert transition.state.state == :lockout
    assert transition.state.farm_b_counter == 4
    assert FARM.clcw(transition.state).farm_b_counter == 0
  end

  test "Unlock clears Wait, Lockout, and Retransmit without changing V(R)" do
    for initial_state <- [:open, :wait, :lockout] do
      farm =
        farm!(
          state: initial_state,
          retransmit: true,
          receiver_frame_sequence_number: 19
        )

      assert {:ok, transition} = FARM.process_frame(farm, frame(:bc, 0, <<0>>))
      assert transition.event == :e7
      assert transition.disposition == :accept
      assert transition.control_command == :unlock
      assert transition.control_command_executed?
      assert transition.state.state == :open
      refute transition.state.retransmit
      assert transition.state.receiver_frame_sequence_number == 19
      assert transition.state.farm_b_counter == 1
    end
  end

  test "Set V(R) opens Open and Wait states but is not executed in Lockout" do
    for initial_state <- [:open, :wait] do
      farm = farm!(state: initial_state, retransmit: true)

      assert {:ok, transition} =
               FARM.process_frame(farm, frame(:bc, 0, <<0x82, 0, 41>>))

      assert transition.event == :e8
      assert transition.control_command == {:set_vr, 41}
      assert transition.control_command_executed?
      assert transition.state.state == :open
      refute transition.state.retransmit
      assert transition.state.receiver_frame_sequence_number == 41
      assert transition.state.farm_b_counter == 1
    end

    locked = farm!(state: :lockout, retransmit: true, receiver_frame_sequence_number: 9)
    assert {:ok, transition} = FARM.process_frame(locked, frame(:bc, 0, <<0x82, 0, 41>>))
    refute transition.control_command_executed?
    assert transition.state.state == :lockout
    assert transition.state.retransmit
    assert transition.state.receiver_frame_sequence_number == 9
    assert transition.state.farm_b_counter == 1
  end

  test "treats an unknown Type-BC command as invalid without incrementing FARM-B" do
    farm = farm!(state: :wait, retransmit: true, farm_b_counter: 2)

    assert {:ok, transition} = FARM.process_frame(farm, frame(:bc, 0, <<1>>))
    assert transition.event == :e9
    assert transition.disposition == :discard
    assert transition.state == farm
  end

  test "keeps all Type-AD frames discarded while Wait or Lockout is active" do
    wait = farm!(state: :wait, receiver_frame_sequence_number: 7, retransmit: true)
    locked = farm!(state: :lockout, receiver_frame_sequence_number: 7)

    assert {:ok, wait_transition} = FARM.process_frame(wait, frame(:ad, 7))
    assert wait_transition.event == :e2
    assert wait_transition.state == wait

    assert {:ok, locked_transition} = FARM.process_frame(locked, frame(:ad, 7))
    assert locked_transition.event == :e1
    assert locked_transition.state == locked
  end

  test "moves from Wait to Lockout for a Type-AD frame outside the sliding window" do
    farm =
      farm!(
        state: :wait,
        retransmit: true,
        receiver_frame_sequence_number: 0,
        positive_window_width: 2,
        negative_window_width: 2
      )

    assert {:ok, transition} = FARM.process_frame(farm, frame(:ad, 3))
    assert transition.event == :e5
    assert transition.disposition == :discard
    assert transition.state.state == :lockout
    assert transition.state.retransmit
  end

  test "supports the retransmission-not-allowed window profile" do
    farm =
      farm!(
        retransmission_allowed: false,
        positive_window_width: 256,
        negative_window_width: 0
      )

    assert farm.sliding_window_width == 256
    assert {:ok, transition} = FARM.process_frame(farm, frame(:ad, 255))
    assert transition.event == :e3
    assert transition.state.state == :open
  end

  test "validates managed window parameters and virtual-channel ownership" do
    assert {:error, {:unequal_retransmission_windows, 3, 2}} =
             FARM.new(positive_window_width: 3, negative_window_width: 2)

    assert {:error, {:invalid_field, :sliding_window_width, 257}} =
             FARM.new(
               retransmission_allowed: false,
               positive_window_width: 256,
               negative_window_width: 1
             )

    farm = farm!(vcid: 3)
    assert {:error, {:vcid_mismatch, 3, 4}} = FARM.process_frame(farm, frame(:ad, 0, <<>>, 4))
  end

  defp farm!(attrs) do
    attrs = Map.new(attrs)
    {:ok, farm} = FARM.new(Map.put_new(attrs, :vcid, 3))
    farm
  end

  defp frame(type, sequence_number, payload \\ <<0xAA>>, vcid \\ 3) do
    {bypass_flag, control_command_flag} =
      case type do
        :ad -> {0, 0}
        :bd -> {1, 0}
        :bc -> {1, 1}
      end

    %LinkFrame{
      profile: :tc,
      scid: 42,
      vcid: vcid,
      frame_seq: sequence_number,
      payload_octets: payload,
      quality: :good,
      meta: %{
        bypass_flag: bypass_flag,
        control_command_flag: control_command_flag
      }
    }
  end
end
