defmodule Cadence.Runtime.ProfileAcceptorTest do
  @moduledoc """
  DECISIONS #87 (A): one listener per listen-mode provider profile. Overlapping contacts on one
  profile each get their own peer, identified by the first frame's SCID (routing, not
  attestation); anything unidentified is refused.
  """
  use ExUnit.Case, async: false

  alias Cadence.Runtime.{ProcessNamespace, ProfileAcceptor}

  @frame_size 14

  setup do
    %{
      namespace: ProcessNamespace.default(),
      mission: "mission-acceptor-#{System.unique_integer([:positive])}",
      profile: "profile-acceptor-#{System.unique_integer([:positive])}"
    }
  end

  test "two overlapping contacts on one profile each get their own peer, by SCID", c do
    {a, port} = register!(c, "contact-a", 1)
    {b, ^port} = register!(c, "contact-b", 2)

    sent_at = DateTime.utc_now()
    peer_b = connect!(port, frame(2))
    peer_a = connect!(port, frame(1))

    assert_receive {^a, {:peer_accepted, socket_a, prefix_a, _peer, read_a}}, 2_000
    assert_receive {^b, {:peer_accepted, socket_b, prefix_b, _peer, _read_b}}, 2_000
    assert <<_::2, 1::10, _::bitstring>> = prefix_a
    # The first frame's receipt time is when the acceptor read it (api-ops review).
    assert %DateTime{} = read_a
    assert DateTime.compare(read_a, sent_at) != :lt
    assert DateTime.compare(read_a, DateTime.utc_now()) != :gt
    assert <<_::2, 2::10, _::bitstring>> = prefix_b

    # Each adapter now owns its peer's socket and reads what follows.
    :ok = :gen_tcp.send(peer_a, "after-a")
    assert {:ok, "after-a"} = recv_as(a, socket_a)
    :ok = :gen_tcp.send(peer_b, "after-b")
    assert {:ok, "after-b"} = recv_as(b, socket_b)
  end

  test "a contained pass comes and goes; the other contact's session is untouched", c do
    {a, port} = register!(c, "contact-a", 1)
    peer_a = connect!(port, frame(1))
    assert_receive {^a, {:peer_accepted, socket_a, _prefix, _peer, _read_at}}, 2_000

    {b, ^port} = register!(c, "contact-b", 2)
    _peer_b = connect!(port, frame(2))
    assert_receive {^b, {:peer_accepted, _socket_b, _prefix, _peer, _read_at}}, 2_000
    stop_adapter(b)

    :ok = :gen_tcp.send(peer_a, "still-here")
    assert {:ok, "still-here"} = recv_as(a, socket_a)
  end

  test "a frame for no registered spacecraft is refused, and every adapter hears of it", c do
    {a, port} = register!(c, "contact-a", 1)
    peer = connect!(port, frame(99))

    assert_receive {^a, {:peer_refused, _peer, {:unregistered_scid, 99}}}, 2_000
    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
    refute_received {^a, {:peer_accepted, _, _, _, _}}
  end

  test "the single-registration fallback, opt-in, refuses once two are registered", c do
    listen = %{port: 0, host: "127.0.0.1", fallback_single_registration?: true}
    {a, port} = register!(c, "contact-a", nil, listen: listen, frame_size: nil)
    _peer = connect!(port, "")
    assert_receive {^a, {:peer_accepted, _socket, <<>>, _peer, _read_at}}, 2_000

    {b, ^port} = register!(c, "contact-b", nil, listen: listen, frame_size: nil)
    _peer2 = connect!(port, "")
    assert_receive {^a, {:peer_refused, _, :unidentified}}, 2_000
    assert_receive {^b, {:peer_refused, _, :unidentified}}, 2_000
  end

  test "an IPv4-mapped expected address matches its IPv4 peer", c do
    {a, port} = register!(c, "contact-a", 1, expected_peer_address: "::ffff:127.0.0.1")
    _peer = connect!(port, frame(1))
    assert_receive {^a, {:peer_accepted, _socket, _prefix, "127.0.0.1", _read_at}}, 2_000
  end

  test "a peer from an address the profile doesn't expect is refused", c do
    {a, port} = register!(c, "contact-a", 1, expected_peer_address: "10.9.9.9")
    _peer = connect!(port, frame(1))
    assert_receive {^a, {:peer_refused, "127.0.0.1", {:unregistered_scid, 1}}}, 2_000
  end

  test "the listener closes after the last contact leaves (linger) and frees its port", c do
    listen = %{port: 0, host: "127.0.0.1", linger_ms: 50}
    {a, port} = register!(c, "contact-a", 1, listen: listen)
    stop_adapter(a)

    assert eventually(fn ->
             match?({:error, _}, :gen_tcp.connect(~c"127.0.0.1", port, [], 100))
           end)
  end

  # A stand-in adapter: registers, then forwards what the acceptor sends it to the test.
  defp register!(c, contact, scid, opts \\ []) do
    test = self()
    listen = Keyword.get(opts, :listen, %{port: 0, host: "127.0.0.1"})

    adapter =
      spawn(fn ->
        receive do
          {:register, from} ->
            registration = %{
              adapter: self(),
              realized_contact_id: contact,
              path_id: "downlink",
              scid: scid,
              expected_peer_address: Keyword.get(opts, :expected_peer_address),
              frame_size: Keyword.get(opts, :frame_size, @frame_size)
            }

            send(
              from,
              {:registered,
               ProfileAcceptor.register(c.namespace, c.mission, c.profile, listen, registration)}
            )

            forward(test)
        end
      end)

    send(adapter, {:register, self()})
    assert_receive {:registered, {:ok, port}}, 2_000
    {adapter, port}
  end

  defp forward(test) do
    receive do
      {:recv, socket, from} ->
        send(from, {:received, :gen_tcp.recv(socket, 0, 2_000)})
        forward(test)

      :stop ->
        :ok

      message ->
        send(test, {self(), message})
        forward(test)
    end
  end

  # The adapter owns the socket, so it reads on the test's behalf.
  defp recv_as(adapter, socket) do
    send(adapter, {:recv, socket, self()})
    assert_receive {:received, result}, 2_000
    result
  end

  defp stop_adapter(adapter) do
    ref = Process.monitor(adapter)
    send(adapter, :stop)
    assert_receive {:DOWN, ^ref, :process, ^adapter, _}, 2_000
  end

  defp connect!(port, first) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    if first != "", do: :ok = :gen_tcp.send(socket, first)
    socket
  end

  # A TM transfer frame header with `scid`, padded to the frame size.
  defp frame(scid), do: <<0::2, scid::10, 0::3, 0::1, 0::16, 0::64>> <> <<0::16>>

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end
end
