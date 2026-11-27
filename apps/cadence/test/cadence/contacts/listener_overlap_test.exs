defmodule Cadence.Contacts.ListenerOverlapTest do
  @moduledoc """
  #361 (U58 (b)): which listeners contend, and who loses how many seconds. The runtime's own rule:
  own-socket listen bindings on colliding endpoints, the later start losing until the earlier pass
  ends.
  """
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ListenerOverlap

  @t0 ~U[2026-11-20 00:00:00Z]

  defp at(s), do: DateTime.add(@t0, s, :second)

  defp path(direction, configuration),
    do: %{direction: direction, provider_bindings: [%{configuration: configuration}]}

  defp listen(port, extra \\ %{}),
    do:
      Map.merge(
        %{
          "mode" => "listen",
          "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
          "host" => "0.0.0.0",
          "port" => port
        },
        extra
      )

  defp pass(id, from, to, paths),
    do: %{
      id: id,
      starts_at: at(from),
      ends_at: to && at(to),
      listeners: ListenerOverlap.listeners(paths)
    }

  describe "listeners/1" do
    test "an own listen binding counts; a shared downlink, a dial-out and no fixed port don't" do
      assert [%{port: 42_105, direction: :downlink}] =
               ListenerOverlap.listeners([path(:downlink, listen(42_105))])

      assert [] =
               ListenerOverlap.listeners([
                 path(:downlink, listen(42_105, %{"listener" => "shared"}))
               ])

      # Uplink keeps its own listener even when the profile says shared (#87).
      assert [%{direction: :uplink}] =
               ListenerOverlap.listeners([
                 path(:uplink, listen(42_105, %{"listener" => "shared"}))
               ])

      assert [] =
               ListenerOverlap.listeners([
                 path(:downlink, %{"mode" => "connect", "host" => "x", "port" => 1})
               ])

      # Port 0 asks the OS for a free port: nothing fixed to collide on (domain).
      assert [] = ListenerOverlap.listeners([path(:downlink, listen(0))])
      assert [] = ListenerOverlap.listeners([path(:downlink, Map.delete(listen(1), "port"))])
    end
  end

  describe "overlaps/1" do
    test "no overlap: neither is flagged" do
      a = pass("a", 0, 600, [path(:downlink, listen(42_105))])
      b = pass("b", 600, 1200, [path(:downlink, listen(42_105))])
      assert ListenerOverlap.overlaps([a, b]) == %{"a" => nil, "b" => nil}
    end

    test "partial: the later start loses until the earlier pass ends" do
      earlier = pass("006", 0, 600, [path(:downlink, listen(42_105))])
      later = pass("001", 574, 1200, [path(:downlink, listen(42_105))])
      result = ListenerOverlap.overlaps([earlier, later])

      assert %{with: "006", seconds: 26, loses: "this", direction: :downlink, count: 1} =
               result["001"]

      assert %{with: "001", seconds: 26, loses: "other"} = result["006"]
      assert result["001"].listener == %{host: "0.0.0.0", port: 42_105}
    end

    test "full: a later pass inside the earlier one loses all of itself" do
      earlier = pass("a", 0, 1200, [path(:downlink, listen(42_105))])
      later = pass("b", 100, 400, [path(:downlink, listen(42_105))])
      assert %{seconds: 300, loses: "this"} = ListenerOverlap.overlaps([earlier, later])["b"]
    end

    test "an equal start is a race: both read 'either'" do
      a = pass("a", 0, 600, [path(:downlink, listen(42_105))])
      b = pass("b", 0, 300, [path(:downlink, listen(42_105))])
      result = ListenerOverlap.overlaps([a, b])
      assert %{loses: "either", seconds: 300} = result["a"]
      assert %{loses: "either", seconds: 300} = result["b"]
    end

    test "a shared downlink listener never contends; uplink on the same endpoint does" do
      shared = [path(:downlink, listen(42_105, %{"listener" => "shared"}))]

      assert ListenerOverlap.overlaps([pass("a", 0, 600, shared), pass("b", 100, 700, shared)]) ==
               %{"a" => nil, "b" => nil}

      up = [path(:uplink, listen(42_105, %{"listener" => "shared"}))]

      assert %{direction: :uplink, loses: "this"} =
               ListenerOverlap.overlaps([pass("a", 0, 600, up), pass("b", 100, 700, up)])["b"]
    end

    test "endpoints collide by the claim rule: same port and host, or a wildcard; a different port never" do
      wild = [path(:downlink, listen(42_105))]
      host = [path(:downlink, listen(42_105, %{"host" => "10.0.0.5"}))]
      other_host = [path(:downlink, listen(42_105, %{"host" => "10.0.0.6"}))]
      other_port = [path(:downlink, listen(42_106))]

      assert ListenerOverlap.overlaps([pass("a", 0, 600, wild), pass("b", 100, 700, host)])["b"]

      refute ListenerOverlap.overlaps([pass("a", 0, 600, host), pass("b", 100, 700, other_host)])[
               "b"
             ]

      refute ListenerOverlap.overlaps([pass("a", 0, 600, wild), pass("b", 100, 700, other_port)])[
               "b"
             ]
    end

    test "a pass that both loses and delays another reads its OWN loss (domain, fe-ops)" do
      l = [path(:downlink, listen(42_105))]
      a = pass("a", 0, 600, l)
      # b loses 10 s to a, and makes c lose 40 s.
      b = pass("b", 590, 1000, l)
      c = pass("c", 960, 1500, l)
      result = ListenerOverlap.overlaps([a, b, c])

      assert %{with: "a", loses: "this", seconds: 10, count: 2} = result["b"]
      assert %{with: "b", loses: "this", seconds: 40} = result["c"]
      # a loses nothing: it reads the delay it causes.
      assert %{with: "b", loses: "other", seconds: 10} = result["a"]
    end

    test "neither pass ends: flagged, with seconds null (unmeasurable, not absent)" do
      l = [path(:downlink, listen(42_105))]
      result = ListenerOverlap.overlaps([pass("a", 0, nil, l), pass("b", 100, nil, l)])
      assert %{loses: "this", seconds: nil} = result["b"]
      assert %{loses: "other", seconds: nil} = result["a"]
    end

    test "with several, the costliest is named and count says how many" do
      l = [path(:downlink, listen(42_105))]

      result =
        ListenerOverlap.overlaps([
          pass("x", 0, 200, l),
          pass("y", 0, 500, l),
          pass("z", 100, 1000, l)
        ])

      assert %{with: "y", seconds: 400, count: 2} = result["z"]
    end
  end
end
