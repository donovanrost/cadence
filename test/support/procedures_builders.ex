defmodule Cadence.ProceduresBuilders do
  @moduledoc """
  Builders for Procedures structs without database interaction.

  Use these builders for pure unit tests that don't need persistence.
  For tests that need database records, use `Cadence.ProceduresFixtures` instead.

  ## Design Philosophy

  Builders create plain structs with sensible defaults. They:
  - Never touch the database
  - Generate unique IDs automatically
  - Allow full override of any field
  - Support both keyword lists and maps as input

  ## Examples

      # Simple execution struct
      execution = build_execution()

      # Execution with custom status
      execution = build_execution(status: :running)

      # Build DAG steps for testing
      steps = build_dag_steps([
        [name: "init", type: "log", message: "Starting"],
        [name: "work", type: "wait", duration: 100, depends_on: ["init"]],
        [name: "done", type: "log", message: "Done", depends_on: ["work"]]
      ])
  """

  alias Cadence.Procedures.{Procedure, ProcedureVersion, ProcedureExecution, ProcedureLog}

  # ============================================================================
  # Execution Builders
  # ============================================================================

  @doc """
  Builds a ProcedureExecution struct with defaults.

  ## Examples

      execution = build_execution()
      execution = build_execution(status: :running, parameters: %{"key" => "value"})
  """
  def build_execution(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      procedure_id: Ecto.UUID.generate(),
      procedure_version_id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      mission_id: Ecto.UUID.generate(),
      target_id: nil,
      status: :pending,
      parameters: %{},
      trigger_context: nil,
      triggered_by: :manual,
      triggered_by_user_id: nil,
      current_step_index: 0,
      completed_steps: [],
      failed_steps: [],
      skipped_steps: [],
      blocked_steps: [],
      timed_out_steps: [],
      step_results: %{},
      error_message: nil,
      error_step_index: nil,
      started_at: nil,
      completed_at: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(ProcedureExecution, Map.merge(defaults, to_map(overrides)))
  end

  @doc """
  Builds a running execution (with started_at set).
  """
  def build_running_execution(overrides \\ %{}) do
    build_execution(
      Map.merge(
        %{status: :running, started_at: DateTime.utc_now()},
        to_map(overrides)
      )
    )
  end

  @doc """
  Builds a completed execution.
  """
  def build_completed_execution(overrides \\ %{}) do
    now = DateTime.utc_now()

    build_execution(
      Map.merge(
        %{
          status: :completed,
          started_at: DateTime.add(now, -60, :second),
          completed_at: now,
          completed_steps: ["step_1", "step_2", "step_3"]
        },
        to_map(overrides)
      )
    )
  end

  # ============================================================================
  # Procedure Builders
  # ============================================================================

  @doc """
  Builds a Procedure struct with defaults.
  """
  def build_procedure(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      mission_id: Ecto.UUID.generate(),
      name: "Test Procedure #{System.unique_integer([:positive])}",
      description: "A test procedure",
      type: :dag,
      current_version_id: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(Procedure, Map.merge(defaults, to_map(overrides)))
  end

  @doc """
  Builds a ProcedureVersion struct with defaults.
  """
  def build_version(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      procedure_id: Ecto.UUID.generate(),
      version_number: 1,
      status: :draft,
      source: default_dag_source(),
      parameters_schema: nil,
      created_by_id: nil,
      approved_by_id: nil,
      approved_at: nil,
      allow_hazardous_commands: false,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct!(ProcedureVersion, Map.merge(defaults, to_map(overrides)))
  end

  @doc """
  Builds an approved version.
  """
  def build_approved_version(overrides \\ %{}) do
    build_version(
      Map.merge(
        %{
          status: :approved,
          approved_by_id: Ecto.UUID.generate(),
          approved_at: DateTime.utc_now()
        },
        to_map(overrides)
      )
    )
  end

  # ============================================================================
  # Log Builders
  # ============================================================================

  @doc """
  Builds a ProcedureLog struct.
  """
  def build_log(overrides \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      execution_id: Ecto.UUID.generate(),
      timestamp: DateTime.utc_now(),
      level: :info,
      message: "Test log message",
      step_index: nil,
      inserted_at: DateTime.utc_now()
    }

    struct!(ProcedureLog, Map.merge(defaults, to_map(overrides)))
  end

  # ============================================================================
  # DAG Step Builders
  # ============================================================================

  @doc """
  Builds a map of DAG steps from a list of configurations.

  ## Examples

      steps = build_dag_steps([
        [name: "init", type: "log", message: "Starting"],
        [name: "work", type: "wait", duration: 100, depends_on: ["init"]],
        [name: "done", type: "log", depends_on: ["work"]]
      ])

      # Returns:
      %{
        "init" => %{"type" => "log", "message" => "Starting", "depends_on" => []},
        "work" => %{"type" => "wait", "duration" => 100, "depends_on" => ["init"]},
        "done" => %{"type" => "log", "depends_on" => ["work"]}
      }
  """
  def build_dag_steps(configs) when is_list(configs) do
    configs
    |> Enum.with_index(1)
    |> Enum.map(fn {config, idx} ->
      config = to_map(config)
      name = Map.get(config, :name) || "step_#{idx}"
      {name, build_step(config)}
    end)
    |> Map.new()
  end

  @doc """
  Builds a single step definition map.
  """
  def build_step(config) do
    config = to_map(config)

    base = %{
      "type" => to_string(config[:type] || "log"),
      "depends_on" => config[:depends_on] || []
    }

    # Remove meta keys and convert remaining to string keys
    extra =
      config
      |> Map.drop([:name, :type, :depends_on])
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()

    Map.merge(base, extra)
  end

  @doc """
  Builds a log step.
  """
  def build_log_step(message, opts \\ []) do
    build_step(
      Keyword.merge(
        [type: "log", message: message],
        opts
      )
    )
  end

  @doc """
  Builds a wait step.
  """
  def build_wait_step(duration_ms, opts \\ []) do
    build_step(
      Keyword.merge(
        [type: "wait", duration: duration_ms],
        opts
      )
    )
  end

  @doc """
  Builds a check step.
  """
  def build_check_step(condition, opts \\ []) do
    build_step(
      Keyword.merge(
        [type: "check", condition: condition],
        opts
      )
    )
  end

  @doc """
  Builds a command step.
  """
  def build_command_step(command_name, args \\ %{}, opts \\ []) do
    build_step(
      Keyword.merge(
        [type: "command", name: command_name, args: args],
        opts
      )
    )
  end

  # ============================================================================
  # Source Builders
  # ============================================================================

  @doc """
  Returns a default DAG source with 3 steps.
  """
  def default_dag_source do
    %{
      "steps" => %{
        "step_1" => %{"type" => "log", "message" => "Starting procedure", "depends_on" => []},
        "step_2" => %{"type" => "wait", "duration" => 10, "depends_on" => ["step_1"]},
        "step_3" => %{"type" => "log", "message" => "Procedure complete", "depends_on" => ["step_2"]}
      }
    }
  end

  @doc """
  Builds a DAG source from step configs.

  ## Examples

      source = build_dag_source([
        [name: "init", type: "log"],
        [name: "work", type: "wait", duration: 100, depends_on: ["init"]]
      ])
  """
  def build_dag_source(step_configs, opts \\ []) do
    base = %{"steps" => build_dag_steps(step_configs)}

    if on_step_failure = Keyword.get(opts, :on_step_failure) do
      Map.put(base, "on_step_failure", on_step_failure)
    else
      base
    end
  end

  @doc """
  Builds a script source.
  """
  def build_script_source(code) do
    %{"code" => code}
  end

  # ============================================================================
  # Context Builders
  # ============================================================================

  @doc """
  Builds an execution context map for DAG/step execution.

  ## Examples

      context = build_context()
      context = build_context(params: %{"threshold" => 50})
  """
  def build_context(overrides \\ %{}) do
    defaults = %{
      mission_id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      target_id: nil,
      execution_id: Ecto.UUID.generate(),
      params: %{},
      vars: %{},
      trigger: nil
    }

    Map.merge(defaults, to_map(overrides))
  end

  @doc """
  Builds a context with trigger data (for automation-triggered executions).
  """
  def build_triggered_context(trigger_type, trigger_data, overrides \\ %{}) do
    build_context(
      Map.merge(
        %{
          trigger: %{
            "type" => to_string(trigger_type),
            "data" => trigger_data
          }
        },
        to_map(overrides)
      )
    )
  end

  # ============================================================================
  # Lua/CadenceApi Context Builder
  # ============================================================================

  @doc """
  Builds a context suitable for CadenceApi.install/2.

  Includes execution_pid for message sending.
  """
  def build_cadence_api_context(overrides \\ %{}) do
    defaults = %{
      mission_id: Ecto.UUID.generate(),
      organization_id: Ecto.UUID.generate(),
      target_id: nil,
      execution_id: Ecto.UUID.generate(),
      execution_pid: self(),
      params: %{},
      allow_hazardous_commands: false
    }

    Map.merge(defaults, to_map(overrides))
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp to_map(kw) when is_list(kw), do: Map.new(kw)
  defp to_map(map) when is_map(map), do: map
end
