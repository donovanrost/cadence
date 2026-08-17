defmodule CadenceWeb.OpsDashboardShowLive.LifecycleEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.LifecycleEvents
  alias Phoenix.LiveView.Socket

  test "save_runtime_defaults flashes on success" do
    assert {:ok, socket} =
             LifecycleEvents.save_runtime_defaults(socket(),
               dashboard_list_path: &dashboard_list_path/1,
               save_runtime_defaults: fn socket, opts ->
                 assert opts[:dashboard_list_path].(socket) == "/dashboards"
                 {:ok, socket}
               end,
               put_flash: fn socket, kind, message ->
                 assign(socket, :flash_call, {kind, message})
               end
             )

    assert socket.assigns.flash_call == {:info, "Dashboard runtime defaults saved."}
  end

  test "save_runtime_defaults returns errors without success flash" do
    assert {:error, socket} =
             LifecycleEvents.save_runtime_defaults(socket(),
               dashboard_list_path: &dashboard_list_path/1,
               save_runtime_defaults: fn socket, _opts ->
                 {:error, assign(socket, :error_seen?, true)}
               end,
               put_flash: fn _socket, _kind, _message -> flunk("should not flash") end
             )

    assert socket.assigns.error_seen? == true
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end

  defp dashboard_list_path(_socket), do: "/dashboards"
end
