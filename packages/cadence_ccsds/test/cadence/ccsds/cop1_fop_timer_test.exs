defmodule Cadence.CCSDS.Transport.COP1.FOPTimerTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Test.COP1FOPFixtures
  alias Cadence.CCSDS.Transport.COP1.FOP

  test "E16 retransmits AD in S1 and S2, ignores S3, and alerts in S4" do
    for state_name <- [:active, :retransmit_without_wait] do
      state = COP1FOPFixtures.sent_state(state_name, [1, 2])
      assert {:ok, transition} = FOP.timer_expired(state)
      assert transition.event == :e16
      assert transition.state.state == state_name
      assert transition.state.transmission_count == 2
      assert transition.abort_lower?
      assert transition.timer_action == :start
      assert [%{frame: %{seq: 1, retries: 1}}] = transition.transmit_requests
    end

    waiting = COP1FOPFixtures.sent_state(:retransmit_with_wait, [1, 2])
    assert {:ok, ignored} = FOP.timer_expired(waiting)
    assert ignored.event == :e16
    assert ignored.state.state == :retransmit_with_wait
    refute ignored.state.timer_running
    refute ignored.abort_lower?

    checking = COP1FOPFixtures.state(state: :initializing_without_bc, timer_running: true)
    assert {:ok, alerted} = FOP.timer_expired(checking)
    assert alerted.event == :e16
    assert alerted.alerts == [:t1]
    assert alerted.state.state == :initial
  end

  test "E104 uses the same below-limit retransmission path and suspends S4" do
    for state_name <- [:active, :retransmit_without_wait] do
      state = COP1FOPFixtures.sent_state(state_name, [3], timeout_type: 1)
      assert {:ok, transition} = FOP.timer_expired(state)
      assert transition.event == :e104
      assert transition.state.state == state_name
      assert transition.state.transmission_count == 2
      assert transition.timer_action == :start
    end

    checking =
      COP1FOPFixtures.state(
        state: :initializing_without_bc,
        timeout_type: 1,
        timer_running: true
      )

    assert {:ok, suspended} = FOP.timer_expired(checking)
    assert suspended.event == :e104
    assert suspended.state.state == :initial
    assert suspended.state.suspend_state == 4
    assert suspended.notifications == [{:suspend, 4}]
  end

  test "E16 and E104 retransmit the pending BC regardless of timeout type" do
    for timeout_type <- [0, 1] do
      state = COP1FOPFixtures.bc_state(timeout_type: timeout_type, bc_out_ready: true)
      assert {:ok, transition} = FOP.timer_expired(state)
      assert transition.event == if(timeout_type == 0, do: :e16, else: :e104)
      assert transition.state.state == :initializing_with_bc
      assert transition.state.transmission_count == 2
      assert transition.abort_lower?
      assert transition.timer_action == :start
      assert transition.transmit_bc_commands == [:unlock]
    end
  end

  test "E17 alerts with T1 at the transmission limit for timeout type zero" do
    for state <- [
          COP1FOPFixtures.sent_state(:active, [4], transmission_count: 3),
          COP1FOPFixtures.sent_state(:retransmit_without_wait, [4], transmission_count: 3),
          COP1FOPFixtures.sent_state(:retransmit_with_wait, [4], transmission_count: 3),
          COP1FOPFixtures.state(
            state: :initializing_without_bc,
            transmission_count: 3,
            timer_running: true
          ),
          COP1FOPFixtures.bc_state(transmission_count: 3)
        ] do
      assert {:ok, transition} = FOP.timer_expired(state)
      assert transition.event == :e17
      assert transition.alerts == [:t1]
      assert transition.state.state == :initial
      assert transition.timer_action == :cancel
    end
  end

  test "E18 suspends S1 through S4 and alerts S5 at the transmission limit" do
    states = [
      {COP1FOPFixtures.sent_state(:active, [5]), 1},
      {COP1FOPFixtures.sent_state(:retransmit_without_wait, [5]), 2},
      {COP1FOPFixtures.sent_state(:retransmit_with_wait, [5]), 3},
      {COP1FOPFixtures.state(state: :initializing_without_bc, timer_running: true), 4}
    ]

    for {state, suspend_state} <- states do
      state = %{state | timeout_type: 1, transmission_count: state.transmission_limit}
      assert {:ok, transition} = FOP.timer_expired(state)
      assert transition.event == :e18
      assert transition.state.state == :initial
      assert transition.state.suspend_state == suspend_state
      assert transition.notifications == [{:suspend, suspend_state}]
      assert transition.state.sent_queue == state.sent_queue
    end

    bc = COP1FOPFixtures.bc_state(timeout_type: 1, transmission_count: 3)
    assert {:ok, alerted} = FOP.timer_expired(bc)
    assert alerted.event == :e18
    assert alerted.alerts == [:t1]
    assert alerted.state.state == :initial
  end

  test "timer expiry is not applicable in S6" do
    initial = COP1FOPFixtures.state(state: :initial, timeout_type: 1, transmission_count: 3)
    assert {:ok, transition} = FOP.timer_expired(initial)
    assert transition.event == :e18
    assert transition.state.state == :initial
    assert transition.alerts == []
    assert transition.notifications == []
  end
end
