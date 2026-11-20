defmodule Cadence.Platform.ReplayIdTest do
  use ExUnit.Case, async: true

  alias Cadence.Platform.ReplayId

  @key %{receipt: ~U[2026-11-17 01:02:03.456789Z], ordinal: 7, offset: 1_048_576, index: 3}

  test "the format: kind, then four fixed-width base32hex fields, 31 bytes" do
    id = ReplayId.id(:alarm_episode, @key)

    assert byte_size(id) == 31
    assert <<"aep_", body::binary-size(27)>> = id
    assert body =~ ~r/\A[0-9a-v]{27}\z/
    assert String.starts_with?(ReplayId.id(:alarm_event, @key), "aev_")
    assert String.starts_with?(ReplayId.id(:managed_action_request, @key), "mar_")
  end

  test "the same key is the same id; the parts read back" do
    assert ReplayId.id(:alarm_event, @key) == ReplayId.id(:alarm_event, @key)

    assert {:ok, %{kind: :alarm_event, ordinal: 7, offset: 1_048_576, index: 3, receipt_us: us}} =
             ReplayId.parse(ReplayId.id(:alarm_event, @key))

    assert us == DateTime.to_unix(@key.receipt, :microsecond)
  end

  test "ids sort by time first, then stream, offset and index, as plain strings" do
    later = %{@key | receipt: DateTime.add(@key.receipt, 1, :microsecond), ordinal: 0, offset: 0}

    keys = [
      later,
      %{@key | index: 4},
      @key,
      %{@key | offset: @key.offset + 1, index: 0},
      %{@key | ordinal: 8, offset: 0, index: 0}
    ]

    ids = Enum.map(keys, &ReplayId.id(:alarm_event, &1))

    assert Enum.sort(ids) ==
             Enum.map(
               [
                 @key,
                 %{@key | index: 4},
                 %{@key | offset: @key.offset + 1, index: 0},
                 %{@key | ordinal: 8, offset: 0, index: 0},
                 later
               ],
               &ReplayId.id(:alarm_event, &1)
             )
  end

  test "a field that doesn't fit is refused, never truncated" do
    assert_raise ArgumentError, ~r/index 32768/, fn ->
      ReplayId.id(:alarm_event, %{@key | index: 32_768})
    end

    assert_raise ArgumentError, ~r/ordinal/, fn ->
      ReplayId.id(:alarm_event, %{@key | ordinal: -1})
    end

    assert_raise ArgumentError, ~r/receipt/, fn ->
      ReplayId.id(:alarm_event, %{@key | receipt: ~U[2019-12-31 23:59:59Z]})
    end
  end

  test "other ids don't parse" do
    for id <- [
          "alarm_episode_abc123_1",
          "xyz_" <> String.duplicate("0", 27),
          "aep_" <> String.duplicate("z", 27)
        ] do
      assert ReplayId.parse(id) == :error
    end
  end

  describe "number/3" do
    @us DateTime.to_unix(~U[2026-11-17 01:00:00Z], :microsecond)

    test "numbers per (stream, offset) in order; sources without an ordinal or nil get nil" do
      items = [
        {:a, ["j1", 14, @us]},
        {:b, ["j1", 14, @us]},
        {:c, ["j1", 28, @us]},
        {:d, nil},
        {:e, ["j2", 14, @us]},
        {:f, ["unknown", 14, @us]},
        {:g, ["j1", 14, @us]}
      ]

      numbered = ReplayId.number(items, &elem(&1, 1), %{"j1" => 3, "j2" => 4})

      assert Enum.map(numbered, fn
               {{name, _}, nil} -> {name, nil}
               {{name, _}, key} -> {name, key.ordinal, key.offset, key.index}
             end) == [
               {:a, 3, 14, 0},
               {:b, 3, 14, 1},
               {:c, 3, 28, 0},
               {:d, nil},
               {:e, 4, 14, 0},
               {:f, nil},
               {:g, 3, 14, 2}
             ]
    end

    test "the same items numbered again give the same keys" do
      items = for n <- 1..5, do: {n, ["j1", div(n, 2) * 14, @us]}
      ordinals = %{"j1" => 9}

      assert ReplayId.number(items, &elem(&1, 1), ordinals) ==
               ReplayId.number(items, &elem(&1, 1), ordinals)
    end

    test "stream_keys/1 lists each stream once and skips nils" do
      assert ReplayId.stream_keys([["a", 0, 1], nil, ["b", 0, 1], ["a", 14, 1]]) == ["a", "b"]
    end
  end

  test "past 32,768 effects for one input, the rest get nil (Ids.new) and are counted" do
    us = DateTime.to_unix(~U[2026-11-17 01:00:00Z], :microsecond)
    ref = make_ref()
    test_pid = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:cadence, :replay_id, :index_overflow],
      fn _event, %{count: n}, _meta, _config -> send(test_pid, {:overflow, ref, n}) end,
      nil
    )

    items = for n <- 1..32_770, do: {n, ["j1", 14, us]}

    numbered =
      ExUnit.CaptureLog.capture_log(fn ->
        send(self(), {:numbered, ReplayId.number(items, &elem(&1, 1), %{"j1" => 1})})
      end)

    assert numbered =~ "MM_REPLAY_ID_INDEX_OVERFLOW"
    assert_received {:numbered, keys}
    assert Enum.count(keys, fn {_item, key} -> is_nil(key) end) == 2
    assert_received {:overflow, ^ref, 1}
    assert_received {:overflow, ^ref, 1}
    :telemetry.detach({__MODULE__, ref})
  end
end
