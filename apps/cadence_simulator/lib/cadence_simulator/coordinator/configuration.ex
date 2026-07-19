defmodule CadenceSimulator.Coordinator.Configuration do
  @moduledoc false

  require Logger

  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias CadenceSimulator.PacketEncoder
  alias CadenceSimulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}

  @default_generator_count System.schedulers_online()
  @default_metrics_sample_rate 100
  @default_in_flight_multiplier 4
  @default_dispatch_batch_floor 4
  @default_dispatch_batch_ceiling 32

  def determine_provider(opts) do
    cond do
      scenario_path = Keyword.get(opts, :scenario_path) ->
        {ScenarioProvider, %{scenario_path: scenario_path}}

      scenario = Keyword.get(opts, :scenario) ->
        {ScenarioProvider, %{scenario: scenario}}

      provider = Keyword.get(opts, :provider) ->
        {provider, provider_config(provider, opts)}

      true ->
        {BasicDynamics, Keyword.get(opts, :provider_config, %{})}
    end
  end

  def require_encoder(opts) do
    cond do
      definitions_content = Keyword.get(opts, :definitions_content) ->
        PacketEncoder.load_string(definitions_content)

      definitions_path = Keyword.get(opts, :definitions_path) ->
        PacketEncoder.load(definitions_path)

      true ->
        {:error, :missing_definitions}
    end
  end

  def normalize_frame(nil), do: nil

  def normalize_frame(%{format: :tm, frame_size: frame_size} = frame)
      when is_integer(frame_size) do
    %{
      format: :tm,
      frame_size: frame_size,
      scid: Map.get(frame, :scid, 0),
      vcid: Map.get(frame, :vcid, 0)
    }
  end

  def normalize_frame(%{"format" => "tm", "frame_size" => frame_size} = frame)
      when is_integer(frame_size) do
    %{
      format: :tm,
      frame_size: frame_size,
      scid: Map.get(frame, "scid", 0),
      vcid: Map.get(frame, "vcid", 0)
    }
  end

  def normalize_frame(other) do
    raise ArgumentError, "unsupported simulator frame config: #{inspect(other)}"
  end

  def init_frame_state(nil), do: {:ok, nil}
  def init_frame_state(%{format: :tm}), do: Segmentation.init([])

  def normalize_parallel_mode(:parallel, _provider_module, _provider_config, generator_count)
      when generator_count <= 1 do
    :sequential
  end

  def normalize_parallel_mode(:parallel, provider_module, provider_config, _generator_count) do
    if provider_parallel_safe?(provider_module, provider_config) do
      :parallel
    else
      Logger.warning(
        "Provider #{inspect(provider_module)} is not parallel-safe; falling back to sequential mode"
      )

      :sequential
    end
  end

  def normalize_parallel_mode(mode, _provider_module, _provider_config, _generator_count),
    do: mode

  def parallel_delivery_mode(:parallel, %{format: :tm}, opts) do
    if Keyword.get(opts, :tm_parallel_framing, false),
      do: :ordered_frame_plan,
      else: :ordered_framer
  end

  def parallel_delivery_mode(:parallel, _frame, _opts), do: :send_buffer
  def parallel_delivery_mode(_mode, _frame, _opts), do: nil

  def packet_value_provider?(provider_module) do
    function_exported?(provider_module, :generate_packet_values, 2)
  end

  def schedule_config(rate_hz) when rate_hz <= 1000 do
    {max(1, trunc(1000 / rate_hz)), 1}
  end

  def schedule_config(rate_hz), do: {1, ceil(rate_hz / 1000)}

  def normalize_generator_count(nil), do: @default_generator_count
  def normalize_generator_count(count) when is_integer(count) and count > 0, do: count
  def normalize_generator_count(_count), do: 1

  def normalize_metrics_sample_rate(nil), do: @default_metrics_sample_rate
  def normalize_metrics_sample_rate(rate) when is_integer(rate) and rate >= 0, do: rate
  def normalize_metrics_sample_rate(_rate), do: @default_metrics_sample_rate

  def normalize_max_in_flight_steps(opts, generator_count, steps_per_tick) do
    case Keyword.get(opts, :max_in_flight_steps) do
      value when is_integer(value) and value > 0 ->
        value

      _ ->
        max(steps_per_tick * @default_in_flight_multiplier, generator_count * 2)
    end
  end

  def normalize_send_buffer_backpressure(opts, generator_count, send_batch_size) do
    case Keyword.get(opts, :max_send_buffer_queue) do
      value when is_integer(value) and value > 0 ->
        {:queue, value, nil}

      _ ->
        max_backlog_bytes =
          max(
            send_batch_size * max(generator_count, 1),
            send_batch_size * @default_in_flight_multiplier
          )

        {:bytes, nil, max_backlog_bytes}
    end
  end

  def normalize_dispatch_batch_floor(opts) do
    case Keyword.get(opts, :dispatch_batch_floor) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_dispatch_batch_floor
    end
  end

  def normalize_dispatch_batch_ceiling(opts, dispatch_batch_floor, steps_per_tick) do
    case Keyword.get(opts, :dispatch_batch_ceiling) do
      value when is_integer(value) and value >= dispatch_batch_floor ->
        value

      _ ->
        max(@default_dispatch_batch_ceiling, max(dispatch_batch_floor, steps_per_tick * 2))
    end
  end

  defp provider_config(DatabaseDynamics, opts) do
    %{
      definitions_path: Keyword.get(opts, :definitions_path),
      definitions_content: Keyword.get(opts, :definitions_content),
      noise_amplitude: Keyword.get(opts, :noise_amplitude, 1.0)
    }
  end

  defp provider_config(ScenarioProvider, opts) do
    cond do
      scenario_path = Keyword.get(opts, :scenario_path) ->
        %{scenario_path: scenario_path}

      scenario = Keyword.get(opts, :scenario) ->
        %{scenario: scenario}

      true ->
        Keyword.get(opts, :provider_config, %{})
    end
  end

  defp provider_config(_provider, opts), do: Keyword.get(opts, :provider_config, %{})

  defp provider_parallel_safe?(provider_module, provider_config) do
    if function_exported?(provider_module, :parallel_safe?, 1) do
      provider_module.parallel_safe?(provider_config)
    else
      provider_module != ScenarioProvider
    end
  end
end
