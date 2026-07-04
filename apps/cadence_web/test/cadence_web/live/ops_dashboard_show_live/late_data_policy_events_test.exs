defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyEvents
  alias Phoenix.LiveView.Socket

  test "record_decision delegates params and opts" do
    opts = [
      record_late_data_policy_event: fn socket, params, opts ->
        assign(socket, :late_data_policy_event, {params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket =
      LateDataPolicyEvents.record_decision(
        socket(),
        %{"late_data_policy" => %{"decision" => "accept"}},
        opts
      )

    assert socket.assigns.late_data_policy_event ==
             {%{"late_data_policy" => %{"decision" => "accept"}}, :ok}
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end
end
