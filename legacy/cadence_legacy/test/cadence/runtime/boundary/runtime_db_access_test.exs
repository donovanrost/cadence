defmodule Cadence.Runtime.Boundary.RuntimeDbAccessTest do
  use Cadence.PureCase, async: true

  @runtime_dirs [
    "lib/cadence/runtime/uplink",
    "lib/cadence/runtime/protocol"
  ]

  @forbidden_patterns [
    "Cadence.Repo",
    "Cadence.Links.",
    "Ecto.Query"
  ]

  test "uplink/downlink runtime modules avoid database access" do
    offenders =
      @runtime_dirs
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
      |> Enum.flat_map(fn file ->
        contents = File.read!(file)

        @forbidden_patterns
        |> Enum.filter(&String.contains?(contents, &1))
        |> Enum.map(&{file, &1})
      end)

    assert offenders == []
  end
end
