defmodule Cadence.Simulator.Providers.ScenarioProvider do
  @moduledoc """
  YAML-driven scenario provider for deterministic testing.

  This provider executes scenarios defined in YAML files, allowing precise
  control over telemetry values at specific simulation steps. It's designed
  for testing alarm triggering, limit violations, and operator responses.

  ## Usage

      config = %{scenario_path: "priv/scenarios/alarm_test.yaml"}
      {:ok, state} = ScenarioProvider.init(config)

      # Or with inline scenario
      config = %{scenario: %{name: "Test", baseline: %{...}, timeline: [...]}}
      {:ok, state} = ScenarioProvider.init(config)

  ## Scenario Execution

  The provider:
  1. Starts with baseline values for all telemetry items
  2. Applies injections from timeline events at the specified steps
  3. Maintains injected values until overwritten or scenario ends
  4. Signals completion when an `end: true` event is reached

  ## Injection Patterns

  Besides static values, scenarios support patterns:

      inject:
        HEALTH.cpu_temp:
          type: ramp
          from: 25.0
          to: 95.0
          steps: 20
          noise: 1.0

  Pattern types:
  - `ramp` - Linear interpolation from `from` to `to` over `steps`
  - `spike` - Quick rise to peak and fall back
  - `sine` - Sinusoidal variation
  """

  @behaviour Cadence.Simulator.DynamicsProvider

  alias Cadence.Simulator.Scenario.Parser

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
      state = %__MODULE__{
        scenario: scenario,
        current_step: 0,
        baseline_values: scenario.baseline,
        active_injections: %{},
        pattern_states: %{},
        completed: false
      }

      Logger.info("ScenarioProvider initialized: #{scenario.name}")
      {:ok, state}
    end
  end

  @impl true
  def generate_values(%{completed: true} = state, _step) do
    # Scenario is complete, return baseline values
    {:ok, state.baseline_values, state}
  end

  def generate_values(state, step) do
    # Process any timeline events that should trigger at this step
    state = process_timeline_events(state, step)

    # Generate current values by merging baseline with active injections
    values = compute_current_values(state, step)

    new_state = %{state | current_step: step}

    {:ok, values, new_state}
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

  # Load scenario from file path or inline config
  defp load_scenario(%{scenario_path: path}) when is_binary(path) do
    Parser.parse_file(path)
  end

  defp load_scenario(%{scenario: scenario}) when is_map(scenario) do
    # Inline scenario provided
    {:ok, normalize_scenario(scenario)}
  end

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

  # Process timeline events that trigger at the current step
  defp process_timeline_events(state, step) do
    events_at_step =
      state.scenario.timeline
      |> Enum.filter(fn event -> event.step == step end)

    Enum.reduce(events_at_step, state, fn event, acc ->
      apply_timeline_event(acc, event, step)
    end)
  end

  defp apply_timeline_event(state, %{end: true} = event, _step) do
    Logger.info("Scenario '#{state.scenario.name}' completed at step #{event.step}")
    %{state | completed: true}
  end

  defp apply_timeline_event(state, event, step) do
    # Apply injections from this event
    case event.inject do
      nil ->
        state

      injections when is_map(injections) ->
        new_active = Map.merge(state.active_injections, injections)

        # Initialize pattern states for any new patterns
        new_pattern_states =
          injections
          |> Enum.filter(fn {_k, v} -> is_map(v) and Map.has_key?(v, :type) end)
          |> Enum.map(fn {k, pattern} ->
            {k, %{start_step: step, pattern: pattern}}
          end)
          |> Map.new()
          |> Map.merge(state.pattern_states)

        if event.description do
          Logger.info("Step #{step}: #{event.description}")
        end

        %{state | active_injections: new_active, pattern_states: new_pattern_states}
    end
  end

  # Compute current values by merging baseline with injections
  defp compute_current_values(state, step) do
    state.baseline_values
    |> Map.merge(resolve_injections(state, step))
  end

  # Resolve injection values (including patterns)
  defp resolve_injections(state, step) do
    state.active_injections
    |> Enum.map(fn {key, value} ->
      resolved = resolve_injection_value(key, value, state, step)
      {key, resolved}
    end)
    |> Map.new()
  end

  # Static value
  defp resolve_injection_value(_key, value, _state, _step)
       when is_number(value) or is_binary(value) do
    value
  end

  # Pattern-based value
  defp resolve_injection_value(key, %{type: type} = pattern, state, step) do
    case Map.get(state.pattern_states, key) do
      nil ->
        # No pattern state, use from value
        pattern.from || 0.0

      %{start_step: start_step} ->
        pattern_step = step - start_step
        compute_pattern_value(type, pattern, pattern_step)
    end
  end

  defp resolve_injection_value(_key, value, _state, _step) do
    # Unknown format, return as-is
    value
  end

  # Compute pattern values
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

    # Spike goes up in first half, down in second half
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

  defp compute_pattern_value(unknown, _pattern, _pattern_step) do
    Logger.warning("Unknown pattern type: #{inspect(unknown)}")
    0.0
  end

  defp random_noise(amplitude) when amplitude == 0.0, do: 0.0

  defp random_noise(amplitude) do
    (:rand.uniform() - 0.5) * 2.0 * amplitude
  end
end
