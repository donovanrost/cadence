defmodule Cadence.Architecture.SourceSizeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.SourceSize

  test "reports production and test files over their limits" do
    root = fixture_root()
    production_path = Path.join(root, "apps/cadence/lib/cadence/large.ex")
    test_path = Path.join(root, "apps/cadence/test/cadence/large_test.exs")

    write_source!(production_path, repeated_lines(11))
    write_source!(test_path, repeated_lines(16))

    assert [
             %{kind: :production_file, path: "apps/cadence/lib/cadence/large.ex", lines: 11},
             %{kind: :test_file, path: "apps/cadence/test/cadence/large_test.exs", lines: 16}
           ] =
             SourceSize.scan_files([production_path, test_path],
               root: root,
               production_file_limit: 10,
               test_file_limit: 15
             )
  end

  test "reports an oversized test block with its source line" do
    root = fixture_root()
    path = Path.join(root, "apps/cadence/test/cadence/large_test.exs")

    source = """
    defmodule LargeTest do
      test "large scenario" do
        #{repeated_lines(5)}
      end
    end
    """

    write_source!(path, source)

    assert [
             %{
               kind: :test_function,
               path: "apps/cadence/test/cadence/large_test.exs",
               line: 2,
               lines: 7,
               name: ~s(test "large scenario"),
               limit: 6
             }
           ] =
             SourceSize.scan_files([path],
               root: root,
               test_file_limit: 100,
               test_function_limit: 6
             )
  end

  test "finds the workspace root from a child application" do
    repo_root = SourceSize.repo_root!()

    assert SourceSize.repo_root!(Path.join(repo_root, "apps/cadence")) == repo_root
  end

  defp fixture_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "cadence-source-size-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp write_source!(path, source) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, source)
  end

  defp repeated_lines(count) do
    1..count
    |> Enum.map_join("\n", &"line_#{&1}")
  end
end
