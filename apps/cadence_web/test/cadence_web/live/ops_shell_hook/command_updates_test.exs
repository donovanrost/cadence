defmodule CadenceWeb.OpsShellHook.CommandUpdatesTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Platform.ScopedReadUpdates, as: ReadUpdates
  alias Cadence.Reads.OperationalContext
  alias CadenceWeb.OpsShellHook.{CommandUpdates, ContextDeps}
  alias Phoenix.Component
  alias Phoenix.LiveView.Socket

  test "committed notices coalesce into one command-only refresh and preserve followed context" do
    socket = CommandUpdates.subscribe(socket())
    ReadUpdates.publish(:commanding_changed, "org-one", "mission-one")
    assert_receive {:commanding_changed, "org-one", "mission-one"}

    socket = CommandUpdates.changed(socket, "org-one", "mission-one")
    updates = socket.assigns.ops_command_context_updates

    for _ <- 1..5 do
      assert CommandUpdates.changed(socket, "org-one", "mission-one") == socket
    end

    refute_received {:command_summary_read, _, _}
    assert_receive {:ops_command_context_flush, token}, 1_000
    assert token == updates.token
    socket = CommandUpdates.flush(socket, token)

    assert_received {:command_summary_read, "org-one", "mission-one"}
    assert socket.assigns.ops_command_context_updates.pending == nil
    command = Enum.find(socket.assigns.ops_context.modules, &(&1.key == "commands"))
    assert command.count == 2
    assert command.data.queued_count == 2
    assert command.data.followed_command.command_request_id == "request-one"
    assert command.data.followed_command.status == :queued
    assert socket.assigns.ops_context.pinned_focus == %{kind: :command, id: "request-one"}
    assert Enum.find(socket.assigns.ops_context.modules, &(&1.key == "fleet_health")).data == nil

    assert CommandUpdates.flush(socket, token) == socket
    refute_received {:command_summary_read, _, _}
    CommandUpdates.stop(socket)
  end

  test "mission changes replace the subscription and ignore notices and timers from the previous scope" do
    first =
      socket() |> CommandUpdates.subscribe() |> CommandUpdates.changed("org-one", "mission-one")

    old = first.assigns.ops_command_context_updates

    second =
      first
      |> Component.assign(:current_mission, %{mission_id: "mission-two"})
      |> CommandUpdates.subscribe()

    assert Process.read_timer(old.pending) == false
    assert second.assigns.ops_command_context_updates.token != old.token
    assert CommandUpdates.flush(second, old.token) == second
    assert CommandUpdates.changed(second, "org-one", "mission-one") == second
    assert CommandUpdates.changed(second, "another-org", "mission-two") == second

    ReadUpdates.publish(:commanding_changed, "org-one", "mission-one")
    ReadUpdates.publish(:commanding_changed, "org-one", "mission-two")
    assert_receive {:commanding_changed, "org-one", "mission-two"}
    refute_received {:commanding_changed, "org-one", "mission-one"}
    refute_received {:command_summary_read, _, _}

    second = CommandUpdates.changed(second, "org-one", "mission-two")
    updates = second.assigns.ops_command_context_updates
    outside = second |> CommandUpdates.stop() |> Component.assign(:ops_context_active?, false)
    assert Process.read_timer(updates.pending) == false
    assert outside.assigns.ops_command_context_updates == nil
    assert CommandUpdates.flush(outside, updates.token) == outside
    assert CommandUpdates.changed(outside, "org-one", "mission-two") == outside
    ReadUpdates.publish(:commanding_changed, "org-one", "mission-two")
    refute_receive {:commanding_changed, _, _}
  end

  test "entering another Ops page retains a single subscription and disconnected renders do not subscribe" do
    disconnected = socket()

    assert CommandUpdates.subscribe(%{disconnected | transport_pid: nil}) ==
             %{disconnected | transport_pid: nil}

    socket = CommandUpdates.subscribe(disconnected)
    assert CommandUpdates.subscribe(socket) == socket
    ReadUpdates.publish(:commanding_changed, "org-one", "mission-one")
    assert_receive {:commanding_changed, "org-one", "mission-one"}
    refute_receive {:commanding_changed, _, _}
    CommandUpdates.stop(socket)
  end

  defp socket do
    deps =
      ContextDeps.new(
        mission_health_summary: fn _, _, _ ->
          flunk("A command notice must not reload fleet health")
        end,
        alarm_summary: fn _, _, _ -> flunk("A command notice must not reload alarms") end,
        command_summary: fn org, mission, [] ->
          send(self(), {:command_summary_read, org, mission})
          summary(2)
        end
      )

    context =
      "mission-one"
      |> OperationalContext.new(nil)
      |> OperationalContext.put_command_summary(summary(0))
      |> OperationalContext.pin_command_focus("request-one")

    %Socket{
      transport_pid: self(),
      assigns: %{
        __changed__: %{},
        current_scope: %{organization_id: "org-one"},
        current_mission: %{mission_id: "mission-one"},
        ops_context_active?: true,
        ops_context_deps: deps,
        ops_context: context
      }
    }
  end

  defp summary(queued) do
    %{
      active_count: queued,
      queued_count: queued,
      status: :nominal,
      freshness: :current,
      rows: [%{command_request_id: "request-one", status: :queued}]
    }
  end
end
