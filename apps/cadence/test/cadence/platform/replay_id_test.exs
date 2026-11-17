defmodule Cadence.Platform.ReplayIdTest do
  use ExUnit.Case, async: true

  alias Cadence.Platform.ReplayId

  @key %{receipt: ~U[2026-11-17 01:02:03.456789Z], ordinal: 7, offset: 1_048_576, index: 3}

  test "the format: kind, then four fixed-width base32hex fields, 30 bytes" do
    id = ReplayId.id(:alarm_episode, @key)

    assert byte_size(id) == 30
    assert <<"aep_", body::binary-size(26)>> = id
    assert body =~ ~r/\A[0-9a-v]{26}\z/
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
    assert_raise ArgumentError, ~r/index 1024/, fn ->
      ReplayId.id(:alarm_event, %{@key | index: 1024})
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
          "xyz_" <> String.duplicate("0", 26),
          "aep_" <> String.duplicate("z", 26)
        ] do
      assert ReplayId.parse(id) == :error
    end
  end
end
