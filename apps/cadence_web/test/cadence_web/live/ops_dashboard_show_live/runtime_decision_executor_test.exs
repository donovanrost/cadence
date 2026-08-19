defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDecisionExecutorTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDecisionExecutor

  test "cancels a superseded resolve before starting its replacement" do
    test_pid = self()

    decisions = [
      %{action: :cancel_obsolete, superseded_resolve_id: 4},
      %{action: :start_resolve, resolve_mode: :context_change, resolve_id: 5},
      %{action: :accept_result, resolve_id: 3}
    ]

    socket =
      RuntimeDecisionExecutor.apply(%{effects: []}, decisions, [reason: :runtime_context_changed],
        cancel_resolve: fn socket, resolve_id ->
          send(test_pid, {:cancel, resolve_id})
          update_in(socket.effects, &(&1 ++ [{:cancel, resolve_id}]))
        end,
        start_resolve: fn socket, mode, resolve_id, opts ->
          send(test_pid, {:start, mode, resolve_id, opts})
          update_in(socket.effects, &(&1 ++ [{:start, mode, resolve_id}]))
        end
      )

    assert socket.effects == [
             {:cancel, 4},
             {:start, :context_change, 5}
           ]

    assert_receive {:cancel, 4}
    assert_receive {:start, :context_change, 5, [reason: :runtime_context_changed]}
  end
end
