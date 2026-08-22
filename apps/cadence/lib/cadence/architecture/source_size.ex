defmodule Cadence.Architecture.SourceSize do
  @moduledoc """
  Reports source files and test functions that exceed architecture review limits.

  The diagnostic is intentionally advisory. Its thresholds identify change
  pressure; they do not decide whether a large file is well designed.
  """

  @default_thresholds %{
    production_file: 1_000,
    test_file: 1_500,
    test_function: 300
  }

  @source_globs [
    "apps/*/lib/**/*.ex",
    "apps/*/test/**/*.{ex,exs}",
    "apps/*/browser_test/**/*.{ex,exs}",
    "packages/*/lib/**/*.ex",
    "packages/*/test/**/*.{ex,exs}"
  ]

  @type finding_kind :: :production_file | :test_file | :test_function

  @type finding :: %{
          required(:kind) => finding_kind(),
          required(:path) => String.t(),
          required(:lines) => non_neg_integer(),
          required(:limit) => pos_integer(),
          optional(:line) => pos_integer(),
          optional(:name) => String.t()
        }

  @spec scan(String.t(), keyword()) :: [finding()]
  def scan(repo_root, opts \\ []) do
    repo_root = Path.expand(repo_root)

    @source_globs
    |> Enum.flat_map(&Path.wildcard(Path.join(repo_root, &1)))
    |> Enum.uniq()
    |> scan_files(Keyword.put(opts, :root, repo_root))
  end

  @spec scan_files([String.t()], keyword()) :: [finding()]
  def scan_files(paths, opts \\ []) do
    root = opts |> Keyword.get(:root, File.cwd!()) |> Path.expand()
    thresholds = thresholds(opts)

    paths
    |> Enum.sort()
    |> Enum.flat_map(&file_findings(&1, root, thresholds))
    |> Enum.sort_by(&finding_sort_key/1)
  end

  @spec repo_root!(String.t()) :: String.t()
  def repo_root!(start_path \\ File.cwd!()) do
    start_path
    |> Path.expand()
    |> ancestor_paths()
    |> Enum.find(&repo_root?/1)
    |> case do
      nil -> raise ArgumentError, "could not find the Cadence workspace root"
      path -> path
    end
  end

  @spec format_finding(finding()) :: String.t()
  def format_finding(%{kind: :production_file} = finding) do
    "#{finding.path} has #{finding.lines} production lines (limit #{finding.limit})"
  end

  def format_finding(%{kind: :test_file} = finding) do
    "#{finding.path} has #{finding.lines} test lines (limit #{finding.limit})"
  end

  def format_finding(%{kind: :test_function} = finding) do
    "#{finding.path}:#{finding.line} #{finding.name} spans #{finding.lines} lines " <>
      "(limit #{finding.limit})"
  end

  defp file_findings(path, root, thresholds) do
    source = File.read!(path)
    relative_path = Path.relative_to(path, root)
    line_count = line_count(source)

    case source_kind(relative_path) do
      :production ->
        maybe_file_finding(
          :production_file,
          relative_path,
          line_count,
          thresholds.production_file
        )

      :test ->
        maybe_file_finding(:test_file, relative_path, line_count, thresholds.test_file) ++
          test_function_findings(
            source,
            relative_path,
            thresholds.test_function
          )
    end
  end

  defp maybe_file_finding(kind, path, lines, limit) when lines > limit do
    [%{kind: kind, path: path, lines: lines, limit: limit}]
  end

  defp maybe_file_finding(_kind, _path, _lines, _limit), do: []

  defp test_function_findings(source, path, limit) do
    case Code.string_to_quoted(source,
           columns: true,
           token_metadata: true
         ) do
      {:ok, ast} ->
        {_ast, findings} =
          Macro.prewalk(ast, [], fn
            {:test, metadata, args} = node, findings ->
              {node, maybe_test_function_finding(metadata, args, path, limit, findings)}

            node, findings ->
              {node, findings}
          end)

        findings

      {:error, _reason} ->
        []
    end
  end

  defp maybe_test_function_finding(metadata, args, path, limit, findings) do
    line = Keyword.get(metadata, :line)
    end_line = metadata |> Keyword.get(:end, []) |> Keyword.get(:line)

    if is_integer(line) and is_integer(end_line) and end_line - line + 1 > limit do
      [
        %{
          kind: :test_function,
          path: path,
          line: line,
          name: test_name(args),
          lines: end_line - line + 1,
          limit: limit
        }
        | findings
      ]
    else
      findings
    end
  end

  defp test_name([name | _args]) when is_binary(name), do: "test #{inspect(name)}"
  defp test_name(_args), do: "test"

  defp source_kind(path) do
    if String.contains?(path, ["/test/", "/browser_test/"]) do
      :test
    else
      :production
    end
  end

  defp line_count(""), do: 0

  defp line_count(source) do
    newline_count = source |> :binary.matches("\n") |> length()

    if String.ends_with?(source, "\n") do
      newline_count
    else
      newline_count + 1
    end
  end

  defp thresholds(opts) do
    %{
      production_file:
        Keyword.get(opts, :production_file_limit, @default_thresholds.production_file),
      test_file: Keyword.get(opts, :test_file_limit, @default_thresholds.test_file),
      test_function: Keyword.get(opts, :test_function_limit, @default_thresholds.test_function)
    }
  end

  defp finding_sort_key(finding) do
    {finding.kind, finding.path, Map.get(finding, :line, 0)}
  end

  defp ancestor_paths(path) do
    Stream.unfold(path, fn current ->
      parent = Path.dirname(current)

      if parent == current do
        {current, nil}
      else
        {current, parent}
      end
    end)
  end

  defp repo_root?(path) do
    File.regular?(Path.join(path, "mix.exs")) and
      File.regular?(Path.join(path, "apps/cadence/mix.exs"))
  end
end
