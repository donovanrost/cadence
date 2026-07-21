defmodule CadenceSimulator.CatalogDatabase do
  @moduledoc """
  Loads and compiles a command-and-telemetry database without a Cadence runtime.

  This is the simulator-facing adapter over `cadence_catalog`. It deliberately
  stops at portable import and compiler results; it does not create Cadence
  revisions, rows, jobs, bindings, or activation state.
  """

  alias Cadence.Catalog.Command.Compiler, as: CommandCompiler
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult
  alias Cadence.Catalog.Command.Compiler.RuntimeDefinition
  alias Cadence.Catalog.Command.{Decoder, Invocation}
  alias Cadence.Catalog.{Ids, ImportResult, Source}
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Telemetry.Compiler, as: TelemetryCompiler
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: TelemetryCompilerResult

  @type t :: %__MODULE__{
          source: Source.t(),
          import_result: ImportResult.t(),
          telemetry_compilation: TelemetryCompilerResult.t() | nil,
          command_compilation: CommandCompilerResult.t() | nil
        }

  defstruct [
    :source,
    :import_result,
    :telemetry_compilation,
    :command_compilation
  ]

  @doc """
  Builds a portable source for YAML content and loads both catalog families.

  Source identity fields may be supplied as atom or string keys. Simulator-safe
  defaults are generated when they are omitted.
  """
  @spec load_yaml(binary(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def load_yaml(content, source_attrs \\ %{}, opts \\ [])
      when is_binary(content) and is_map(source_attrs) and is_list(opts) do
    source =
      Source.new(%{
        artifact_id: get(source_attrs, :artifact_id, Ids.new("simulator_catalog")),
        organization_id: get(source_attrs, :organization_id),
        mission_id: get(source_attrs, :mission_id, "simulator"),
        catalog_family: get(source_attrs, :catalog_family, :combined),
        artifact_name: get(source_attrs, :artifact_name, "simulator-catalog.yaml"),
        format_key: get(source_attrs, :format_key, "cadence_yaml"),
        format_version: get(source_attrs, :format_version),
        media_type: get(source_attrs, :media_type, "application/yaml"),
        source_artifact: content,
        metadata: get(source_attrs, :metadata, %{})
      })

    load(source, opts)
  end

  @doc """
  Runs the selected portable importer and compiles every snapshot it returns.
  """
  @spec load(Source.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(%Source{} = source, opts \\ []) when is_list(opts) do
    importer = Keyword.get(opts, :importer, CadenceYamlDatabase)
    import_run_id = Keyword.get(opts, :import_run_id, Ids.new("simulator_import"))

    with :ok <- validate(importer, source),
         {:ok, %ImportResult{} = import_result} <-
           importer.import(source, %{import_run_id: import_run_id}) do
      {:ok,
       %__MODULE__{
         source: source,
         import_result: import_result,
         telemetry_compilation:
           compile_telemetry(import_result, Keyword.get(opts, :telemetry_compiler, [])),
         command_compilation: compile_commands(import_result)
       }}
    end
  end

  @doc """
  Returns importer and compiler diagnostics in execution order.
  """
  @spec diagnostics(t()) :: [Cadence.Catalog.Diagnostic.t()]
  def diagnostics(%__MODULE__{} = database) do
    database.import_result.diagnostics ++
      compilation_diagnostics(database.telemetry_compilation) ++
      compilation_diagnostics(database.command_compilation)
  end

  @doc """
  Fetches one compiled command by its stable ID or catalog name.
  """
  @spec fetch_command(t(), binary()) :: {:ok, RuntimeDefinition.t()} | {:error, term()}
  def fetch_command(
        %__MODULE__{command_compilation: %CommandCompilerResult{} = result},
        command_ref
      )
      when is_binary(command_ref) do
    case Enum.find(
           result.runtime_definitions,
           &(&1.command_id == command_ref or &1.name == command_ref)
         ) do
      %RuntimeDefinition{} = runtime_definition -> {:ok, runtime_definition}
      nil -> {:error, {:simulator_command_not_found, command_ref}}
    end
  end

  def fetch_command(%__MODULE__{}, command_ref),
    do: {:error, {:simulator_command_not_found, command_ref}}

  @doc """
  Resolves invocation arguments for a command in this database.
  """
  @spec resolve_command(t(), binary(), map()) ::
          {:ok, RuntimeDefinition.t(), map()} | {:error, term()}
  def resolve_command(%__MODULE__{} = database, command_ref, arguments)
      when is_binary(command_ref) and is_map(arguments) do
    with {:ok, %RuntimeDefinition{} = runtime_definition} <-
           fetch_command(database, command_ref),
         {:ok, resolved_arguments} <- Invocation.resolve(runtime_definition, arguments) do
      {:ok, runtime_definition, resolved_arguments}
    end
  end

  @doc """
  Decodes an encoded command payload using this database's compiled commands.
  """
  @spec decode_command(t(), binary()) ::
          {:ok, %{runtime_definition: RuntimeDefinition.t(), arguments: map()}}
          | {:error, term()}
  def decode_command(
        %__MODULE__{command_compilation: %CommandCompilerResult{} = result},
        payload
      )
      when is_binary(payload) do
    Decoder.decode(result.runtime_definitions, payload)
  end

  def decode_command(%__MODULE__{}, _payload), do: {:error, :command_catalog_not_loaded}

  defp validate(importer, source) do
    if function_exported?(importer, :validate, 1) do
      importer.validate(source)
    else
      :ok
    end
  end

  defp compile_telemetry(%ImportResult{} = result, opts) do
    case result.bundle.telemetry_snapshot do
      nil -> nil
      snapshot -> TelemetryCompiler.compile(snapshot, opts)
    end
  end

  defp compile_commands(%ImportResult{} = result) do
    case result.bundle.command_snapshot do
      nil -> nil
      snapshot -> CommandCompiler.compile(snapshot)
    end
  end

  defp compilation_diagnostics(nil), do: []
  defp compilation_diagnostics(compilation), do: compilation.diagnostics

  defp get(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
