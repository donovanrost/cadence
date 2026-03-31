defmodule CadenceSimulator.Providers.BasicDynamics do
  @moduledoc """
  Basic simulator dynamics with sinusoidal telemetry patterns and light noise.
  """

  @behaviour CadenceSimulator.DynamicsProvider

  require Logger

  defstruct [
    :packets,
    :noise_amplitude
  ]

  @default_packets [:health, :attitude, :power]
  @default_noise_amplitude 1.0

  @impl true
  def init(config) do
    {:ok,
     %__MODULE__{
       packets: Map.get(config, :packets, @default_packets),
       noise_amplitude: Map.get(config, :noise_amplitude, @default_noise_amplitude)
     }}
  end

  @impl true
  def generate_values(state, step) do
    values =
      state.packets
      |> Enum.flat_map(fn packet_type ->
        generate_packet_values(packet_type, step, state.noise_amplitude)
      end)
      |> Map.new()

    {:ok, values, state}
  end

  @impl true
  def status(state) do
    %{
      provider: "BasicDynamics",
      packets: state.packets,
      noise_amplitude: state.noise_amplitude
    }
  end

  @impl true
  def parallel_safe?(_config), do: true

  defp generate_packet_values(:health, step, noise_amp) do
    base_temp = 20.0
    temp_variation = :math.sin(step / 10.0) * 5.0

    [
      {"HEALTH.cpu_temp", base_temp + temp_variation + random_noise(1.0 * noise_amp)},
      {"HEALTH.battery_voltage",
       14.5 + :math.sin(step / 20.0) * 0.5 + random_noise(0.1 * noise_amp)},
      {"HEALTH.battery_current", 2.3 + random_noise(0.2 * noise_amp)},
      {"HEALTH.battery_percentage", min(100.0, 75.0 + :math.sin(step / 50.0) * 20.0)},
      {"HEALTH.uptime_seconds", step * 10},
      {"HEALTH.memory_used_mb", 512 + :rand.uniform(100)}
    ]
  end

  defp generate_packet_values(:attitude, step, noise_amp) do
    [
      {"ATTITUDE.roll", :math.sin(step / 30.0) * 10.0 + random_noise(0.5 * noise_amp)},
      {"ATTITUDE.pitch", :math.cos(step / 25.0) * 8.0 + random_noise(0.5 * noise_amp)},
      {"ATTITUDE.yaw", :math.sin(step / 40.0) * 15.0 + random_noise(0.5 * noise_amp)},
      {"ATTITUDE.roll_rate", :math.cos(step / 15.0) * 0.1 + random_noise(0.01 * noise_amp)},
      {"ATTITUDE.pitch_rate", :math.sin(step / 20.0) * 0.1 + random_noise(0.01 * noise_amp)},
      {"ATTITUDE.yaw_rate", :math.cos(step / 18.0) * 0.1 + random_noise(0.01 * noise_amp)}
    ]
  end

  defp generate_packet_values(:power, step, noise_amp) do
    solar_panel_angle = rem(step, 360)
    solar_efficiency = max(0.0, :math.cos(solar_panel_angle * :math.pi() / 180.0))

    power_mode =
      cond do
        solar_efficiency > 0.7 -> "HIGH_POWER"
        solar_efficiency > 0.1 -> "NOMINAL"
        true -> "OFF"
      end

    [
      {"POWER.solar_panel_voltage", 28.0 * solar_efficiency + random_noise(0.5 * noise_amp)},
      {"POWER.solar_panel_current", 5.0 * solar_efficiency + random_noise(0.2 * noise_amp)},
      {"POWER.bus_voltage", 27.5 + random_noise(0.3 * noise_amp)},
      {"POWER.bus_current", 3.2 + random_noise(0.5 * noise_amp)},
      {"POWER.power_mode", power_mode}
    ]
  end

  defp generate_packet_values(unknown_packet, _step, _noise_amp) do
    Logger.warning("BasicDynamics: unknown packet type #{inspect(unknown_packet)}")
    []
  end

  defp random_noise(amplitude) do
    (:rand.uniform() - 0.5) * 2.0 * amplitude
  end
end
