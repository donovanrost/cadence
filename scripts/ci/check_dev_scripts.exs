defmodule Cadence.CI.DevScriptCheck do
  @moduledoc false

  @excluded ~w(chaos ingress-benchmark otp_cluster)

  def run(argv) do
    root =
      case argv do
        [] -> Path.expand("../..", __DIR__)
        [path] -> Path.expand(path)
        _ -> raise "usage: check_dev_scripts.exs [repository root]"
      end

    files =
      root
      |> Path.join("dev/**/*.exs")
      |> Path.wildcard()
      |> Enum.reject(&excluded?(&1, root))
      |> Enum.sort()

    if files == [], do: raise("no dev scripts found under #{root}")

    temporary =
      Path.join(
        System.tmp_dir!(),
        "cadence-dev-script-check-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(temporary)

    try do
      parsed = Enum.map(files, &parse/1)
      {module_files, source_paths} = module_sources(parsed, temporary, root)
      module_diagnostics = compile_modules(module_files)
      entry_diagnostics = compile_entries(parsed)
      diagnostics = module_diagnostics ++ entry_diagnostics

      Enum.each(diagnostics, &report(&1, source_paths, root))

      if diagnostics != [], do: System.halt(1)
      IO.puts("Dev scripts: compiled #{length(files)} files without running entrypoints")
    after
      File.rm_rf!(temporary)
    end
  end

  defp excluded?(file, root) do
    case file |> Path.relative_to(Path.join(root, "dev")) |> Path.split() do
      [directory | _] -> directory in @excluded
      _ -> false
    end
  end

  defp parse(file) do
    source = File.read!(file)
    ast = Code.string_to_quoted!(source, file: file, token_metadata: true)
    forms = if match?({:__block__, _, _}, ast), do: elem(ast, 2), else: [ast]
    {file, source, forms}
  end

  defp module_sources(parsed, temporary, root) do
    Enum.reduce(parsed, {[], %{}}, fn {file, source, forms}, {files, paths} ->
      modules = Enum.filter(forms, &match?({:defmodule, _, _}, &1))

      cond do
        modules == [] ->
          {files, paths}

        length(modules) == length(forms) ->
          {[file | files], paths}

        true ->
          temporary_file = Path.join(temporary, Path.relative_to(file, root))
          File.mkdir_p!(Path.dirname(temporary_file))
          File.write!(temporary_file, modules_only(source, forms))
          {[temporary_file | files], Map.put(paths, temporary_file, file)}
      end
    end)
  end

  # Keep module source on its original lines; all executable top-level forms become blank lines.
  # This also lets ParallelCompiler resolve cross-file module references in any order.
  defp modules_only(source, forms) do
    lines = String.split(source, "\n")

    ranges =
      forms
      |> Enum.flat_map(fn
        {:defmodule, meta, _} ->
          start_line = Keyword.fetch!(meta, :line)
          end_line = meta |> Keyword.fetch!(:end) |> Keyword.fetch!(:line)
          [{start_line, end_line}]

        _other ->
          []
      end)

    lines
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {line, number} ->
      if module_line?(ranges, number), do: line, else: ""
    end)
  end

  defp module_line?(ranges, number) do
    Enum.any?(ranges, fn {first, last} -> number >= first and number <= last end)
  end

  defp compile_modules(files) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        Kernel.ParallelCompiler.compile(files, return_diagnostics: true)
      end)

    case result do
      {:ok, _modules, _warnings} -> diagnostics
      {:error, errors, _warnings} -> raise "dev module compilation failed: #{inspect(errors)}"
    end
  end

  defp compile_entries(parsed) do
    parsed
    |> Enum.with_index()
    |> Enum.flat_map(fn {{file, _source, forms}, index} -> compile_entry(file, forms, index) end)
  end

  defp compile_entry(file, forms, index) do
    entrypoint = Enum.reject(forms, &match?({:defmodule, _, _}, &1))

    case entrypoint do
      [] -> []
      _ -> compile_entrypoint(file, entrypoint, index)
    end
  end

  defp compile_entrypoint(file, entrypoint, index) do
    module = Module.concat(__MODULE__, "Entrypoint#{index}")

    wrapper =
      quote do
        defmodule unquote(module) do
          @moduledoc false

          def run do
            (unquote_splicing(entrypoint))
          end
        end
      end

    {_compiled, diagnostics} =
      Code.with_diagnostics(fn -> Code.compile_quoted(wrapper, file) end)

    Enum.map(diagnostics, fn diagnostic ->
      Map.update(diagnostic, :file, file, &(&1 || file))
    end)
  end

  defp report(diagnostic, source_paths, root) do
    file = Map.get(source_paths, diagnostic.file, diagnostic.file)

    line =
      case diagnostic.position do
        {number, _column} -> number
        number when is_integer(number) -> number
        _ -> 1
      end

    relative = if file, do: Path.relative_to(file, root), else: "<unknown>"
    IO.puts(:stderr, "#{relative}:#{line}: #{diagnostic.message}")
  end
end

Cadence.CI.DevScriptCheck.run(System.argv())
