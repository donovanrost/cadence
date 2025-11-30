defmodule Cadence.Simulator.Providers.DatabaseDynamics do
  @moduledoc """
  Dynamics provider that generates telemetry values based on YAML database definitions.

  Unlike BasicDynamics which uses hardcoded packet/item names, this provider reads
  the packet definitions from the YAML database and generates appropriate values
  for each item based on its data type and configuration.

  ## Value Generation Strategies

  Values are generated based on the item's data type:

  - **float** - Sinusoidal variation with configurable range
  - **uint/int** - Counter or random within valid range
  - **boolean** - Random true/false
  - **string** - Static placeholder or cycling values
  - **binary** - Random bytes

  Items with state table conversions cycle through their defined states.

  Items with limits use those limits to bound the generated range.

  ## Configuration

      config = %{
        definitions_path: "path/to/database.yaml",
        noise_amplitude: 1.0  # Optional, default 1.0
      }
      {:ok, state} = DatabaseDynamics.init(config)

  ## Example

  Given a YAML with:
      packets:
        - name: HK
          items:
            - name: cpu_temp
              data_type: float
              limits:
                yellow_low: -20.0
                yellow_high: 60.0
            - name: sc_mode
              data_type: uint
              conversion:
                type: state_table
                states:
                  0: "BOOT"
                  1: "SAFE"
                  2: "NOMINAL"

  The provider generates:
      %{
        "HK.cpu_temp" => 25.5,      # Float within limits range
        "HK.sc_mode" => "NOMINAL"   # Cycles through state values
      }
  """

  @behaviour Cadence.Simulator.DynamicsProvider

  require Logger

  defstruct [
    :packets,
    :items,
    :noise_amplitude,
    :state_indices
  ]

  @default_noise_amplitude 1.0

  @impl true
  def init(config) do
    definitions_path = Map.get(config, :definitions_path)
    definitions_content = Map.get(config, :definitions_content)

    result =
      cond do
        definitions_content ->
          YamlElixir.read_from_string(definitions_content)

        definitions_path ->
          with {:ok, content} <- File.read(definitions_path) do
            YamlElixir.read_from_string(content)
          end

        true ->
          {:error, :no_definitions_provided}
      end

    case result do
      {:ok, parsed} ->
        {packets, items} = extract_definitions(parsed)

        state = %__MODULE__{
          packets: packets,
          items: items,
          noise_amplitude: Map.get(config, :noise_amplitude, @default_noise_amplitude),
          state_indices: %{}
        }

        Logger.info("""
        DatabaseDynamics initialized:
          packets: #{length(packets)}
          items: #{length(items)}
        """)

        {:ok, state}

      {:error, reason} ->
        {:error, {:failed_to_load_definitions, reason}}
    end
  end

  @impl true
  def generate_values(state, step) do
    {values, state_indices} =
      state.items
      |> Enum.reduce({%{}, state.state_indices}, fn item, {vals, indices} ->
        {value, new_indices} = generate_item_value(item, step, state.noise_amplitude, indices)
        qualified_name = "#{item.packet_name}.#{item.name}"
        {Map.put(vals, qualified_name, value), new_indices}
      end)

    {:ok, values, %{state | state_indices: state_indices}}
  end

  @impl true
  def status(state) do
    %{
      provider: "DatabaseDynamics",
      packet_count: length(state.packets),
      item_count: length(state.items),
      noise_amplitude: state.noise_amplitude
    }
  end

  # ============================================================================
  # Definition Extraction
  # ============================================================================

  defp extract_definitions(parsed) do
    packets = parsed["packets"] || []

    {packet_defs, item_defs} =
      Enum.reduce(packets, {[], []}, fn packet_data, {pkts, items} ->
        packet_name = packet_data["name"]

        packet_def = %{
          name: packet_name,
          apid: packet_data["apid"],
          description: packet_data["description"]
        }

        packet_items =
          (packet_data["items"] || [])
          |> Enum.map(fn item_data ->
            %{
              name: item_data["name"],
              packet_name: packet_name,
              data_type: item_data["data_type"],
              bit_size: item_data["bit_size"],
              conversion: item_data["conversion"],
              limits: item_data["limits"],
              units: item_data["units"],
              description: item_data["description"]
            }
          end)

        {[packet_def | pkts], items ++ packet_items}
      end)

    {Enum.reverse(packet_defs), item_defs}
  end

  # ============================================================================
  # Value Generation
  # ============================================================================

  defp generate_item_value(item, step, noise_amp, state_indices) do
    qualified_name = "#{item.packet_name}.#{item.name}"

    # Check for state table conversion first
    case item.conversion do
      %{"type" => "state_table", "states" => states} when is_map(states) ->
        generate_state_value(qualified_name, states, state_indices, step)

      _ ->
        # Generate based on data type
        value = generate_typed_value(item, step, noise_amp)
        {value, state_indices}
    end
  end

  defp generate_state_value(qualified_name, states, state_indices, step) do
    # Get sorted state values for consistent cycling
    state_values = states |> Map.values() |> Enum.sort()

    # Cycle through states, changing every ~10 steps
    cycle_rate = 10
    current_index = rem(div(step, cycle_rate), length(state_values))

    value = Enum.at(state_values, current_index)
    new_indices = Map.put(state_indices, qualified_name, current_index)

    {value, new_indices}
  end

  defp generate_typed_value(item, step, noise_amp) do
    data_type = item.data_type
    limits = item.limits || %{}

    case data_type do
      "float" ->
        generate_float(item, step, noise_amp, limits)

      "uint" ->
        generate_uint(item, step, limits)

      "int" ->
        generate_int(item, step, limits)

      "boolean" ->
        # Toggle every 20 steps
        rem(div(step, 20), 2) == 0

      "string" ->
        # Return a placeholder string
        "#{item.packet_name}_#{item.name}_v#{step}"

      "binary" ->
        # Generate random bytes based on bit_size
        byte_size = div(item.bit_size || 8, 8)
        :crypto.strong_rand_bytes(byte_size)

      _ ->
        # Default to float-like behavior
        generate_float(item, step, noise_amp, limits)
    end
  end

  defp generate_float(item, step, noise_amp, limits) do
    # Determine range from limits or use sensible defaults
    {min_val, max_val} = get_float_range(limits, item)

    # Generate sinusoidal value within range
    mid = (min_val + max_val) / 2
    amplitude = (max_val - min_val) / 2 * 0.8  # Use 80% of range

    # Use item name hash to create different phases for different items
    phase = :erlang.phash2(item.name) / 1000.0

    base_value = mid + amplitude * :math.sin(step / 20.0 + phase)

    # Add noise
    noise = (0.5 - :rand.uniform()) * noise_amp * amplitude * 0.1
    base_value + noise
  end

  defp get_float_range(limits, item) do
    # Try to extract range from limits
    min_from_limits =
      limits["red_low"] || limits["yellow_low"]

    max_from_limits =
      limits["red_high"] || limits["yellow_high"]

    cond do
      min_from_limits && max_from_limits ->
        {min_from_limits, max_from_limits}

      # Guess based on common patterns
      String.contains?(item.name, "temp") ->
        {-40.0, 85.0}

      String.contains?(item.name, "voltage") ->
        {0.0, 50.0}

      String.contains?(item.name, "current") ->
        {-10.0, 10.0}

      String.contains?(item.name, "percent") || String.contains?(item.name, "soc") ->
        {0.0, 100.0}

      String.contains?(item.name, "rate") ->
        {-5.0, 5.0}

      String.contains?(item.name, "angle") || String.contains?(item.name, "roll") ||
          String.contains?(item.name, "pitch") || String.contains?(item.name, "yaw") ->
        {-180.0, 180.0}

      true ->
        {0.0, 100.0}
    end
  end

  defp generate_uint(item, step, limits) do
    {min_val, max_val} = get_int_range(limits, item, false)

    # For counters, increment; for others, sinusoidal pattern
    if String.contains?(item.name, "count") || String.contains?(item.name, "uptime") ||
         String.contains?(item.name, "seq") do
      # Counter - just return step or step mod max
      rem(step, max_val + 1)
    else
      # Sinusoidal within range
      mid = (min_val + max_val) / 2
      amplitude = (max_val - min_val) / 2 * 0.8
      phase = :erlang.phash2(item.name) / 1000.0

      value = mid + amplitude * :math.sin(step / 15.0 + phase)
      round(value) |> max(min_val) |> min(max_val)
    end
  end

  defp generate_int(item, step, limits) do
    {min_val, max_val} = get_int_range(limits, item, true)

    mid = (min_val + max_val) / 2
    amplitude = (max_val - min_val) / 2 * 0.8
    phase = :erlang.phash2(item.name) / 1000.0

    value = mid + amplitude * :math.sin(step / 15.0 + phase)
    round(value) |> max(min_val) |> min(max_val)
  end

  defp get_int_range(limits, item, signed) do
    min_from_limits = limits["red_low"] || limits["yellow_low"]
    max_from_limits = limits["red_high"] || limits["yellow_high"]

    cond do
      min_from_limits && max_from_limits ->
        {round(min_from_limits), round(max_from_limits)}

      # Use bit_size to determine max
      item.bit_size ->
        max_val = round(:math.pow(2, item.bit_size)) - 1

        if signed do
          half = div(max_val + 1, 2)
          {-half, half - 1}
        else
          {0, max_val}
        end

      true ->
        if signed, do: {-1000, 1000}, else: {0, 1000}
    end
  end
end
