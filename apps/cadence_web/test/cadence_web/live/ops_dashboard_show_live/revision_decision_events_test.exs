defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionEvents
  alias Phoenix.LiveView.Socket

  test "apply_decision delegates params and opts" do
    opts = [
      apply_revision_decision_event: fn socket, params, opts ->
        assign(socket, :revision_decision_event, {params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket =
      RevisionDecisionEvents.apply_decision(
        socket(),
        %{"revision_decision" => %{"decision" => "mark_conflict"}},
        opts
      )

    assert socket.assigns.revision_decision_event ==
             {%{"revision_decision" => %{"decision" => "mark_conflict"}}, :ok}
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end
end
