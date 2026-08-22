defmodule CadenceSimulator.CatalogDatabase do
  @moduledoc """
  Loads a command-and-telemetry database as a native Mission Model.

  The simulator uses the same importer, canonical revision, and target plans as
  Cadence runtime. It does not create Cadence rows, jobs, bindings, or
  activation state.
  """

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep, RuntimeDefinition}
  alias Cadence.Catalog.Command.{Decoder, Invocation, StateEffect, TypeEncoding}
  alias Cadence.Catalog.Ids
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.ImportResult
  alias Cadence.Catalog.MissionModel.{Compiler, CompilerResult}
  alias Cadence.Catalog.Source
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @type t :: %__MODULE__{
          source: Source.t(),
          import_result: ImportResult.t(),
          compilation: CompilerResult.t(),
          packet_definitions: [PacketDefinition.t()],
          command_definitions: [RuntimeDefinition.t()]
        }

  @enforce_keys [
    :source,
    :import_result,
    :compilation,
    :packet_definitions,
    :command_definitions
  ]
  defstruct @enforce_keys

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

  @spec load(Source.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(%Source{} = source, opts \\ []) when is_list(opts) do
    importer = Keyword.get(opts, :importer, CadenceYamlDatabase)
    import_run_id = Keyword.get(opts, :import_run_id, Ids.new("simulator_import"))

    with :ok <- validate(importer, source),
         {:ok, %ImportResult{} = import_result} <-
           importer.import(source, %{import_run_id: import_run_id}),
         {:ok, %CompilerResult{} = compilation} <-
           Compiler.compile(import_result.bundle.declaration_layers),
         {:ok, packet_definitions} <- decode_telemetry(compilation),
         {:ok, command_definitions} <- decode_commands(compilation) do
      {:ok,
       %__MODULE__{
         source: source,
         import_result: import_result,
         compilation: compilation,
         packet_definitions: packet_definitions,
         command_definitions: command_definitions
       }}
    end
  end

  @spec diagnostics(t()) :: list()
  def diagnostics(%__MODULE__{} = database) do
    target_diagnostics =
      database.compilation.plans
      |> Map.values()
      |> Enum.flat_map(& &1.diagnostics)

    Enum.uniq(
      database.import_result.diagnostics ++
        database.compilation.revision.diagnostics ++ target_diagnostics
    )
  end

  @spec fetch_command(t(), binary()) :: {:ok, RuntimeDefinition.t()} | {:error, term()}
  def fetch_command(%__MODULE__{} = database, command_ref) when is_binary(command_ref) do
    case Enum.find(
           database.command_definitions,
           &(&1.command_id == command_ref or &1.name == command_ref)
         ) do
      %RuntimeDefinition{} = runtime_definition -> {:ok, runtime_definition}
      nil -> {:error, {:simulator_command_not_found, command_ref}}
    end
  end

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

  @spec decode_command(t(), binary()) ::
          {:ok, %{runtime_definition: RuntimeDefinition.t(), arguments: map()}}
          | {:error, term()}
  def decode_command(%__MODULE__{} = database, payload) when is_binary(payload) do
    Decoder.decode(database.command_definitions, payload)
  end

  defp validate(importer, source) do
    if function_exported?(importer, :validate, 1), do: importer.validate(source), else: :ok
  end

  defp decode_telemetry(%CompilerResult{plans: %{telemetry: plan}}) do
    if plan.status == :ready and
         value(plan.plan, :runtime_contract) == "mission_model_telemetry_v1" do
      {:ok, Enum.map(list(plan.plan, :packet_definitions), &packet_definition/1)}
    else
      {:error, {:mission_model_telemetry_plan_not_ready, plan.diagnostics}}
    end
  end

  defp decode_commands(%CompilerResult{plans: %{command: plan}}) do
    if plan.status == :ready and value(plan.plan, :runtime_contract) == "mission_model_command_v1" do
      {:ok, Enum.map(list(plan.plan, :runtime_definitions), &runtime_definition/1)}
    else
      {:error, {:mission_model_command_plan_not_ready, plan.diagnostics}}
    end
  end

  defp packet_definition(document) do
    PacketDefinition.new(%{
      packet_definition_id: value(document, :packet_definition_id),
      organization_id: value(document, :organization_id),
      mission_id: value(document, :mission_id),
      packet_name: value(document, :packet_name),
      apid: value(document, :apid),
      version: value(document, :version, 1),
      fields: Enum.map(list(document, :fields), &field_definition/1)
    })
  end

  defp field_definition(document) do
    FieldDefinition.new(%{
      field_id: value(document, :field_id),
      parameter_id: value(document, :parameter_id),
      qualified_name: value(document, :qualified_name),
      name: value(document, :name),
      offset_bits: value(document, :offset_bits, 0),
      size_bits: value(document, :size_bits),
      data_type:
        enum(value(document, :data_type), [:uint, :int, :float, :bool, :binary, :string]),
      byte_order: enum(value(document, :byte_order), [:big_endian, :little_endian]),
      engineering_unit: value(document, :engineering_unit)
    })
  end

  defp runtime_definition(document) do
    RuntimeDefinition.new(%{
      command_id: value(document, :command_id),
      mission_model_revision_id: value(document, :mission_model_revision_id),
      name: value(document, :name),
      display_name: value(document, :display_name),
      description: value(document, :description),
      layout_id: value(document, :layout_id),
      layout_kind:
        enum(value(document, :layout_kind), [
          :binary_container,
          :space_packet,
          :service_data_unit,
          :raw_payload
        ]),
      byte_order: enum(value(document, :byte_order), [:big_endian, :little_endian]),
      apid: value(document, :apid),
      service_type: value(document, :service_type),
      service_subtype: value(document, :service_subtype),
      opcode: value(document, :opcode),
      opcode_size_bits: value(document, :opcode_size_bits),
      size_bits: value(document, :size_bits),
      max_size_bits: value(document, :max_size_bits),
      argument_specs: Enum.map(list(document, :argument_specs), &argument_spec/1),
      encoding_steps: Enum.map(list(document, :encoding_steps), &encoding_step/1),
      default_argument_values: value(document, :default_argument_values, %{}),
      fixed_argument_values: value(document, :fixed_argument_values, %{}),
      state_effects: Enum.map(list(document, :state_effects), &state_effect/1),
      metadata: value(document, :metadata, %{})
    })
  end

  defp argument_spec(document) do
    ArgumentSpec.new(%{
      argument_id: value(document, :argument_id),
      name: value(document, :name),
      description: value(document, :description),
      base_type:
        enum(value(document, :base_type), [
          :integer,
          :float,
          :string,
          :binary,
          :boolean,
          :enumerated
        ]),
      required: value(document, :required, true),
      encoding: TypeEncoding.new(value(document, :encoding, %{})),
      default_value: value(document, :default_value),
      fixed_value: value(document, :fixed_value),
      hazardous_values: value(document, :hazardous_values, []),
      metadata: value(document, :metadata, %{})
    })
  end

  defp encoding_step(document) do
    EncodingStep.new(%{
      step_kind: enum(value(document, :step_kind), [:argument_ref, :fixed_value]),
      argument_id: value(document, :argument_id),
      bit_offset: value(document, :bit_offset),
      bit_offset_from: :layout_start,
      size_bits: value(document, :size_bits),
      fixed_value: value(document, :fixed_value),
      display_order: value(document, :display_order),
      metadata: value(document, :metadata, %{})
    })
  end

  defp state_effect(document) do
    StateEffect.new(%{
      effect_id: value(document, :effect_id),
      target_ref: value(document, :target_ref),
      operation: value(document, :operation),
      argument_ref: value(document, :argument_id),
      value: value(document, :value),
      metadata: value(document, :metadata, %{})
    })
  end

  defp enum(value, allowed) when is_atom(value) do
    if value in allowed, do: value
  end

  defp enum(value, allowed) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value))
  end

  defp list(map, key), do: value(map, key, [])

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp get(attrs, key, default \\ nil), do: value(attrs, key, default)
end
