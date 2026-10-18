defmodule Cadence.Architecture.CompiledGraph do
  @moduledoc """
  Current production dependencies across the Cadence domain and web projects.

  A single module index preserves references across workspace path dependencies,
  which separate `mix xref graph` calls omit. Compile manifests supply reference
  kinds; the production inventory and compiler content digests establish coverage
  and currentness. Test helpers are outside this production policy.
  """

  import Mix.Compilers.Elixir, only: [read_manifest: 1, source: 2]

  @projects [{:cadence, "apps/cadence"}, {:cadence_web, "apps/cadence_web"}]
  @labels ~w(runtime export compile)

  def projects, do: @projects

  def load!(root, build_path) do
    entries = Enum.flat_map(@projects, &project_entries!(&1, root, build_path))
    graph = from_entries!(entries)
    Enum.each(entries, &assert_current!/1)
    graph
  end

  @doc false
  def from_entries!(entries) when is_list(entries) and entries != [] do
    paths = Enum.map(entries, & &1.path)
    if length(Enum.uniq(paths)) != length(paths), do: invalid!("duplicate production source path")

    index =
      Enum.reduce(entries, %{}, fn entry, index ->
        Enum.reduce(entry.modules, index, &put_module_owner!(&2, &1, entry.path))
      end)

    Map.new(entries, fn entry -> {entry.path, entry_references(entry, index)} end)
  end

  def from_entries!(_), do: invalid!("no production sources")

  @doc "Admits prepared JSON only when it is the exact current production graph."
  def validate_prepared!(candidate, current) when is_map(current) and map_size(current) > 0 do
    unless is_map(candidate) and map_size(candidate) > 0,
      do: invalid!("prepared graph must be a nonempty object")

    unless MapSet.new(Map.keys(candidate)) == MapSet.new(Map.keys(current)),
      do:
        invalid!("prepared graph does not cover the current domain and web production inventory")

    Enum.each(candidate, fn {path, references} ->
      validate_references!(path, references, current)
    end)

    unless candidate == current,
      do: invalid!("prepared graph differs from current compiler references")

    candidate
  end

  def validate_prepared!(_, _), do: invalid!("no current production graph")

  defp put_module_owner!(index, name, source_path) do
    case Map.fetch(index, name) do
      :error -> Map.put(index, name, source_path)
      {:ok, ^source_path} -> index
      {:ok, _} -> invalid!("module has multiple production owners: #{inspect(name)}")
    end
  end

  defp entry_references(entry, index) do
    Enum.reduce([:runtime, :export, :compile], %{}, fn kind, references ->
      entry
      |> Map.fetch!(kind)
      |> Enum.reduce(references, &put_reference(&2, &1, entry.path, kind, index))
    end)
  end

  defp put_reference(references, name, source_path, kind, index) do
    case Map.get(index, name) do
      nil -> references
      ^source_path -> references
      path -> Map.put(references, path, Atom.to_string(kind))
    end
  end

  defp validate_references!(path, references, current) do
    unless is_map(references), do: invalid!("invalid references for #{path}")

    Enum.each(references, fn {target, label} ->
      unless Map.has_key?(current, target) and label in @labels,
        do: invalid!("invalid production dependency from #{path}")
    end)
  end

  defp project_entries!({app, relative_root}, root, build_path) do
    project_root = Path.join(root, relative_root)
    manifest = Path.join([build_path, "lib", Atom.to_string(app), ".mix", "compile.elixir"])
    {_modules, sources} = read_manifest(manifest)

    entries =
      for {path, record} <- sources, String.starts_with?(path, "lib/") do
        %{
          path: path,
          file: Path.join(project_root, path),
          digest: source(record, :digest),
          modules: source(record, :modules),
          runtime: source(record, :runtime_references),
          export: source(record, :export_references),
          compile: source(record, :compile_references)
        }
      end

    expected =
      project_root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, project_root))
      |> Enum.sort()

    if expected == [] or Enum.sort(Enum.map(entries, & &1.path)) != expected,
      do: invalid!("#{app} compile manifest does not cover its current production sources")

    Enum.each(entries, &assert_current!/1)
    entries
  end

  @doc false
  def assert_current!(entry) do
    # These are the content-digest formats emitted by Mix's Elixir compiler.
    # Unknown or absent formats fail closed instead of accepting a stale file.
    algorithm =
      case entry.digest do
        digest when is_binary(digest) and byte_size(digest) == 64 -> :blake2b
        digest when is_binary(digest) and byte_size(digest) == 32 -> :blake2s
        digest when is_binary(digest) and byte_size(digest) == 16 -> :md5
        _ -> invalid!("missing or unsupported compiler source digest: #{entry.file}")
      end

    unless :crypto.hash(algorithm, File.read!(entry.file)) == entry.digest,
      do: invalid!("source changed since compilation: #{entry.file}")
  end

  defp invalid!(reason), do: raise(ArgumentError, "Invalid architecture graph: " <> reason)
end
