defmodule CCSDS.Transport.COP1.FOPDirectiveTest do
  use ExUnit.Case, async: true

  alias CCSDS.Test.COP1FOPFixtures
  alias CCSDS.Transport.COP1.FOP

  test "E23 initializes AD service without a CLCW check" do
    state = COP1FOPFixtures.state(state: :initial, suspend_state: 3)

    assert {:ok, transition} =
             FOP.directive(state, :initiate_ad_without_clcw_check, nil, request_id: :start)

    assert transition.event == :e23
    assert transition.state.state == :active
    assert transition.state.suspend_state == 0
    assert transition.timer_action == :none
    assert directive_statuses(transition) == [:accept, :positive_confirm]
  end

  test "E24 waits for a clean CLCW and then confirms initialization" do
    state = COP1FOPFixtures.state(state: :initial)

    assert {:ok, started} =
             FOP.directive(state, :initiate_ad_with_clcw_check, nil, request_id: :start)

    assert started.event == :e24
    assert started.state.state == :initializing_without_bc
    assert started.state.pending_directive.request_id == :start
    assert started.timer_action == :start
    assert directive_statuses(started) == [:accept]

    assert {:ok, confirmed} =
             FOP.apply_clcw(started.state, COP1FOPFixtures.clcw(report_value: 0))

    assert confirmed.event == :e1
    assert confirmed.state.state == :active
    assert confirmed.state.pending_directive == nil
    assert confirmed.timer_action == :cancel
    assert directive_statuses(confirmed) == [:positive_confirm]
  end

  test "E25 and E27 initialize with Unlock and Set V(R) BC commands" do
    initial = COP1FOPFixtures.state(state: :initial)

    assert {:ok, unlock} =
             FOP.directive(initial, :initiate_ad_with_unlock, nil, request_id: :unlock)

    assert unlock.event == :e25
    assert unlock.state.state == :initializing_with_bc
    refute unlock.state.bc_out_ready
    assert unlock.timer_action == :start
    assert unlock.transmit_bc_commands == [:unlock]

    assert {:ok, set_vr} =
             FOP.directive(initial, :initiate_ad_with_set_vr, 231, request_id: :set_vr)

    assert set_vr.event == :e27
    assert set_vr.state.vs == 231
    assert set_vr.state.nnr == 231
    assert set_vr.transmit_bc_commands == [{:set_vr, 231}]
  end

  test "E26 and E28 reject BC initialization when the lower interface is busy" do
    state = COP1FOPFixtures.state(state: :initial, bc_out_ready: false)

    assert {:ok, unlock} = FOP.directive(state, :initiate_ad_with_unlock)
    assert unlock.event == :e26
    assert directive_statuses(unlock) == [:reject]

    assert {:ok, set_vr} = FOP.directive(state, :initiate_ad_with_set_vr, 9)
    assert set_vr.event == :e28
    assert directive_statuses(set_vr) == [:reject]
  end

  test "E29 terminates active service with Alert[term] and confirms the directive" do
    state = COP1FOPFixtures.sent_state(:active, [0])

    assert {:ok, transition} = FOP.directive(state, :terminate_ad, nil, request_id: :stop)

    assert transition.event == :e29
    assert transition.state.state == :initial
    assert transition.state.sent_queue == []
    assert transition.alerts == [:term]
    assert transition.timer_action == :cancel
    assert directive_statuses(transition) == [:accept, :positive_confirm]
    assert {:fdu, :negative_confirm, {:request, 0}} in transition.notifications

    assert {:ok, already_initial} = FOP.directive(%{state | state: :initial}, :terminate_ad)
    assert already_initial.alerts == []
    assert directive_statuses(already_initial) == [:accept, :positive_confirm]
  end

  test "E31 through E34 resume each suspended state and E30 rejects when not suspended" do
    expectations = [
      {1, :e31, :active},
      {2, :e32, :retransmit_without_wait},
      {3, :e33, :retransmit_with_wait},
      {4, :e34, :initializing_without_bc}
    ]

    for {suspend_state, event, expected_state} <- expectations do
      state = COP1FOPFixtures.state(state: :initial, suspend_state: suspend_state)
      assert {:ok, transition} = FOP.directive(state, :resume_ad)
      assert transition.event == event
      assert transition.state.state == expected_state
      assert transition.state.suspend_state == 0
      assert transition.timer_action == :start
      assert directive_statuses(transition) == [:accept, :positive_confirm]
    end

    assert {:ok, rejected} =
             FOP.directive(COP1FOPFixtures.state(state: :initial), :resume_ad)

    assert rejected.event == :e30
    assert directive_statuses(rejected) == [:reject]
  end

  test "E35 constrains Set V(S) to unsuspended initial state" do
    initial = COP1FOPFixtures.state(state: :initial)
    assert {:ok, accepted} = FOP.directive(initial, :set_vs, 255)
    assert accepted.event == :e35
    assert accepted.state.vs == 255
    assert accepted.state.nnr == 255
    assert directive_statuses(accepted) == [:accept, :positive_confirm]

    assert {:ok, active_reject} =
             FOP.directive(COP1FOPFixtures.state(state: :active), :set_vs, 4)

    assert directive_statuses(active_reject) == [:reject]

    assert {:ok, suspended_reject} =
             FOP.directive(%{initial | suspend_state: 1}, :set_vs, 4)

    assert directive_statuses(suspended_reject) == [:reject]
  end

  test "E36 through E39 apply setup directives in every state" do
    for state_name <- [
          :active,
          :retransmit_without_wait,
          :retransmit_with_wait,
          :initializing_without_bc,
          :initializing_with_bc,
          :initial
        ] do
      state = COP1FOPFixtures.state(state: state_name)

      assert {:ok, width} = FOP.directive(state, :set_fop_sliding_window_width, 12)
      assert width.event == :e36
      assert width.state.sliding_window_width == 12

      assert {:ok, t1} = FOP.directive(state, :set_t1_initial, 900)
      assert t1.event == :e37
      assert t1.state.t1_initial_ms == 900

      assert {:ok, limit} = FOP.directive(state, :set_transmission_limit, 7)
      assert limit.event == :e38
      assert limit.state.transmission_limit == 7

      assert {:ok, timeout_type} = FOP.directive(state, :set_timeout_type, 1)
      assert timeout_type.event == :e39
      assert timeout_type.state.timeout_type == 1

      assert directive_statuses(width) == [:accept, :positive_confirm]
    end
  end

  test "E40 rejects unknown and invalid directives without changing state" do
    state = COP1FOPFixtures.state()

    for {directive, qualifier} <- [
          {:unknown, nil},
          {:set_vs, 256},
          {:set_fop_sliding_window_width, 0},
          {:set_t1_initial, 0},
          {:set_transmission_limit, 0},
          {:set_timeout_type, 2}
        ] do
      assert {:ok, transition} = FOP.directive(state, directive, qualifier)
      assert transition.event == :e40
      assert transition.state == state
      assert directive_statuses(transition) == [:reject]
    end
  end

  defp directive_statuses(transition) do
    for {:directive, status, _directive} <- transition.notifications, do: status
  end
end
