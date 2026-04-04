defmodule CadenceSimulator.Providers.DatabaseDynamics do
  @moduledoc """
  Generates telemetry values from a YAML telemetry definition set.

  Unlike `BasicDynamics`, this provider derives point names and value-generation
  strategies directly from the same dev-format YAML used by the simulator
  encoder.
  """

  @behaviour CadenceSimulator.DynamicsProvider

  import Bitwise

  require Logger

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
    :packets,
    :packet_count,
    :item_count,
    :noise_amplitude
  ]

  @impl true
  def init(config) do
    definitions_path = Map.get(config, :definitions_path)
    definitions_content = Map.get(config, :definitions_content)

    result =
      cond do
        is_binary(definitions_content) ->
          YamlElixir.read_from_string(definitions_content)

        is_binary(definitions_path) ->
          with {:ok, content} <- File.read(definitions_path) do
            YamlElixir.read_from_string(content)
          end

        true ->
          {:error, :no_definitions_provided}
      end

    case result do
      {:ok, parsed} ->
        {packets, item_count} = extract_definitions(parsed)

        Logger.info("""
        DatabaseDynamics initialized:
          packets: #{length(packets)}
          items: #{item_count}
        """)

        {:ok,
         %__MODULE__{
           packets: packets,
           packet_count: length(packets),
           item_count: item_count,
           noise_amplitude: Map.get(config, :noise_amplitude, @default_noise_amplitude)
         }}

      {:error, reason} ->
        {:error, {:failed_to_load_definitions, reason}}
    end
  end

  @impl true
  def generate_values(state, step) do
    {:ok, build_flat_values(state.packets, step, state.noise_amplitude), state}
  end

  @impl true
  def generate_packet_values(state, step) do
    {:ok, build_packet_values(state.packets, step, state.noise_amplitude), state}
  end

  @impl true
  def status(state) do
    %{
      provider: "DatabaseDynamics",
      packet_count: state.packet_count,
      item_count: state.item_count,
      noise_amplitude: state.noise_amplitude
    }
  end

  @impl true
  def parallel_safe?(_config), do: true

  defp extract_definitions(parsed) do
    packets = parsed["packets"] || []

    Enum.reduce(packets, {[], 0}, fn packet_data, {pkts, item_count} ->
      packet_name = packet_data["name"]

      packet_items =
        (packet_data["items"] || [])
        |> Enum.with_index()
        |> Enum.map(fn {item_data, index} -> build_item_spec(packet_name, item_data, index) end)
        |> Enum.sort_by(fn item -> {item.bit_offset, item.sort_index} end)

      {
        [
          %{
            name: packet_name,
            apid: packet_data["apid"],
            description: packet_data["description"],
            items: packet_items
          }
          | pkts
        ],
        item_count + length(packet_items)
      }
    end)
    |> then(fn {packet_defs, item_count} -> {Enum.reverse(packet_defs), item_count} end)
  end

  defp build_item_spec(packet_name, item_data, sort_index) do
    item_name = item_data["name"]
    qualified_name = "#{packet_name}.#{item_name}"
    phase = :erlang.phash2(item_name) / 1000.0

    %{
      bit_offset: item_data["bit_offset"] || 0,
      name: item_name,
      qualified_name: qualified_name,
      sort_index: sort_index,
      generator: build_generator(packet_name, item_name, item_data, phase)
    }
  end

  defp build_packet_values(packet_specs, step, noise_amplitude) do
    Enum.map(packet_specs, fn %{name: packet_name, items: item_specs} ->
      values =
        Enum.map(item_specs, fn %{generator: generator} ->
          generate_item_value(generator, step, noise_amplitude)
        end)

      {packet_name, values}
    end)
  end

  defp build_flat_values(packet_specs, step, noise_amplitude) do
    Enum.reduce(packet_specs, %{}, fn %{items: item_specs}, acc ->
      Enum.reduce(item_specs, acc, fn %{qualified_name: qualified_name, generator: generator},
                                      item_acc ->
        Map.put(item_acc, qualified_name, generate_item_value(generator, step, noise_amplitude))
      end)
    end)
  end

  defp build_generator(packet_name, item_name, item_data, phase) do
    conversion = item_data["conversion"]
    limits = item_data["limits"] || %{}
    bit_size = item_data["bit_size"]

    case sorted_state_values(conversion) do
      state_values when is_list(state_values) ->
        {:state_cycle, List.to_tuple(state_values), length(state_values)}

      _ ->
        build_typed_generator(
          packet_name,
          item_name,
          item_data["data_type"],
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

  defp sorted_state_values(%{"type" => "state_table", "states" => states}) when is_map(states) do
    states
    |> Map.values()
    |> Enum.sort()
  end

  defp sorted_state_values(_), do: nil

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
