defmodule CadenceSimulator.Provider.UplinkSessionsTest do
  @moduledoc "DECISIONS #67: an uplink peer can't outlive the process that started it."
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider.UplinkSessions

  setup do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: 0])
    {:ok, {_address, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    contact = %{
      "id" => "contact-67-#{System.unique_integer([:positive])}",
      "uplink" => %{"status" => "included"},
      "uplink_delivery_profile_snapshot" => %{
        "target" => %{"host" => "127.0.0.1", "port" => port},
        "framing" => %{"frame_bytes" => 16}
      }
    }

    %{contact: contact}
  end

  test "a peer dies with the orchestrator that started it", c do
    test = self()

    owner =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        sessions = UplinkSessions.ensure(%{}, c.contact, nil)
        send(test, {:peer, sessions[c.contact["id"]].pid})
        Process.sleep(:infinity)
      end)

    assert_receive {:peer, peer}, 2_000
    reference = Process.monitor(peer)

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^reference, :process, ^peer, :killed}, 2_000
  end

  test "a peer's own exit doesn't take the orchestrator down", c do
    test = self()

    owner =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        sessions = UplinkSessions.ensure(%{}, c.contact, nil)
        send(test, {:peer, sessions[c.contact["id"]].pid})

        receive do
          {:EXIT, _peer, reason} -> send(test, {:owner_saw_exit, reason})
        end

        Process.sleep(:infinity)
      end)

    assert_receive {:peer, peer}, 2_000
    Process.exit(peer, :kill)
    assert_receive {:owner_saw_exit, :killed}, 2_000
    assert Process.alive?(owner)
    Process.exit(owner, :kill)
  end
end
