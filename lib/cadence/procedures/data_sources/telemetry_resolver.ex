defmodule Cadence.Procedures.DataSources.TelemetryResolver do
  @moduledoc """
  Resolves telemetry path templates to concrete item paths.

  Procedures use template paths that get resolved at execution time based on
  the execution context. This allows a single procedure to work across multiple
  targets in a constellation.

  ## Path Formats

  ### Explicit Target
      "SC-001.EPS.battery_voltage"
      → "SC-001.EPS.battery_voltage"

  ### Target Prefix (uses execution target)
      "target.EPS.battery_voltage"
      → "SC-001.EPS.battery_voltage" (if execution.target_id → SC-001)

  ### Parameter Interpolation
      "{{params.vehicle}}.EPS.battery_voltage"
      → "SC-002.EPS.battery_voltage" (if params.vehicle = "SC-002")

  ### Unscoped (uses execution target)
      "EPS.battery_voltage"
      → "SC-001.EPS.battery_voltage" (if execution.target_id → SC-001)

  ## Context Requirements

  The resolver requires a context map with:
  - `:target_id` - The execution's target UUID (optional)
  - `:target_name` - The target's name/identifier (resolved from target_id)
  - `:parameters` - Runtime parameters (for interpolation)

  ## Examples

      context = %{
        target_id: "uuid-123",
        target_name: "SC-001",
        parameters: %{"backup" => "SC-002"}
      }

      resolve("target.EPS.voltage", context)
      # => {:ok, "SC-001.EPS.voltage"}

      resolve("{{params.backup}}.EPS.voltage", context)
      # => {:ok, "SC-002.EPS.voltage"}

      resolve("EPS.voltage", context)
      # => {:ok, "SC-001.EPS.voltage"}

      resolve("GROUND.POWER.grid", context)
      # => {:ok, "GROUND.POWER.grid"} (already has target)
  """

  @type context :: %{
          optional(:target_id) => String.t(),
          optional(:target_name) => String.t(),
          optional(:parameters) => map()
        }

  @doc """
  Resolves a telemetry path template to a concrete path.

  ## Parameters

  - `path` - The template path to resolve
  - `context` - Execution context with target and parameters

  ## Returns

  - `{:ok, resolved_path}` - Successfully resolved
  - `{:error, :no_target}` - Path requires target but none in context
  - `{:error, {:missing_param, name}}` - Referenced parameter not found
  - `{:error, reason}` - Other resolution error
  """
  @spec resolve(String.t(), context()) :: {:ok, String.t()} | {:error, term()}
  def resolve(path, context) do
    path
    |> interpolate_params(context[:parameters] || %{})
    |> case do
      {:ok, interpolated} ->
        interpolated
        |> resolve_target_prefix(context)
        |> apply_default_target(context)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Resolves a path, returning the path unchanged on error.

  Useful when you want to attempt resolution but fall back gracefully.
  """
  @spec resolve!(String.t(), context()) :: String.t()
  def resolve!(path, context) do
    case resolve(path, context) do
      {:ok, resolved} -> resolved
      {:error, _} -> path
    end
  end

  @doc """
  Extracts the target prefix from a resolved path.

  ## Examples

      extract_target("SC-001.EPS.voltage")
      # => {:ok, "SC-001"}

      extract_target("EPS.voltage")
      # => {:error, :no_target_prefix}
  """
  @spec extract_target(String.t()) :: {:ok, String.t()} | {:error, :no_target_prefix}
  def extract_target(path) do
    parts = String.split(path, ".")

    case parts do
      [target, _packet, _item] -> {:ok, target}
      [target, _packet, _item | _rest] -> {:ok, target}
      _ -> {:error, :no_target_prefix}
    end
  end

  @doc """
  Checks if a path contains unresolved template variables.
  """
  @spec has_unresolved_vars?(String.t()) :: boolean()
  def has_unresolved_vars?(path) do
    String.contains?(path, "{{") or String.starts_with?(path, "target.")
  end

  @doc """
  Lists all parameter references in a path.

  ## Examples

      list_param_refs("{{params.primary}}.EPS.{{params.metric}}")
      # => ["primary", "metric"]
  """
  @spec list_param_refs(String.t()) :: [String.t()]
  def list_param_refs(path) do
    ~r/\{\{params\.(\w+)\}\}/
    |> Regex.scan(path)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  # ─────────────────────────────────────────────────────────────
  # Private Functions
  # ─────────────────────────────────────────────────────────────

  defp interpolate_params(path, params) do
    # Find all {{params.name}} patterns and replace with values
    pattern = ~r/\{\{params\.(\w+)\}\}/

    refs = Regex.scan(pattern, path)

    result =
      Enum.reduce_while(refs, {:ok, path}, fn [full_match, param_name], {:ok, current_path} ->
        case get_param_value(params, param_name) do
          {:ok, value} ->
            replaced = String.replace(current_path, full_match, to_string(value))
            {:cont, {:ok, replaced}}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    result
  end

  defp get_param_value(params, name) do
    # Try both string and atom keys
    value = params[name] || params[String.to_atom(name)]

    if is_nil(value) do
      {:error, {:missing_param, name}}
    else
      {:ok, value}
    end
  end

  defp resolve_target_prefix("target." <> rest, context) do
    case get_target_name(context) do
      {:ok, target_name} ->
        {:ok, "#{target_name}.#{rest}"}

      {:error, _} = error ->
        error
    end
  end

  defp resolve_target_prefix(path, _context) do
    {:ok, path}
  end

  defp apply_default_target({:ok, path}, context) do
    if has_target_prefix?(path) do
      {:ok, path}
    else
      # Path is unscoped (e.g., "EPS.voltage") - apply default target
      case get_target_name(context) do
        {:ok, target_name} ->
          {:ok, "#{target_name}.#{path}"}

        {:error, :no_target} ->
          # No target available - return path as-is
          # This might be valid for mission-level telemetry
          {:ok, path}
      end
    end
  end

  defp apply_default_target({:error, _} = error, _context), do: error

  defp has_target_prefix?(path) do
    parts = String.split(path, ".")
    # If path has 3+ parts, first part is a target
    length(parts) >= 3
  end

  defp get_target_name(context) do
    cond do
      # Direct target_name in context
      context[:target_name] ->
        {:ok, context[:target_name]}

      # Target ID that needs resolution
      context[:target_id] ->
        resolve_target_id(context[:target_id])

      true ->
        {:error, :no_target}
    end
  end

  defp resolve_target_id(target_id) do
    # Look up target name from ID (unscoped since we don't have mission context here)
    case Cadence.Targets.get_target_unscoped(target_id) do
      {:ok, target} ->
        {:ok, target.name}

      nil ->
        {:error, {:target_not_found, target_id}}

      {:error, :not_found} ->
        {:error, {:target_not_found, target_id}}

      _ ->
        {:error, {:target_lookup_failed, target_id}}
    end
  rescue
    # Target module might not be available or ID format wrong
    _ -> {:error, {:target_lookup_failed, target_id}}
  end
end
