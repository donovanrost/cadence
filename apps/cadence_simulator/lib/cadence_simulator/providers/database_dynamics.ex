defmodule CadenceSimulator.Providers.DatabaseDynamics do
  @moduledoc """
  Generates telemetry values from a YAML telemetry definition set.

  Unlike `BasicDynamics`, this provider derives point names and value-generation
  strategies from the portable canonical catalog. Compiled command effects can
  override those generated values at runtime.
  """

  @behaviour CadenceSimulator.DynamicsProvider

  import Bitwise

  require Logger

  alias Cadence.Catalog.Command.Compiler.RuntimeDefinition
  alias Cadence.Catalog.Command.StateEffect
  alias Cadence.Catalog.MissionModel.Declaration
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}
  alias CadenceSimulator.CatalogDatabase

  @boolean_toggle_rate 20
  @default_noise_amplitude 1.0
  @float_step_divisor 20.0
  @int_step_divisor 15.0
  @state_cycle_rate 10

  @float_range_keywords [
    {["temp"], {-40.0, 85.0}},
    {["voltage"], {0.0, 50.0}},
    {["current"], {-10.0, 10.0}},
    {["percent", "soc"], {0.0, 100.0}},
    {["rate"], {-5.0, 5.0}},
    {["angle", "roll", "pitch", "yaw"], {-180.0, 180.0}}
  ]

  defstruct [
    :catalog_database,
    :command_state_table,
    :items_by_qualified_name,
    :packets,
    :packet_count,
    :item_count,
    :noise_amplitude
  ]

  @impl true
  def init(config) do
    with {:ok, definitions_content, source_attrs} <- load_definitions(config),
         {:ok, catalog_database} <-
           CatalogDatabase.load_yaml(definitions_content, source_attrs),
         [_ | _] <- catalog_database.packet_definitions do
      {packets, item_count} = extract_definitions(catalog_database)
      items_by_qualified_name = index_items(packets)
      command_state_table = init_command_state()

      Logger.info("""
      DatabaseDynamics initialized:
        packets: #{length(packets)}
        items: #{item_count}
        commands: #{command_count(catalog_database)}
      """)

      {:ok,
       %__MODULE__{
         catalog_database: catalog_database,
         command_state_table: command_state_table,
         items_by_qualified_name: items_by_qualified_name,
         packets: packets,
         packet_count: length(packets),
         item_count: item_count,
         noise_amplitude: Map.get(config, :noise_amplitude, @default_noise_amplitude)
       }}
    else
      nil -> {:error, {:failed_to_load_definitions, :telemetry_catalog_not_found}}
      {:error, reason} -> {:error, {:failed_to_load_definitions, reason}}
    end
  end

  @impl true
  def generate_values(state, step) do
    overrides = command_state(state).overrides
    {:ok, build_flat_values(state.packets, step, state.noise_amplitude, overrides), state}
  end

  @impl true
  def generate_packet_values(state, step) do
    overrides = command_state(state).overrides
    {:ok, build_packet_values(state.packets, step, state.noise_amplitude, overrides), state}
  end

  @impl true
  def status(state) do
    command_state = command_state(state)

    %{
      provider: "DatabaseDynamics",
      packet_count: state.packet_count,
      item_count: state.item_count,
      noise_amplitude: state.noise_amplitude,
      command_count: command_state.command_count,
      last_command: command_state.last_command,
      overridden_point_count: map_size(command_state.overrides)
    }
  end

  @impl true
  def execute_command(state, command_ref, arguments) do
    with {:ok, %RuntimeDefinition{} = runtime_definition, resolved_arguments} <-
           CatalogDatabase.resolve_command(
             state.catalog_database,
             command_ref,
             arguments
           ),
         {:ok, result} <-
           execute_runtime_definition(state, runtime_definition, resolved_arguments) do
      {:ok, result, state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def execute_encoded_command(state, payload) do
    with {:ok,
          %{
            runtime_definition: %RuntimeDefinition{} = runtime_definition,
            arguments: resolved_arguments
          }} <- CatalogDatabase.decode_command(state.catalog_database, payload),
         {:ok, result} <-
           execute_runtime_definition(state, runtime_definition, resolved_arguments) do
      {:ok, result, state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def parallel_safe?(_config), do: true

  defp load_definitions(config) do
    definitions_path = Map.get(config, :definitions_path)
    definitions_content = Map.get(config, :definitions_content)

    cond do
      is_binary(definitions_content) ->
        {:ok, definitions_content, %{artifact_name: "simulator-catalog.yaml"}}

      is_binary(definitions_path) ->
        case File.read(definitions_path) do
          {:ok, content} ->
            {:ok, content, %{artifact_name: Path.basename(definitions_path)}}

          {:error, reason} ->
            {:error, {:load_error, definitions_path, reason}}
        end

      true ->
        {:error, :no_definitions_provided}
    end
  end

  defp extract_definitions(%CatalogDatabase{} = database) do
    declarations = database.compilation.revision.declarations
    limits_by_parameter = limits_by_parameter(database.compilation.plans.monitoring.plan)

    Enum.reduce(database.packet_definitions, {[], 0}, fn %PacketDefinition{} = packet,
                                                         {packets, item_count} ->
      packet_items = build_packet_items(packet, declarations, limits_by_parameter)

      packet_spec = %{
        name: packet.packet_name,
        apid: packet.apid,
        items: packet_items
      }

      {[packet_spec | packets], item_count + length(packet_items)}
    end)
    |> then(fn {packets, item_count} -> {Enum.reverse(packets), item_count} end)
  end

  defp build_packet_items(%PacketDefinition{} = packet, declarations, limits_by_parameter) do
    packet.fields
    |> Enum.with_index()
    |> Enum.flat_map(
      &build_packet_item(packet.packet_name, &1, declarations, limits_by_parameter)
    )
    |> Enum.sort_by(&{&1.bit_offset, &1.sort_index})
  end

  defp build_packet_item(packet_name, {%FieldDefinition{} = field, index}, declarations, limits) do
    with parameter_id when is_binary(parameter_id) <- field.parameter_id,
         %Declaration{} = parameter <- Map.get(declarations, parameter_id),
         %Declaration{} = type <- parameter_type(parameter, declarations) do
      [
        build_item_spec(
          packet_name,
          field,
          parameter,
          type,
          Map.get(limits, parameter_id, %{}),
          index
        )
      ]
    else
      _other -> []
    end
  end

  defp build_item_spec(packet_name, field, parameter, type, limits, sort_index) do
    qualified_name = "#{packet_name}.#{field.name}"
    phase = :erlang.phash2(field.name) / 1000.0

    enumerations =
      Map.new(value(type.definition, :enumerations, []), &{value(&1, :value), value(&1, :label)})

    %{
      bit_offset: field.offset_bits,
      name: field.name,
      parameter_id: parameter.semantic_id,
      qualified_name: qualified_name,
      sort_index: sort_index,
      enumerations: enumerations,
      generator: build_generator(packet_name, field, type, limits, phase)
    }
  end

  defp parameter_type(parameter, declarations) do
    parameter.references
    |> Enum.find(&(&1.role == :type and is_binary(&1.resolved_id)))
    |> case do
      nil -> nil
      reference -> Map.get(declarations, reference.resolved_id)
    end
  end

  defp limits_by_parameter(plan) do
    plan
    |> value(:policies, [])
    |> Map.new(&{value(&1, :parameter_id), value(&1, :rules, %{})})
  end

  defp build_packet_values(packet_specs, step, noise_amplitude, overrides) do
    Enum.map(packet_specs, fn %{name: packet_name, items: item_specs} ->
      values =
        Enum.map(item_specs, &item_value(&1, step, noise_amplitude, overrides))

      {packet_name, values}
    end)
  end

  defp build_flat_values(packet_specs, step, noise_amplitude, overrides) do
    Enum.reduce(packet_specs, %{}, fn %{items: item_specs}, acc ->
      Enum.reduce(item_specs, acc, fn item, item_acc ->
        Map.put(
          item_acc,
          item.qualified_name,
          item_value(item, step, noise_amplitude, overrides)
        )
      end)
    end)
  end

  defp item_value(item, step, noise_amplitude, overrides) do
    case Map.fetch(overrides, item.parameter_id) do
      {:ok, value} ->
        value

      :error ->
        Map.get_lazy(overrides, item.qualified_name, fn ->
          generate_item_value(item.generator, step, noise_amplitude)
        end)
    end
  end

  defp build_generator(packet_name, field, type, limits, phase) do
    bit_size = field.size_bits

    case state_values(type) do
      state_values when is_list(state_values) and state_values != [] ->
        {:state_cycle, List.to_tuple(state_values), length(state_values)}

      _ ->
        build_typed_generator(
          packet_name,
          field.name,
          generator_data_type(type),
          bit_size,
          limits,
          phase
        )
    end
  end

  defp build_typed_generator(_packet_name, item_name, "float", _bit_size, limits, phase) do
    build_float_generator(item_name, limits, phase)
  end

  defp build_typed_generator(_packet_name, item_name, "uint", bit_size, limits, phase) do
    {_min_val, max_val} = get_int_range(limits, bit_size, false)

    if counter_name?(item_name) do
      {:uint_counter, max_val}
    else
      build_integer_wave_generator(limits, bit_size, false, phase)
    end
  end

  defp build_typed_generator(_packet_name, _item_name, "int", bit_size, limits, phase) do
    build_integer_wave_generator(limits, bit_size, true, phase)
  end

  defp build_typed_generator(_packet_name, _item_name, "boolean", _bit_size, _limits, _phase) do
    :boolean_toggle
  end

  defp build_typed_generator(packet_name, item_name, "string", _bit_size, _limits, _phase) do
    {:step_string, "#{packet_name}_#{item_name}_v"}
  end

  defp build_typed_generator(_packet_name, _item_name, "binary", bit_size, _limits, _phase) do
    {:binary_random, div(bit_size || 8, 8)}
  end

  defp build_typed_generator(_packet_name, item_name, _data_type, _bit_size, limits, phase) do
    build_float_generator(item_name, limits, phase)
  end

  defp build_float_generator(item_name, limits, phase) do
    {min_val, max_val} = get_float_range(limits, item_name)
    mid = (min_val + max_val) / 2
    amplitude = (max_val - min_val) / 2 * 0.8
    {:float_wave, phase, mid, amplitude, amplitude * 0.1}
  end

  defp build_integer_wave_generator(limits, bit_size, signed, phase) do
    {min_val, max_val} = get_int_range(limits, bit_size, signed)
    mid = (min_val + max_val) / 2
    amplitude = (max_val - min_val) / 2 * 0.8
    {:integer_wave, phase, min_val, max_val, mid, amplitude}
  end

  defp generate_item_value({:state_cycle, state_values, state_count}, step, _noise_amp) do
    current_index = rem(div(step, @state_cycle_rate), state_count)
    elem(state_values, current_index)
  end

  defp generate_item_value({:float_wave, phase, mid, amplitude, noise_scale}, step, noise_amp) do
    base_value = mid + amplitude * :math.sin(step / @float_step_divisor + phase)
    noise = (0.5 - :rand.uniform()) * noise_amp * noise_scale
    base_value + noise
  end

  defp generate_item_value({:uint_counter, max_val}, step, _noise_amp) do
    rem(step, max_val + 1)
  end

  defp generate_item_value(
         {:integer_wave, phase, min_val, max_val, mid, amplitude},
         step,
         _noise_amp
       ) do
    value = mid + amplitude * :math.sin(step / @int_step_divisor + phase)
    round(value) |> max(min_val) |> min(max_val)
  end

  defp generate_item_value(:boolean_toggle, step, _noise_amp) do
    rem(div(step, @boolean_toggle_rate), 2) == 0
  end

  defp generate_item_value({:step_string, prefix}, step, _noise_amp) do
    prefix <> Integer.to_string(step)
  end

  defp generate_item_value({:binary_random, byte_size}, _step, _noise_amp) do
    :crypto.strong_rand_bytes(byte_size)
  end

  defp execute_runtime_definition(state, %RuntimeDefinition{} = runtime_definition, arguments) do
    current_state = command_state(state)
    argument_specs_by_id = Map.new(runtime_definition.argument_specs, &{&1.argument_id, &1})

    result =
      Enum.reduce_while(
        runtime_definition.state_effects,
        {:ok, current_state.overrides, []},
        fn %StateEffect{} = effect, {:ok, overrides, applied_effects} ->
          case apply_state_effect(
                 state,
                 effect,
                 arguments,
                 argument_specs_by_id,
                 overrides
               ) do
            {:ok, next_overrides, applied_effect} ->
              {:cont, {:ok, next_overrides, [applied_effect | applied_effects]}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )

    case result do
      {:ok, overrides, applied_effects} ->
        command_result = %{
          command_id: runtime_definition.command_id,
          command_name: runtime_definition.name,
          arguments: arguments,
          applied_effects: Enum.reverse(applied_effects)
        }

        put_command_state(state, %{
          overrides: overrides,
          command_count: current_state.command_count + 1,
          last_command: command_result
        })

        {:ok, command_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_state_effect(state, %StateEffect{} = effect, arguments, specs_by_id, overrides) do
    with {:ok, item} <- fetch_effect_target(state, effect),
         {:ok, operand} <- effect_operand(effect, arguments, specs_by_id),
         {:ok, value} <- apply_effect_operation(effect, operand, overrides),
         {:ok, normalized_value} <- normalize_effect_value(item, value) do
      {:ok, Map.put(overrides, effect.target_ref, normalized_value),
       %{
         effect_id: effect.effect_id,
         target_ref: effect.target_ref,
         operation: effect.operation,
         value: normalized_value
       }}
    end
  end

  defp fetch_effect_target(state, %StateEffect{} = effect) do
    case Map.fetch(state.items_by_qualified_name, effect.target_ref) do
      {:ok, item} -> {:ok, item}
      :error -> {:error, {:command_effect_target_not_found, effect.target_ref}}
    end
  end

  defp effect_operand(%StateEffect{operation: :toggle}, _arguments, _specs_by_id),
    do: {:ok, nil}

  defp effect_operand(%StateEffect{argument_id: argument_id}, arguments, specs_by_id)
       when is_binary(argument_id) do
    with {:ok, argument_spec} <- Map.fetch(specs_by_id, argument_id),
         {:ok, value} <- Map.fetch(arguments, argument_spec.name) do
      {:ok, value}
    else
      :error -> {:error, {:command_effect_argument_not_found, argument_id}}
    end
  end

  defp effect_operand(%StateEffect{value: value}, _arguments, _specs_by_id), do: {:ok, value}

  defp apply_effect_operation(%StateEffect{operation: :set}, operand, _overrides),
    do: {:ok, operand}

  defp apply_effect_operation(
         %StateEffect{operation: :increment, target_ref: target},
         operand,
         values
       )
       when is_number(operand) do
    current = Map.get(values, target, 0)

    if is_number(current),
      do: {:ok, current + operand},
      else: {:error, {:command_effect_requires_numeric_target, target, current}}
  end

  defp apply_effect_operation(
         %StateEffect{operation: :decrement, target_ref: target},
         operand,
         values
       )
       when is_number(operand) do
    current = Map.get(values, target, 0)

    if is_number(current),
      do: {:ok, current - operand},
      else: {:error, {:command_effect_requires_numeric_target, target, current}}
  end

  defp apply_effect_operation(
         %StateEffect{operation: :toggle, target_ref: target},
         _operand,
         values
       ) do
    current = Map.get(values, target, false)

    if is_boolean(current),
      do: {:ok, not current},
      else: {:error, {:command_effect_requires_boolean_target, target, current}}
  end

  defp apply_effect_operation(%StateEffect{} = effect, operand, _values),
    do: {:error, {:invalid_command_effect_operand, effect.operation, operand}}

  defp normalize_effect_value(%{enumerations: enumerations}, value)
       when map_size(enumerations) > 0 do
    cond do
      Map.has_key?(enumerations, value) ->
        {:ok, Map.fetch!(enumerations, value)}

      value in Map.values(enumerations) ->
        {:ok, value}

      true ->
        {:error, {:command_effect_enumeration_value_not_found, value}}
    end
  end

  defp normalize_effect_value(_item, value), do: {:ok, value}

  defp init_command_state do
    table =
      :ets.new(:database_dynamics_command_state, [
        :set,
        :protected,
        read_concurrency: true
      ])

    :ets.insert(table, {:state, %{overrides: %{}, command_count: 0, last_command: nil}})
    table
  end

  defp command_state(%__MODULE__{command_state_table: table}) do
    [{:state, command_state}] = :ets.lookup(table, :state)
    command_state
  end

  defp put_command_state(%__MODULE__{command_state_table: table}, command_state) do
    true = :ets.insert(table, {:state, command_state})
    :ok
  end

  defp index_items(packets) do
    packets
    |> Enum.flat_map(& &1.items)
    |> Enum.flat_map(fn item -> [{item.qualified_name, item}, {item.parameter_id, item}] end)
    |> Map.new()
  end

  defp command_count(%CatalogDatabase{} = database), do: length(database.command_definitions)

  defp state_values(%Declaration{} = type) do
    type.definition
    |> value(:enumerations, [])
    |> Enum.sort_by(& &1.value)
    |> Enum.map(& &1.label)
  end

  defp generator_data_type(%Declaration{} = type) do
    encoding = value(type.definition, :encoding, %{})

    case value(type.definition, :base_type) do
      kind when kind in [:float, "float"] ->
        "float"

      kind when kind in [:boolean, "boolean"] ->
        "boolean"

      kind when kind in [:string, "string"] ->
        "string"

      kind when kind in [:binary, "binary"] ->
        "binary"

      kind when kind in [:integer, :enumerated, "integer", "enumerated"] ->
        if(value(encoding, :signed, false), do: "int", else: "uint")

      _other ->
        "float"
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp get_float_range(limits, item_name) do
    case range_from_limits(limits) do
      {:ok, range} -> range
      :error -> infer_float_range(item_name)
    end
  end

  defp range_from_limits(limits) do
    min_from_limits = limits["red_low"] || limits["yellow_low"]
    max_from_limits = limits["red_high"] || limits["yellow_high"]

    if min_from_limits && max_from_limits do
      {:ok, {min_from_limits, max_from_limits}}
    else
      :error
    end
  end

  defp infer_float_range(name) do
    Enum.find_value(@float_range_keywords, fn {keywords, range} ->
      if String.contains?(name, keywords), do: range, else: nil
    end) || {0.0, 100.0}
  end

  defp counter_name?(name) do
    String.contains?(name, ["count", "uptime", "seq"])
  end

  defp get_int_range(limits, bit_size, signed) do
    case int_range_from_limits(limits) do
      {:ok, range} -> range
      :error -> default_int_range(bit_size, signed)
    end
  end

  defp int_range_from_limits(limits) do
    min_from_limits = limits["red_low"] || limits["yellow_low"]
    max_from_limits = limits["red_high"] || limits["yellow_high"]

    if min_from_limits && max_from_limits do
      {:ok, {round(min_from_limits), round(max_from_limits)}}
    else
      :error
    end
  end

  defp default_int_range(bit_size, signed) when is_integer(bit_size) and bit_size > 0 do
    max_val = (1 <<< bit_size) - 1

    if signed do
      half = div(max_val + 1, 2)
      {-half, half - 1}
    else
      {0, max_val}
    end
  end

  defp default_int_range(_bit_size, true), do: {-1000, 1000}
  defp default_int_range(_bit_size, false), do: {0, 1000}
end
