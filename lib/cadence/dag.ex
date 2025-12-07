defmodule Cadence.Dag do
  @moduledoc """
  DAG (Directed Acyclic Graph) execution engine.

  Executes steps in parallel based on their dependencies, with support for:
  - Concurrent execution with configurable limits
  - Pause/resume/abort control signals
  - Multiple failure handling modes
  - Status change callbacks for observability

  ## Example

      steps = %{
        "fetch" => %{"type" => "command", "name" => "FETCH", "depends_on" => []},
        "process" => %{"type" => "wait", "duration" => 1000, "depends_on" => ["fetch"]},
        "notify" => %{"type" => "log", "message" => "Done", "depends_on" => ["process"]}
      }

      {:ok, result} = Cadence.Dag.execute(steps, executor_fn, context,
        max_concurrency: 5,
        on_step_failure: :continue
      )

  ## Step Definition

  Each step is a map with at minimum:
  - `"depends_on"` - List of step names this step depends on (can be empty)

  Additional fields depend on the step type and executor implementation.

  ## Failure Handling

  When a step fails, the behavior is controlled by `:on_step_failure`:
  - `:abort` (default) - Stop the entire DAG, mark remaining steps as blocked
  - `:continue` - Mark the step as failed, block dependents, continue independent branches
  - `:pause` - Pause execution for operator decision

  ## Control Signals

  During execution, the executor process checks for control signals:
  - `{:control_signal, :pause}` - Pause at next safe point
  - `{:control_signal, :abort}` - Abort immediately

  Send these to the executor process (e.g., via the Task pid).
  """

  alias Cadence.Procedures.Dag.{Executor, Validator}

  @type step_name :: String.t()
  @type step_def :: map()
  @type context :: map()
  @type step_result :: {:ok, term()} | {:error, term()} | {:skip, term()}
  @type step_executor :: (step_name(), step_def(), context() -> step_result())

  @type result :: %{
          completed_steps: [step_name()],
          failed_steps: [step_name()],
          blocked_steps: [step_name()],
          skipped_steps: [step_name()],
          timed_out_steps: [step_name()],
          step_results: %{step_name() => term()}
        }

  @type option ::
          {:max_concurrency, pos_integer() | :unlimited}
          | {:on_step_failure, :abort | :continue | :pause}
          | {:on_status_change, (step_name(), atom(), term() -> :ok)}
          | {:completed_steps, [step_name()]}
          | {:step_timeout, pos_integer()}
          | {:global_timeout, pos_integer()}

  @doc """
  Executes a DAG of steps.

  ## Arguments

  - `steps` - Map of step names to step definitions
  - `step_executor` - Function `(name, step_def, context) -> {:ok, result} | {:error, reason} | {:skip, reason}`
  - `context` - Execution context passed to step executor
  - `opts` - Execution options

  ## Options

  - `:max_concurrency` - Maximum parallel steps (default: `:unlimited`)
  - `:on_step_failure` - How to handle failures: `:abort`, `:continue`, or `:pause`
  - `:on_status_change` - Callback `(step_name, status, data) -> :ok` for step status changes
  - `:completed_steps` - Pre-completed steps for resume scenarios
  - `:step_timeout` - Default timeout for steps in ms (default: 5 minutes)
  - `:global_timeout` - Total execution timeout in ms (default: 1 hour)

  ## Step-level Timeouts

  Individual steps can override the default timeout by setting a `timeout` field (in ms).
  When a step times out, it is killed and marked as `:timed_out`.

  ## Returns

  - `{:ok, result}` - Execution completed (may have failed/timed_out steps if `:continue` mode)
  - `{:error, {:validation_failed, reasons}}` - Invalid DAG structure
  - `{:error, {:steps_failed, result}}` - Steps failed in `:abort` mode
  - `{:error, {:global_timeout, result}}` - Global timeout exceeded
  - `{:error, :aborted}` - Execution was aborted via control signal
  - `{:paused, result}` - Execution paused via control signal or `:pause` failure mode
  """
  @spec execute(map(), step_executor(), context(), [option()]) ::
          {:ok, result()} | {:error, term()} | {:paused, result()}
  def execute(steps, step_executor, context, opts \\ []) do
    Executor.execute(steps, step_executor, context, opts)
  end

  @doc """
  Validates a DAG structure without executing it.

  Checks for:
  - No circular dependencies (cycles)
  - All dependencies reference existing steps
  - Unique step names
  - Required `depends_on` field present

  ## Returns

  - `:ok` - Valid DAG
  - `{:error, reasons}` - List of validation error strings
  """
  @spec validate(map()) :: :ok | {:error, [String.t()]}
  def validate(steps) do
    Validator.validate(steps)
  end

  @doc """
  Checks if a source map is in DAG format (steps as map).

  Used to differentiate from legacy list-based step formats.
  """
  @spec dag_format?(map()) :: boolean()
  def dag_format?(source) do
    Validator.is_dag_format?(source)
  end

  @doc """
  Builds a dependency graph from steps.

  Returns a map of `step_name => [dependency_names]`.
  """
  @spec dependency_graph(map()) :: %{step_name() => [step_name()]}
  def dependency_graph(steps) do
    Validator.build_dependency_graph(steps)
  end

  @doc """
  Builds a dependents graph from steps.

  Returns a map of `step_name => [dependent_names]` (reverse of dependencies).
  """
  @spec dependents_graph(map()) :: %{step_name() => [step_name()]}
  def dependents_graph(steps) do
    Validator.build_dependents_graph(steps)
  end
end
