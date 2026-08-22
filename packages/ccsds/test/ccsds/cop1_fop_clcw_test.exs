defmodule CCSDS.Transport.COP1.FOPCLCWTest do
  use ExUnit.Case, async: true

  alias CCSDS.Test.COP1FOPFixtures
  alias CCSDS.Transport.COP1.FOP

  test "E1 handles an unchanged clean CLCW according to all six states" do
    assert_event_and_state(:active, :e1, :active, [])
    assert_event_and_state(:retransmit_without_wait, :e1, :initial, [:synch])
    assert_event_and_state(:retransmit_with_wait, :e1, :initial, [:synch])

    directive = %{type: :initiate_ad_with_clcw_check, qualifier: nil, request_id: :start}

    s4 =
      COP1FOPFixtures.state(
        state: :initializing_without_bc,
        pending_directive: directive,
        timer_running: true
      )

    assert {:ok, s4_transition} = FOP.apply_clcw(s4, COP1FOPFixtures.clcw())
    assert s4_transition.event == :e1
    assert s4_transition.state.state == :active
    assert s4_transition.timer_action == :cancel
    assert {:directive, :positive_confirm, directive} in s4_transition.notifications

    s5 = COP1FOPFixtures.bc_state()
    assert {:ok, s5_transition} = FOP.apply_clcw(s5, COP1FOPFixtures.clcw())
    assert s5_transition.event == :e1
    assert s5_transition.state.state == :active
    assert s5_transition.state.sent_queue == []
    assert s5_transition.timer_action == :cancel

    initial = COP1FOPFixtures.state(state: :initial)
    assert {:ok, ignored} = FOP.apply_clcw(initial, COP1FOPFixtures.clcw())
    assert ignored.event == :e1
    assert ignored.state.state == :initial
  end

  test "E2 and E6 remove acknowledged frames, including across sequence rollover" do
    state = COP1FOPFixtures.sent_state(:retransmit_with_wait, [254, 255, 0])

    assert {:ok, partial} =
             FOP.apply_clcw(state, COP1FOPFixtures.clcw(report_value: 0))

    assert partial.event == :e6
    assert partial.state.state == :active
    assert partial.state.nnr == 0
    assert Enum.map(partial.state.sent_queue, & &1.frame.seq) == [0]
    assert partial.timer_action == :none
    assert partial.cancel_timeout_seqs == [254, 255]

    assert {:ok, complete} =
             FOP.apply_clcw(partial.state, COP1FOPFixtures.clcw(report_value: 1))

    assert complete.event == :e2
    assert complete.state.sent_queue == []
    assert complete.state.nnr == 1
    assert complete.timer_action == :cancel
    assert complete.cancel_timeout_seqs == [0]
  end

  test "E3 and E7 reject inconsistent Wait flag combinations" do
    all_acknowledged = COP1FOPFixtures.sent_state(:active, [5])

    assert {:ok, e3} =
             FOP.apply_clcw(
               all_acknowledged,
               COP1FOPFixtures.clcw(report_value: 6, wait: 1)
             )

    assert e3.event == :e3
    assert e3.alerts == [:clcw]
    assert e3.state.state == :initial

    outstanding = COP1FOPFixtures.sent_state(:active, [5, 6])

    assert {:ok, e7} =
             FOP.apply_clcw(outstanding, COP1FOPFixtures.clcw(report_value: 5, wait: 1))

    assert e7.event == :e7
    assert e7.alerts == [:clcw]
  end

  test "E4 detects synchronization loss except while waiting for a BC clean CLCW" do
    for state_name <- [
          :active,
          :retransmit_without_wait,
          :retransmit_with_wait,
          :initializing_without_bc
        ] do
      state = COP1FOPFixtures.state(state: state_name)

      assert {:ok, transition} =
               FOP.apply_clcw(state, COP1FOPFixtures.clcw(retransmit: 1))

      assert transition.event == :e4
      assert transition.alerts == [:synch]
      assert transition.state.state == :initial
    end

    s5 = COP1FOPFixtures.bc_state()
    assert {:ok, ignored} = FOP.apply_clcw(s5, COP1FOPFixtures.clcw(retransmit: 1))
    assert ignored.event == :e4
    assert ignored.alerts == []
    assert ignored.state.state == :initializing_with_bc
  end

  test "E5 detects synchronization loss in retransmission states" do
    active = COP1FOPFixtures.sent_state(:active, [10, 11])
    assert {:ok, ignored} = FOP.apply_clcw(active, COP1FOPFixtures.clcw(report_value: 10))
    assert ignored.event == :e5
    assert ignored.state.state == :active

    for state_name <- [:retransmit_without_wait, :retransmit_with_wait] do
      state = COP1FOPFixtures.sent_state(state_name, [10, 11])
      assert {:ok, transition} = FOP.apply_clcw(state, COP1FOPFixtures.clcw(report_value: 10))
      assert transition.event == :e5
      assert transition.alerts == [:synch]
    end
  end

  test "E101 and E102 alert at transmission limit one, acknowledging progress first" do
    state = COP1FOPFixtures.sent_state(:active, [20, 21], transmission_limit: 1)

    assert {:ok, progress} =
             FOP.apply_clcw(
               state,
               COP1FOPFixtures.clcw(report_value: 21, retransmit: 1)
             )

    assert progress.event == :e101
    assert progress.alerts == [:limit]
    assert progress.state.state == :initial
    assert {:fdu, :positive_confirm, {:request, 20}} in progress.notifications
    assert {:fdu, :negative_confirm, {:request, 21}} in progress.notifications

    assert {:ok, no_progress} =
             FOP.apply_clcw(state, COP1FOPFixtures.clcw(report_value: 20, retransmit: 1))

    assert no_progress.event == :e102
    assert no_progress.alerts == [:limit]
  end

  test "E8 and E9 acknowledge progress and enter retransmission states" do
    state = COP1FOPFixtures.sent_state(:active, [30, 31, 32])

    assert {:ok, without_wait} =
             FOP.apply_clcw(
               state,
               COP1FOPFixtures.clcw(report_value: 31, retransmit: 1)
             )

    assert without_wait.event == :e8
    assert without_wait.state.state == :retransmit_without_wait
    assert without_wait.state.transmission_count == 2
    assert without_wait.abort_lower?
    assert [%{frame: %{seq: 31, retries: 1}}] = without_wait.transmit_requests

    assert {:ok, with_wait} =
             FOP.apply_clcw(
               state,
               COP1FOPFixtures.clcw(report_value: 31, retransmit: 1, wait: 1)
             )

    assert with_wait.event == :e9
    assert with_wait.state.state == :retransmit_with_wait
    assert Enum.map(with_wait.state.sent_queue, & &1.frame.seq) == [31, 32]
    refute with_wait.abort_lower?
    assert with_wait.transmit_requests == []
  end

  test "E10 through E12 and E103 handle repeated negative acknowledgements" do
    state = COP1FOPFixtures.sent_state(:active, [40, 41])

    assert {:ok, e10} =
             FOP.apply_clcw(state, COP1FOPFixtures.clcw(report_value: 40, retransmit: 1))

    assert e10.event == :e10
    assert e10.state.state == :retransmit_without_wait
    assert e10.state.transmission_count == 2
    assert [%{frame: %{seq: 40}}] = e10.transmit_requests

    assert {:ok, e11} =
             FOP.apply_clcw(
               state,
               COP1FOPFixtures.clcw(report_value: 40, retransmit: 1, wait: 1)
             )

    assert e11.event == :e11
    assert e11.state.state == :retransmit_with_wait
    assert e11.state.transmission_count == 1

    at_limit = %{state | transmission_count: 3}

    assert {:ok, e12} =
             FOP.apply_clcw(
               at_limit,
               COP1FOPFixtures.clcw(report_value: 40, retransmit: 1)
             )

    assert e12.event == :e12
    assert e12.state.state == :retransmit_without_wait
    assert e12.alerts == []

    assert {:ok, e103} =
             FOP.apply_clcw(
               at_limit,
               COP1FOPFixtures.clcw(report_value: 40, retransmit: 1, wait: 1)
             )

    assert e103.event == :e103
    assert e103.state.state == :retransmit_with_wait
    assert e103.alerts == []
  end

  test "E13 through E15 generate the standardized NNR, Lockout, and CLCW alerts" do
    state = COP1FOPFixtures.sent_state(:active, [50, 51])

    assert_alert(state, COP1FOPFixtures.clcw(report_value: 53), :e13, :nnr)
    assert_alert(state, COP1FOPFixtures.clcw(lockout: 1), :e14, :lockout)
    assert_alert(state, COP1FOPFixtures.clcw(spare_1: 1), :e15, :clcw)

    for {attrs, event} <- [
          {%{report_value: 53}, :e13},
          {%{lockout: 1}, :e14}
        ] do
      s5 = COP1FOPFixtures.bc_state()
      assert {:ok, ignored} = FOP.apply_clcw(s5, COP1FOPFixtures.clcw(attrs))
      assert ignored.event == event
      assert ignored.alerts == []
      assert ignored.state.state == :initializing_with_bc
    end
  end

  test "pre-table COP and virtual-channel checks ignore unrelated CLCWs" do
    state = COP1FOPFixtures.sent_state(:active, [1])

    for clcw <- [
          COP1FOPFixtures.clcw(cop_in_effect: 0, report_value: 1),
          COP1FOPFixtures.clcw(vcid: 1, report_value: 1)
        ] do
      assert {:ok, transition} = FOP.apply_clcw(state, clcw)
      assert transition.event == :ignored_clcw
      assert transition.state == state
      assert transition.notifications == []
    end
  end

  defp assert_event_and_state(source_state, event, result_state, alerts) do
    state = COP1FOPFixtures.state(state: source_state)
    assert {:ok, transition} = FOP.apply_clcw(state, COP1FOPFixtures.clcw())
    assert transition.event == event
    assert transition.state.state == result_state
    assert transition.alerts == alerts
  end

  defp assert_alert(state, clcw, event, reason) do
    assert {:ok, transition} = FOP.apply_clcw(state, clcw)
    assert transition.event == event
    assert transition.alerts == [reason]
    assert transition.state.state == :initial
    assert transition.state.sent_queue == []
  end
end
