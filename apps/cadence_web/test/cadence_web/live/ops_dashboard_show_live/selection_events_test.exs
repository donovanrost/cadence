defmodule CadenceWeb.OpsDashboardShowLive.SelectionEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.SelectionEvents
  alias Phoenix.LiveView.Socket

  test "open_evidence delegates params and opts" do
    opts = [
      open_evidence_event: fn socket, params, opts ->
        assign(socket, :selection_event, {:evidence, params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = SelectionEvents.open_evidence(socket(), %{"selected_target" => "frame"}, opts)

    assert socket.assigns.selection_event == {:evidence, %{"selected_target" => "frame"}, :ok}
  end

  test "open_data_link delegates link id, params, and opts" do
    opts = [
      open_data_link_event: fn socket, link_id, params, opts ->
        assign(
          socket,
          :selection_event,
          {:data_link, link_id, params, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket =
      SelectionEvents.open_data_link(socket(), "link-1", %{"selected_target" => "sample"}, opts)

    assert socket.assigns.selection_event ==
             {:data_link, "link-1", %{"selected_target" => "sample"}, :ok}
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end
end
