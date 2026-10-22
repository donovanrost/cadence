defmodule Cadence.Platform.DurableFileTest do
  use ExUnit.Case, async: true

  alias Cadence.Platform.DurableFile

  @tag :tmp_dir
  test "concurrent publishers cannot replace an immutable object", %{tmp_dir: tmp_dir} do
    path = Path.join([tmp_dir, "mission", "date", "segment.bin"])
    payloads = Enum.map(1..12, &:binary.copy(<<&1>>, 4096))

    results =
      payloads
      |> Task.async_stream(&{&1, DurableFile.write_new(path, &1)}, timeout: :infinity)
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{winner, :ok}] = Enum.filter(results, &(elem(&1, 1) == :ok))
    assert File.read!(path) == winner
    assert :ok = DurableFile.write_new(path, winner)

    assert Enum.all?(results, fn
             {^winner, :ok} -> true
             {_other, {:error, {:immutable_file_collision, ^path}}} -> true
             _ -> false
           end)

    assert Path.wildcard(path <> "*.tmp") == []
  end
end
