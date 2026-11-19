defmodule Cadence.Runtime.MissionCoordinator.PartitionBackoffTest do
  @moduledoc "A partition that fails to initialize isn't restarted on every frame."
  use ExUnit.Case, async: true

  alias Cadence.Runtime.MissionCoordinator.PartitionBackoff

  test "after a failure the partition waits, doubling up to 30 s" do
    assert :ok = PartitionBackoff.check(%{}, :p, 0)

    {backoff, 250} = PartitionBackoff.failed(%{}, :p, :boom, 0)

    assert {:error, {:partition_initialization_backoff, :boom, 150}} =
             PartitionBackoff.check(backoff, :p, 100)

    assert :ok = PartitionBackoff.check(backoff, :p, 250)
    assert :ok = PartitionBackoff.check(backoff, :other, 100)

    delays =
      Enum.reduce(1..9, {backoff, 250, [250]}, fn _, {b, at, acc} ->
        {b, delay} = PartitionBackoff.failed(b, :p, :boom, at)
        {b, at + delay, acc ++ [delay]}
      end)
      |> elem(2)

    assert delays == [250, 500, 1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000, 30_000]
  end

  test "a failure after a quiet minute starts over" do
    {backoff, 250} = PartitionBackoff.failed(%{}, :p, :boom, 0)
    {backoff, 500} = PartitionBackoff.failed(backoff, :p, :boom, 250)
    assert {_backoff, 250} = PartitionBackoff.failed(backoff, :p, :boom, 250 + 500 + 60_000)
  end
end
