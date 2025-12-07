defmodule Cadence.Procedures.Dag.Validator do
  @moduledoc """
  Validates DAG (Directed Acyclic Graph) procedure definitions.

  Ensures:
  - No cycles exist in the dependency graph
  - All referenced dependencies exist
  - Step names are unique
  - Required step fields are present
  """

  @type step_name :: String.t()
  @type step_def :: map()
  @type steps :: %{step_name() => step_def()}
  @type validation_error :: String.t()

  @doc """
  Validates a DAG procedure definition.

  Returns `:ok` or `{:error, reasons}` with a list of validation errors.

  ## Example

      iex> Validator.validate(%{
      ...>   "step_a" => %{"type" => "log", "message" => "Hello"},
      ...>   "step_b" => %{"type" => "log", "message" => "World", "depends_on" => ["step_a"]}
      ...> })
      :ok

      iex> Validator.validate(%{
      ...>   "step_a" => %{"type" => "log", "depends_on" => ["step_b"]},
      ...>   "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      ...> })
      {:error, ["Cycle detected: step_a -> step_b -> step_a"]}
  """
  @spec validate(steps()) :: :ok | {:error, list(validation_error())}
  def validate(steps) when is_map(steps) do
    errors =
      []
      |> validate_step_names(steps)
      |> validate_step_definitions(steps)
      |> validate_dependencies_exist(steps)
      |> validate_no_cycles(steps)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def validate(_), do: {:error, ["Steps must be a map"]}

  @doc """
  Checks if a steps definition is in DAG format (map) vs linear format (list).
  """
  @spec is_dag_format?(map()) :: boolean()
  def is_dag_format?(%{"steps" => steps}) when is_map(steps), do: true
  def is_dag_format?(_), do: false

  @doc """
  Returns the dependency graph as an adjacency list.

  The result maps each step to the list of steps it depends on.
  """
  @spec build_dependency_graph(steps()) :: %{step_name() => list(step_name())}
  def build_dependency_graph(steps) do
    Map.new(steps, fn {name, step} ->
      deps = get_dependencies(step)
      {name, deps}
    end)
  end

  @doc """
  Returns the reverse dependency graph (dependents).

  Maps each step to the list of steps that depend on it.
  """
  @spec build_dependents_graph(steps()) :: %{step_name() => list(step_name())}
  def build_dependents_graph(steps) do
    # Initialize all steps with empty lists
    initial = Map.new(Map.keys(steps), fn name -> {name, []} end)

    Enum.reduce(steps, initial, fn {name, step}, acc ->
      deps = get_dependencies(step)

      Enum.reduce(deps, acc, fn dep, inner_acc ->
        Map.update(inner_acc, dep, [name], fn existing -> [name | existing] end)
      end)
    end)
  end

  @doc """
  Returns steps with no dependencies (root nodes).
  """
  @spec find_root_steps(steps()) :: list(step_name())
  def find_root_steps(steps) do
    steps
    |> Enum.filter(fn {_name, step} -> get_dependencies(step) == [] end)
    |> Enum.map(fn {name, _step} -> name end)
  end

  @doc """
  Returns steps that no other step depends on (terminal nodes).
  """
  @spec find_terminal_steps(steps()) :: list(step_name())
  def find_terminal_steps(steps) do
    dependents = build_dependents_graph(steps)

    dependents
    |> Enum.filter(fn {_name, deps} -> deps == [] end)
    |> Enum.map(fn {name, _} -> name end)
  end

  @doc """
  Returns a topological ordering of the steps.

  Returns `{:ok, ordered_names}` or `{:error, :cycle_detected}`.
  """
  @spec topological_sort(steps()) :: {:ok, list(step_name())} | {:error, :cycle_detected}
  def topological_sort(steps) do
    deps_graph = build_dependency_graph(steps)
    all_names = Map.keys(steps)

    # Kahn's algorithm
    # in_degree = number of dependencies for each step
    in_degree =
      Map.new(all_names, fn name ->
        {name, length(Map.get(deps_graph, name, []))}
      end)

    # Start with nodes that have no dependencies
    queue = Enum.filter(all_names, fn name -> Map.get(in_degree, name, 0) == 0 end)

    do_topological_sort(queue, [], in_degree, build_dependents_graph(steps), MapSet.new())
  end

  # ============================================================================
  # Private Validation Functions
  # ============================================================================

  defp validate_step_names(errors, steps) do
    names = Map.keys(steps)

    # Check for empty names
    empty_names = Enum.filter(names, fn name -> String.trim(name) == "" end)

    errors =
      if empty_names != [] do
        ["Step names cannot be empty" | errors]
      else
        errors
      end

    # Check for reserved names
    reserved = ~w(start end _layout)

    reserved_used =
      names
      |> Enum.filter(fn name -> String.downcase(name) in reserved end)

    if reserved_used != [] do
      ["Reserved step names used: #{Enum.join(reserved_used, ", ")}" | errors]
    else
      errors
    end
  end

  defp validate_step_definitions(errors, steps) do
    Enum.reduce(steps, errors, fn {name, step}, acc ->
      validate_step_definition(acc, name, step)
    end)
  end

  defp validate_step_definition(errors, name, step) when is_map(step) do
    errors =
      if Map.has_key?(step, "type") do
        errors
      else
        ["Step '#{name}' is missing required field 'type'" | errors]
      end

    # Validate depends_on is a list if present
    errors =
      case Map.get(step, "depends_on") do
        nil -> errors
        deps when is_list(deps) -> errors
        _ -> ["Step '#{name}' has invalid 'depends_on' (must be a list)" | errors]
      end

    # Validate type-specific required fields
    validate_step_type_fields(errors, name, step)
  end

  defp validate_step_type_fields(errors, name, %{"type" => "command"} = step) do
    if is_nil(step["name"]) or step["name"] == "" do
      ["Step '#{name}' (command): missing required field 'name'" | errors]
    else
      errors
    end
  end

  defp validate_step_type_fields(errors, name, %{"type" => "wait"} = step) do
    duration = step["duration"]

    cond do
      is_nil(duration) ->
        ["Step '#{name}' (wait): missing required field 'duration'" | errors]

      not is_integer(duration) and not is_binary(duration) ->
        ["Step '#{name}' (wait): 'duration' must be a number or string" | errors]

      true ->
        errors
    end
  end

  defp validate_step_type_fields(errors, name, %{"type" => "wait_for"} = step) do
    errors =
      if is_nil(step["item"]) or step["item"] == "" do
        ["Step '#{name}' (wait_for): missing required field 'item'" | errors]
      else
        errors
      end

    if is_nil(step["value"]) do
      ["Step '#{name}' (wait_for): missing required field 'value'" | errors]
    else
      errors
    end
  end

  defp validate_step_type_fields(errors, name, %{"type" => "check"} = step) do
    if is_nil(step["condition"]) or step["condition"] == "" do
      ["Step '#{name}' (check): missing required field 'condition'" | errors]
    else
      errors
    end
  end

  defp validate_step_type_fields(errors, name, %{"type" => "assert"} = step) do
    if is_nil(step["condition"]) or step["condition"] == "" do
      ["Step '#{name}' (assert): missing required field 'condition'" | errors]
    else
      errors
    end
  end

  defp validate_step_type_fields(errors, name, %{"type" => "set"} = step) do
    if is_nil(step["name"]) or step["name"] == "" do
      ["Step '#{name}' (set): missing required field 'name' (variable name)" | errors]
    else
      errors
    end
  end

  # log type - message is optional (will default to empty string)
  defp validate_step_type_fields(errors, _name, %{"type" => "log"}), do: errors

  # Unknown types - no additional validation
  defp validate_step_type_fields(errors, _name, _step), do: errors

  defp validate_step_definition(errors, name, _step) do
    ["Step '#{name}' must be a map" | errors]
  end

  defp validate_dependencies_exist(errors, steps) do
    all_names = MapSet.new(Map.keys(steps))

    Enum.reduce(steps, errors, fn {name, step}, acc ->
      deps = get_dependencies(step)

      missing =
        deps
        |> Enum.reject(fn dep -> MapSet.member?(all_names, dep) end)

      if missing != [] do
        ["Step '#{name}' depends on non-existent steps: #{Enum.join(missing, ", ")}" | acc]
      else
        acc
      end
    end)
  end

  defp validate_no_cycles(errors, steps) do
    case detect_cycle(steps) do
      nil -> errors
      cycle -> ["Cycle detected: #{Enum.join(cycle, " -> ")}" | errors]
    end
  end

  # ============================================================================
  # Cycle Detection (DFS-based)
  # ============================================================================

  defp detect_cycle(steps) do
    deps_graph = build_dependency_graph(steps)
    all_names = Map.keys(steps)

    # DFS with three states: unvisited, visiting (in current path), visited
    initial_state = %{
      visiting: MapSet.new(),
      visited: MapSet.new(),
      path: []
    }

    Enum.reduce_while(all_names, nil, fn name, _acc ->
      case dfs_detect_cycle(name, deps_graph, initial_state) do
        {:cycle, cycle} -> {:halt, cycle}
        {:ok, new_state} ->
          # Merge visited sets for next iteration
          {:cont, nil}
      end
    end)
  end

  defp dfs_detect_cycle(name, deps_graph, state) do
    cond do
      MapSet.member?(state.visiting, name) ->
        # Found a cycle - return the cycle path
        cycle_start = Enum.find_index(state.path, fn n -> n == name end)
        cycle = Enum.slice(state.path, cycle_start..-1//1) ++ [name]
        {:cycle, cycle}

      MapSet.member?(state.visited, name) ->
        # Already fully processed
        {:ok, state}

      true ->
        # Mark as visiting
        state = %{
          state
          | visiting: MapSet.put(state.visiting, name),
            path: state.path ++ [name]
        }

        # Visit all dependencies
        deps = Map.get(deps_graph, name, [])

        result =
          Enum.reduce_while(deps, {:ok, state}, fn dep, {:ok, acc_state} ->
            case dfs_detect_cycle(dep, deps_graph, acc_state) do
              {:cycle, _} = cycle -> {:halt, cycle}
              {:ok, new_state} -> {:cont, {:ok, new_state}}
            end
          end)

        case result do
          {:cycle, _} = cycle ->
            cycle

          {:ok, final_state} ->
            # Mark as fully visited
            {:ok,
             %{
               final_state
               | visiting: MapSet.delete(final_state.visiting, name),
                 visited: MapSet.put(final_state.visited, name),
                 path: List.delete(final_state.path, name)
             }}
        end
    end
  end

  # ============================================================================
  # Topological Sort
  # ============================================================================

  defp do_topological_sort([], result, in_degree, _dependents, _processed) do
    # Check if all nodes were processed
    remaining = Enum.filter(in_degree, fn {_name, degree} -> degree > 0 end)

    if remaining == [] do
      {:ok, Enum.reverse(result)}
    else
      # Some nodes have unresolved dependencies - cycle exists
      {:error, :cycle_detected}
    end
  end

  defp do_topological_sort([current | rest], result, in_degree, dependents, processed) do
    if MapSet.member?(processed, current) do
      # Already processed, skip
      do_topological_sort(rest, result, in_degree, dependents, processed)
    else
      # Add to result and update in-degrees
      processed = MapSet.put(processed, current)
      result = [current | result]

      # Decrement in-degree for all dependents
      deps_of_current = Map.get(dependents, current, [])

      {new_in_degree, new_ready} =
        Enum.reduce(deps_of_current, {in_degree, []}, fn dep, {deg_acc, ready_acc} ->
          new_deg = Map.get(deg_acc, dep, 0) - 1
          deg_acc = Map.put(deg_acc, dep, new_deg)

          if new_deg == 0 and not MapSet.member?(processed, dep) do
            {deg_acc, [dep | ready_acc]}
          else
            {deg_acc, ready_acc}
          end
        end)

      new_queue = rest ++ new_ready
      do_topological_sort(new_queue, result, new_in_degree, dependents, processed)
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp get_dependencies(step) when is_map(step) do
    case Map.get(step, "depends_on") do
      nil -> []
      deps when is_list(deps) -> deps
      _ -> []
    end
  end

  defp get_dependencies(_), do: []
end
