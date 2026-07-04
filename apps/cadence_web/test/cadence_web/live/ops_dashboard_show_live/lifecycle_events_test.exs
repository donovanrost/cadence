defmodule CadenceWeb.OpsDashboardShowLive.LifecycleEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.LifecycleEvents
  alias Phoenix.LiveView.Socket

  test "archive_dashboard delegates with dashboard list navigation opts" do
    socket =
      socket()
      |> LifecycleEvents.archive_dashboard(
        dashboard_list_path: &dashboard_list_path/1,
        archive_document: fn socket, opts ->
          assign(socket, :lifecycle_call, {:archive, opts[:dashboard_list_path].(socket)})
        end
      )

    assert socket.assigns.lifecycle_call == {:archive, "/dashboards"}
  end

  test "publish_dashboard delegates with dashboard list navigation opts" do
    socket =
      socket()
      |> LifecycleEvents.publish_dashboard(
        dashboard_list_path: &dashboard_list_path/1,
        publish_latest_draft: fn socket, opts ->
          assign(socket, :lifecycle_call, {:publish_latest, opts[:dashboard_list_path].(socket)})
        end
      )

    assert socket.assigns.lifecycle_call == {:publish_latest, "/dashboards"}
  end

  test "publish_dashboard_version delegates version and navigation opts" do
    socket =
      socket()
      |> LifecycleEvents.publish_dashboard_version("3",
        dashboard_list_path: &dashboard_list_path/1,
        publish_version: fn socket, version, opts ->
          assign(
            socket,
            :lifecycle_call,
            {:publish_version, version, opts[:dashboard_list_path].(socket)}
          )
        end
      )

    assert socket.assigns.lifecycle_call == {:publish_version, "3", "/dashboards"}
  end

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

  test "restore_version_as_draft delegates version and navigation opts" do
    socket =
      socket()
      |> LifecycleEvents.restore_version_as_draft("2",
        dashboard_list_path: &dashboard_list_path/1,
        restore_version_as_draft: fn socket, version, opts ->
          assign(
            socket,
            :lifecycle_call,
            {:restore, version, opts[:dashboard_list_path].(socket)}
          )
        end
      )

    assert socket.assigns.lifecycle_call == {:restore, "2", "/dashboards"}
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end

  defp dashboard_list_path(_socket), do: "/dashboards"
end
