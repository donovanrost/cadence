defmodule Cadence.Telemetry.DerivedItems do
  @moduledoc """
  Computes derived telemetry items from converted values.

  Derived items are calculated values that don't exist in the raw packet data
  but are computed from other telemetry items using expressions.

  ## Runtime Overlay Model

  Derived items are stored as a mission-scoped runtime overlay, separate from
  the immutable DefinitionSet. This allows:

  - Adding derived calculations without modifying the C&T database
  - Persisting derived items across DefinitionSet version updates
  - Creating mission-specific computations that don't belong in flight software

  ## Pipeline Position

  Derived items are computed after conversions and before limits checking:

      Decommutation → Conversions → **Derived Items** → Limits → CVT

  ## Dependency Ordering

  Derived items can depend on other derived items. This module handles
  topological sorting to ensure correct evaluation order.

  ## Example

      # Mission has derived items defined:
      # - TEMP_AVG (expression: "(HEALTH.TEMP1 + HEALTH.TEMP2) / 2")
      # - TEMP_DELTA (expression: "HEALTH.TEMP1 - TEMP_AVG")

      converted_items = %{"HEALTH.TEMP1" => 25.0, "HEALTH.TEMP2" => 30.0}
      {:ok, all_items} = DerivedItems.compute(converted_items, mission_id)
      # => %{"HEALTH.TEMP1" => 25.0, "HEALTH.TEMP2" => 30.0, "TEMP_AVG" => 27.5, "TEMP_DELTA" => -2.5}
  """

  require Logger

  alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator
  alias Cadence.Telemetry.DerivedItems.Cache

  @type item_value :: {String.t(), number() | nil}
  @type item_values :: %{String.t() => number() | nil}

  @doc """
  Computes derived items and merges them with converted items.

  Loads enabled derived items from the mission's runtime overlay and computes
  them using the converted telemetry values.

  ## Parameters

  - `converted_items` - Map of qualified item names to values (e.g., %{"HEALTH.TEMP" => 25.0})
  - `mission_id` - Mission ID for loading derived item definitions

  ## Returns

  - `{:ok, all_items}` - Converted items plus computed derived items (as map)
  - `{:error, reason}` - If computation fails (e.g., circular dependencies)
  """
  @spec compute(item_values(), String.t()) ::
          {:ok, item_values()} | {:error, term()}
  def compute(converted_items, mission_id) do
    # Get pre-sorted derived items from cache (avoids DB query per packet)
    case Cache.get_definitions(mission_id) do
      {:ok, {[], _packet_index}} ->
        {:ok, converted_items}

      {:ok, {all_defs, packet_index}} ->
        # Fast path: if only one packet type in index, use all_defs directly
        # (no filtering needed - all derived items depend on same packet)
        relevant_defs =
          case map_size(packet_index) do
            0 -> []
            1 -> all_defs
            _ -> get_relevant_defs(converted_items, packet_index)
          end

        if Enum.empty?(relevant_defs) do
          {:ok, converted_items}
        else
          compute_with_sorted_defs(converted_items, relevant_defs, mission_id)
        end

      # Handle legacy format (just defs, no index)
      {:ok, sorted_defs} when is_list(sorted_defs) ->
        compute_with_sorted_defs(converted_items, sorted_defs, mission_id)

      {:error, reason} ->
        Logger.warning("Failed to load derived items from cache: #{inspect(reason)}")
        {:ok, converted_items}
    end
  end

  # Extract packet names from converted_items keys and get relevant derived items
  # Optimized hot path - avoids allocations for common single-packet case
  defp get_relevant_defs(converted_items, packet_index) do
    # Fast path: get packet name from first key (all items in batch share same packet)
    case get_first_packet_name(converted_items) do
      nil ->
        []

      first_packet ->
        # Check if all items are from the same packet (common case)
        # by checking if any other key has a different prefix
        if single_packet_batch?(converted_items, first_packet) do
          # Fast path: return pre-sorted bucket directly (no allocations)
          Map.get(packet_index, first_packet, [])
        else
          # Slow path: multiple packets, need to merge and sort
          get_relevant_defs_multi_packet(converted_items, packet_index, first_packet)
        end
    end
  end

  # Get packet name from first key without allocating a list of all keys
  defp get_first_packet_name(converted_items) do
    # :maps.iterator is the most efficient way to get first key
    case :maps.next(:maps.iterator(converted_items)) do
      {key, _value, _iter} ->
        case :binary.split(key, ".") do
          [packet, _rest] -> packet
          _ -> nil
        end

      :none ->
        nil
    end
  end

  # Check if all keys share the same packet prefix
  # Short-circuits on first mismatch
  defp single_packet_batch?(converted_items, packet_prefix) do
    prefix_with_dot = packet_prefix <> "."
    prefix_len = byte_size(prefix_with_dot)

    Enum.all?(converted_items, fn {key, _value} ->
      binary_part(key, 0, min(prefix_len, byte_size(key))) == prefix_with_dot
    end)
  end

  # Slow path for multi-packet batches
  defp get_relevant_defs_multi_packet(converted_items, packet_index, first_packet) do
    # Collect unique packet names (we already know first_packet)
    packet_names =
      converted_items
      |> Enum.reduce([first_packet], fn {key, _value}, acc ->
        case :binary.split(key, ".") do
          [packet, _rest] ->
            if packet in acc, do: acc, else: [packet | acc]

          _ ->
            acc
        end
      end)

    # Get derived items from all relevant packets
    packet_names
    |> Enum.flat_map(&Map.get(packet_index, &1, []))
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(&Map.get(&1, :topo_order, 0))
  end

  @doc """
  Computes derived items using pre-sorted definitions.

  This is the hot path - definitions should already be sorted by dependencies.
  Used internally by compute/2 after loading from cache.

  ## Parameters

  - `converted_items` - Map of qualified item names to values
  - `sorted_defs` - List of derived item definitions in topological order
  - `mission_id` - Mission ID for stateful function state scoping

  ## Note

  This function supports stateful functions (rolling_avg, rate, etc.) which
  maintain state in the ProcessorState ETS table. State is scoped by mission_id
  and item name to ensure proper isolation.
  """
  @spec compute_with_sorted_defs(item_values(), [map()], String.t()) :: {:ok, item_values()}
  def compute_with_sorted_defs(converted_items, sorted_defs, mission_id) do
    # Compute each derived item in dependency order
    final_bindings =
      Enum.reduce(sorted_defs, converted_items, fn def, bindings ->
        case compute_single(def, bindings, mission_id) do
          {:ok, value} ->
            Map.put(bindings, def.name, value)

          {:skip, _reason} ->
            # Skip silently - required variables not available for this packet
            bindings

          {:error, reason} ->
            Logger.warning(
              "Failed to compute derived item #{def.name}: #{ExpressionEvaluator.format_error(reason)}"
            )

            # Use nil for failed computations
            Map.put(bindings, def.name, nil)
        end
      end)

    {:ok, final_bindings}
  end

  # Legacy 2-arg version for backward compatibility (tests, etc.)
  @doc false
  @spec compute_with_sorted_defs(item_values(), [map()]) :: {:ok, item_values()}
  def compute_with_sorted_defs(converted_items, sorted_defs) do
    compute_with_sorted_defs(converted_items, sorted_defs, "legacy")
  end

  # Compute a single derived item - optimized path with pre-parsed AST
  # Uses pre-extracted required_vars and pre-parsed AST to avoid parsing in hot path
  # Fast path for pure expressions (no stateful functions)
  defp compute_single(
         %{parsed_ast: parsed_ast, required_vars: required_vars, has_stateful: false},
         bindings,
         _mission_id
       )
       when not is_nil(parsed_ast) do
    if all_vars_present?(required_vars, bindings) do
      # Use pure AST evaluator - no stateful context needed
      ExpressionEvaluator.evaluate_ast(parsed_ast, bindings)
    else
      {:skip, :missing_variables}
    end
  end

  # Stateful path - expressions containing stateful functions
  defp compute_single(
         %{parsed_ast: parsed_ast, required_vars: required_vars, name: name},
         bindings,
         mission_id
       )
       when not is_nil(parsed_ast) do
    # Check if all required variables are available (short-circuit, no allocation)
    if all_vars_present?(required_vars, bindings) do
      # Use pre-parsed AST with stateful evaluation support
      ExpressionEvaluator.evaluate_ast_stateful(parsed_ast, bindings, mission_id, name)
    else
      # Skip - not all required variables are available for this packet
      {:skip, :missing_variables}
    end
  end

  # Fallback: pre-extracted required_vars but no cached AST (parse at runtime)
  defp compute_single(
         %{derived_config: config, required_vars: required_vars, name: name},
         bindings,
         mission_id
       ) do
    expression = config["expression"]

    if is_nil(expression) or expression == "" do
      {:error, :missing_expression}
    else
      # Check if all required variables are available (short-circuit, no allocation)
      if all_vars_present?(required_vars, bindings) do
        ExpressionEvaluator.evaluate_stateful(expression, bindings, mission_id, name)
      else
        # Skip - not all required variables are available for this packet
        {:skip, :missing_variables}
      end
    end
  end

  # Fallback for definitions without pre-extracted required_vars (tests)
  defp compute_single(%{derived_config: config, name: name}, bindings, mission_id) do
    expression = config["expression"]

    if is_nil(expression) or expression == "" do
      {:error, :missing_expression}
    else
      ExpressionEvaluator.evaluate_stateful(expression, bindings, mission_id, name)
    end
  end

  # Short-circuit check - returns false as soon as a missing var is found
  # Avoids allocating a list of missing vars
  defp all_vars_present?([], _bindings), do: true

  defp all_vars_present?([var | rest], bindings) do
    Map.has_key?(bindings, var) and all_vars_present?(rest, bindings)
  end

  @doc """
  Sorts derived item definitions by their dependencies.

  Uses topological sort to ensure items are computed in the correct order
  (dependencies before dependents).

  ## Returns

  - `{:ok, sorted_list}` - Definitions in evaluation order
  - `{:error, {:circular_dependency, items}}` - If circular dependencies detected
  """
  @spec sort_by_dependencies([map()]) ::
          {:ok, [map()]} | {:error, term()}
  def sort_by_dependencies(derived_defs) do
    # Build dependency graph
    # Node: item name
    # Edges: item -> dependencies

    # Get all derived item names
    derived_names = MapSet.new(derived_defs, & &1.name)

    # Build adjacency list (item -> items it depends on that are also derived)
    deps_map =
      derived_defs
      |> Enum.map(fn def ->
        # Extract variables directly from the expression
        expression = get_in(def.derived_config, ["expression"]) || ""
        source_items = extract_source_items(expression)

        # Only track dependencies on other derived items
        derived_deps =
          source_items
          |> Enum.filter(&MapSet.member?(derived_names, &1))

        {def.name, derived_deps}
      end)
      |> Map.new()

    # Topological sort using Kahn's algorithm
    case topological_sort(deps_map, derived_defs) do
      {:ok, sorted_names} ->
        # Map back to definitions
        name_to_def = Map.new(derived_defs, &{&1.name, &1})
        sorted_defs = Enum.map(sorted_names, &Map.fetch!(name_to_def, &1))
        {:ok, sorted_defs}

      error ->
        error
    end
  end

  # Kahn's algorithm for topological sort
  defp topological_sort(deps_map, derived_defs) do
    all_names = Enum.map(derived_defs, & &1.name)

    # Calculate in-degree (number of dependencies)
    in_degree =
      Enum.reduce(all_names, %{}, fn name, acc ->
        deps = Map.get(deps_map, name, [])
        Map.put(acc, name, length(deps))
      end)

    # Build reverse map (item -> items that depend on it)
    reverse_deps =
      Enum.reduce(deps_map, %{}, fn {name, deps}, acc ->
        Enum.reduce(deps, acc, fn dep, inner_acc ->
          Map.update(inner_acc, dep, [name], &[name | &1])
        end)
      end)

    # Start with items that have no dependencies
    queue =
      in_degree
      |> Enum.filter(fn {_name, degree} -> degree == 0 end)
      |> Enum.map(fn {name, _} -> name end)

    kahn_loop(queue, in_degree, reverse_deps, [])
  end

  defp kahn_loop([], in_degree, _reverse_deps, result) do
    # Check if all items were processed
    remaining = Enum.filter(in_degree, fn {_, degree} -> degree > 0 end)

    if Enum.empty?(remaining) do
      {:ok, Enum.reverse(result)}
    else
      cycle_items = Enum.map(remaining, fn {name, _} -> name end)
      {:error, {:circular_dependency, cycle_items}}
    end
  end

  defp kahn_loop([current | rest], in_degree, reverse_deps, result) do
    # Process current item
    new_result = [current | result]

    # Reduce in-degree of dependents
    dependents = Map.get(reverse_deps, current, [])

    {new_in_degree, new_queue_items} =
      Enum.reduce(dependents, {in_degree, []}, fn dep, {deg_acc, queue_acc} ->
        new_degree = deg_acc[dep] - 1
        new_deg_acc = Map.put(deg_acc, dep, new_degree)

        if new_degree == 0 do
          {new_deg_acc, [dep | queue_acc]}
        else
          {new_deg_acc, queue_acc}
        end
      end)

    # Mark current as processed
    final_in_degree = Map.put(new_in_degree, current, -1)

    kahn_loop(rest ++ new_queue_items, final_in_degree, reverse_deps, new_result)
  end

  @doc """
  Validates derived item definitions.

  Checks for:
  - Valid expressions
  - Missing dependencies
  - Circular dependencies

  ## Parameters

  - `item_defs` - List of item definitions (both regular and derived)

  ## Returns

  - `:ok` if all valid
  - `{:error, errors}` with list of validation errors
  """
  @spec validate_definitions([map()]) :: :ok | {:error, [term()]}
  def validate_definitions(item_defs) do
    derived_defs = Enum.filter(item_defs, &derived_item?/1)
    regular_names = item_defs |> Enum.reject(&derived_item?/1) |> Enum.map(& &1.name)
    derived_names = Enum.map(derived_defs, & &1.name)
    all_names = MapSet.new(regular_names ++ derived_names)

    errors =
      derived_defs
      |> Enum.flat_map(fn def ->
        validate_single_definition(def, all_names)
      end)

    # Also check for circular dependencies
    errors =
      case sort_by_dependencies(derived_defs) do
        {:ok, _} -> errors
        {:error, {:circular_dependency, items}} -> [{:circular_dependency, items} | errors]
      end

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  # Check if an item is a derived item
  defp derived_item?(%{data_type: :derived}), do: true
  defp derived_item?(%{data_type: "derived"}), do: true
  defp derived_item?(_), do: false

  defp validate_single_definition(%{name: name, derived_config: config}, all_names) do
    errors = []

    # Check expression is valid
    expression = config["expression"] || ""

    errors =
      case ExpressionEvaluator.validate(expression) do
        :ok -> errors
        {:error, reason} -> [{:invalid_expression, name, reason} | errors]
      end

    # Extract variables from expression and check all referenced items exist
    source_items = extract_source_items(expression)

    missing =
      source_items
      |> Enum.reject(&MapSet.member?(all_names, &1))

    errors =
      if Enum.empty?(missing) do
        errors
      else
        [{:undefined_dependencies, name, missing} | errors]
      end

    errors
  end

  # Extract source items (variables) from an expression
  defp extract_source_items(expression) do
    case ExpressionEvaluator.extract_variables(expression) do
      {:ok, variables} -> variables
      {:error, _} -> []
    end
  end
end
