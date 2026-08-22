defmodule CadenceSimulator.Providers.ScenarioProvider do
  @moduledoc """
  YAML-driven deterministic scenario provider.
  """

  @behaviour CadenceSimulator.DynamicsProvider

  alias CadenceSimulator.Scenario.Parser

  require Logger

  defstruct [
    :scenario,
    :current_step,
    :baseline_values,
    :active_injections,
    :pattern_states,
    :completed
  ]

  @impl true
  def init(config) do
    with {:ok, scenario} <- load_scenario(config) do
      Logger.info("ScenarioProvider initialized: #{scenario.name}")

      {:ok,
       %__MODULE__{
         scenario: scenario,
         current_step: 0,
         baseline_values: scenario.baseline,
         active_injections: %{},
         pattern_states: %{},
         completed: false
       }}
    end
  end

  @impl true
  def generate_values(%{completed: true} = state, _step) do
    {:ok, state.baseline_values, state}
  end

  def generate_values(state, step) do
    state = process_timeline_events(state, step)
    values = compute_current_values(state, step)
    {:ok, values, %{state | current_step: step}}
  end

  @impl true
  def status(state) do
    %{
      provider: "ScenarioProvider",
      scenario_name: state.scenario.name,
      current_step: state.current_step,
      completed: state.completed,
      active_injections: Map.keys(state.active_injections),
      target_id: state.scenario.target_id
    }
  end

  @impl true
  def parallel_safe?(_config), do: false

  defp load_scenario(%{scenario_path: path}) when is_binary(path), do: Parser.parse_file(path)

  defp load_scenario(%{scenario: scenario}) when is_map(scenario),
    do: {:ok, normalize_scenario(scenario)}

  defp load_scenario(config) do
    {:error, {:invalid_config, "Expected :scenario_path or :scenario key", config}}
  end

  defp normalize_scenario(scenario) do
    %{
      version: Map.get(scenario, :version, "1.0"),
      name: Map.get(scenario, :name, "Inline Scenario"),
      description: Map.get(scenario, :description),
      target_id: Map.get(scenario, :target_id, "SIM-1"),
      step_rate_hz: Map.get(scenario, :step_rate_hz, 1.0),
      baseline: Map.get(scenario, :baseline, %{}),
      timeline: Map.get(scenario, :timeline, [])
    }
  end

  defp process_timeline_events(state, step) do
    state.scenario.timeline
    |> Enum.filter(fn event -> event.step == step end)
    |> Enum.reduce(state, fn event, acc -> apply_timeline_event(acc, event, step) end)
  end

  defp apply_timeline_event(state, %{end: true} = event, _step) do
    Logger.info("Scenario '#{state.scenario.name}' completed at step #{event.step}")
    %{state | completed: true}
  end

  defp apply_timeline_event(state, event, step) do
    case event.inject do
      nil ->
        state

      injections when is_map(injections) ->
        new_pattern_states =
          injections
          |> Enum.filter(fn {_k, v} -> is_map(v) and Map.has_key?(v, :type) end)
          |> Enum.map(fn {k, pattern} -> {k, %{start_step: step, pattern: pattern}} end)
          |> Map.new()
          |> Map.merge(state.pattern_states)

        if event.description do
          Logger.info("Step #{step}: #{event.description}")
        end

        %{
          state
          | active_injections: Map.merge(state.active_injections, injections),
            pattern_states: new_pattern_states
        }
    end
  end

  defp compute_current_values(state, step) do
    state.baseline_values
    |> Map.merge(resolve_injections(state, step))
  end

  defp resolve_injections(state, step) do
    state.active_injections
    |> Enum.map(fn {key, value} ->
      {key, resolve_injection_value(key, value, state, step)}
    end)
    |> Map.new()
  end

  defp resolve_injection_value(_key, value, _state, _step)
       when is_number(value) or is_binary(value) do
    value
  end

  defp resolve_injection_value(key, %{type: type} = pattern, state, step) do
    case Map.get(state.pattern_states, key) do
      nil ->
        pattern.from || 0.0

      %{start_step: start_step} ->
        compute_pattern_value(type, pattern, step - start_step)
    end
  end

  defp resolve_injection_value(_key, value, _state, _step), do: value

  defp compute_pattern_value(:ramp, pattern, pattern_step) do
    from = pattern.from || 0.0
    to = pattern.to || from
    steps = pattern.steps || 10
    noise = pattern.noise || 0.0

    progress = min(1.0, pattern_step / steps)
    base_value = from + (to - from) * progress
    base_value + random_noise(noise)
  end

  defp compute_pattern_value(:spike, pattern, pattern_step) do
    from = pattern.from || 0.0
    to = pattern.to || from
    steps = pattern.steps || 10
    noise = pattern.noise || 0.0
    half_steps = steps / 2

    progress =
      if pattern_step <= half_steps do
        pattern_step / half_steps
      else
        1.0 - (pattern_step - half_steps) / half_steps
      end

    progress = max(0.0, min(1.0, progress))
    base_value = from + (to - from) * progress
    base_value + random_noise(noise)
  end

  defp compute_pattern_value(:sine, pattern, pattern_step) do
    from = pattern.from || 0.0
    to = pattern.to || from
    steps = pattern.steps || 10
    noise = pattern.noise || 0.0
    amplitude = (to - from) / 2
    center = from + amplitude
    base_value = center + amplitude * :math.sin(pattern_step / steps * 2 * :math.pi())
    base_value + random_noise(noise)
  end

  defp compute_pattern_value(_, pattern, _pattern_step), do: pattern.from || 0.0

  defp random_noise(amplitude), do: (:rand.uniform() - 0.5) * 2.0 * amplitude
end
