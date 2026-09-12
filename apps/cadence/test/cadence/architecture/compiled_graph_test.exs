defmodule Cadence.Architecture.CompiledGraphTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.CompiledGraph

  @tag :tmp_dir
  test "real project compilation preserves cross-project references and rejects stale source", %{
    tmp_dir: root
  } do
    domain = Path.join(root, "apps/cadence")
    web = Path.join(root, "apps/cadence_web")
    for directory <- [domain, web], do: File.mkdir_p!(Path.join(directory, "lib"))

    File.write!(Path.join(domain, "mix.exs"), """
    defmodule DomainFixture.MixProject do
      use Mix.Project
      def project, do: [app: :cadence, version: "0.1.0"]
    end
    """)

    File.write!(Path.join(web, "mix.exs"), """
    defmodule WebFixture.MixProject do
      use Mix.Project
      def project, do: [app: :cadence_web, version: "0.1.0", deps: [{:cadence, path: "../cadence"}]]
    end
    """)

    domain_source = Path.join(domain, "lib/domain_fixture.ex")
    File.write!(domain_source, "defmodule DomainFixture do\n  def read, do: :ok\nend\n")

    File.write!(
      Path.join(web, "lib/web_fixture.ex"),
      "defmodule WebFixture do\n  def read, do: DomainFixture.read()\nend\n"
    )

    {output, status} =
      System.cmd("mix", ["compile", "--warnings-as-errors"],
        cd: web,
        env: [
          {"MIX_ENV", "test"},
          {"MIX_TARGET", "host"},
          {"MIX_BUILD_PATH", nil},
          {"MIX_BUILD_ROOT", nil}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    build = Path.join(web, "_build/test")
    graph = CompiledGraph.load!(root, build)

    assert graph == %{
             "lib/domain_fixture.ex" => %{},
             "lib/web_fixture.ex" => %{"lib/domain_fixture.ex" => "runtime"}
           }

    assert CompiledGraph.validate_prepared!(graph, graph) == graph
    File.write!(domain_source, "defmodule DomainFixture do\n  def read, do: :changed\nend\n")

    assert_raise ArgumentError, ~r/source changed since compilation/, fn ->
      CompiledGraph.load!(root, build)
    end

    File.write!(domain_source, "defmodule DomainFixture do\n  def read, do: :ok\nend\n")
    File.write!(Path.join(web, "lib/added.ex"), "defmodule Added do\nend\n")
    # Coverage validation runs for each project before its bytes are accepted.
    assert_raise ArgumentError, ~r/does not cover its current production sources/, fn ->
      CompiledGraph.load!(root, build)
    end
  end

  test "one module index preserves cross-project edges, all file references and label precedence" do
    entries = [
      entry("lib/cadence/one.ex", [Example.One, Example.Other],
        runtime: [Example.Two, Example.One, Example.External],
        export: [Example.Three],
        compile: [Example.Two]
      ),
      entry("lib/cadence/two.ex", [Example.Two]),
      entry("lib/cadence_web/three.ex", [Example.Three], runtime: [Example.One])
    ]

    assert CompiledGraph.from_entries!(entries) == %{
             "lib/cadence/one.ex" => %{
               "lib/cadence/two.ex" => "compile",
               "lib/cadence_web/three.ex" => "export"
             },
             "lib/cadence/two.ex" => %{},
             "lib/cadence_web/three.ex" => %{"lib/cadence/one.ex" => "runtime"}
           }
  end

  test "empty inventories, path collisions and modules with two owners fail closed" do
    assert_raise ArgumentError, ~r/no production sources/, fn ->
      CompiledGraph.from_entries!([])
    end

    first = entry("lib/one.ex", [Example.One])

    assert_raise ArgumentError, ~r/duplicate production source/, fn ->
      CompiledGraph.from_entries!([first, first])
    end

    assert_raise ArgumentError, ~r/multiple production owners/, fn ->
      CompiledGraph.from_entries!([first, entry("lib/two.ex", [Example.One])])
    end
  end

  test "prepared graphs cannot omit sources, remove edges, change labels or introduce outside paths" do
    current = %{
      "lib/cadence/one.ex" => %{"lib/cadence_web/two.ex" => "runtime"},
      "lib/cadence_web/two.ex" => %{}
    }

    for candidate <- [
          nil,
          [],
          %{},
          %{"unrelated.ex" => %{}},
          Map.delete(current, "lib/cadence_web/two.ex"),
          Map.put(current, "lib/cadence/one.ex", []),
          Map.put(current, "lib/cadence/one.ex", %{}),
          Map.put(current, "lib/cadence/one.ex", %{"lib/cadence_web/two.ex" => "compile"}),
          Map.put(current, "lib/cadence/one.ex", %{"lib/cadence_web/two.ex" => "unknown"}),
          Map.put(current, "lib/cadence/one.ex", %{"../../outside.ex" => "runtime"})
        ] do
      assert_raise ArgumentError, fn -> CompiledGraph.validate_prepared!(candidate, current) end
    end

    assert_raise ArgumentError, fn -> CompiledGraph.validate_prepared!(%{}, %{}) end
  end

  @tag :tmp_dir
  test "compiler content digests reject stale source bytes and missing or unknown formats", %{
    tmp_dir: directory
  } do
    file = Path.join(directory, "source.ex")
    content = "defmodule DigestFixture do\nend\n"
    File.write!(file, content)

    for algorithm <- [:blake2b, :blake2s, :md5] do
      entry = %{file: file, digest: :crypto.hash(algorithm, content)}
      assert CompiledGraph.assert_current!(entry) == nil
      File.write!(file, content <> "# changed\n")

      assert_raise ArgumentError, ~r/source changed since compilation/, fn ->
        CompiledGraph.assert_current!(entry)
      end

      File.write!(file, content)
    end

    for digest <- [nil, "unknown"] do
      assert_raise ArgumentError, ~r/missing or unsupported/, fn ->
        CompiledGraph.assert_current!(%{file: file, digest: digest})
      end
    end
  end

  @tag :tmp_dir
  test "absent compile manifests cannot become a clean graph", %{tmp_dir: directory} do
    source = Path.join(directory, "apps/cadence/lib/one.ex")
    File.mkdir_p!(Path.dirname(source))
    File.write!(source, "defmodule One do\nend\n")

    assert_raise ArgumentError, ~r/does not cover its current production sources/, fn ->
      CompiledGraph.load!(directory, Path.join(directory, "_build/test"))
    end
  end

  defp entry(path, modules, references \\ []),
    do:
      Map.merge(
        %{path: path, modules: modules, runtime: [], export: [], compile: []},
        Map.new(references)
      )
end
