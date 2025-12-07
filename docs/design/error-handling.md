# Error Handling Guidelines

This document establishes patterns for error handling in the Cadence codebase.

## Principles

1. **Business logic errors** use `{:ok, result} | {:error, reason}` tuples
2. **Programmer errors** (bugs) may raise exceptions
3. **Control flow** never uses exceptions

## When to Use Each Pattern

### Tuple Returns `{:ok, _} | {:error, _}`

Use tuple returns for:

- Database operations that might fail (validation, conflicts, constraints)
- External service calls (commands, telemetry queries)
- Operations where the caller might want to handle failure differently
- Any function that can fail in normal operation

```elixir
# Good - caller can pattern match
def get_telemetry(item_name) do
  case CVT.get(item_name) do
    nil -> {:error, :not_found}
    value -> {:ok, value}
  end
end

# Good - validation that can fail
def validate_parameters(params, schema) do
  case do_validate(params, schema) do
    :ok -> {:ok, params}
    errors -> {:error, {:validation_failed, errors}}
  end
end
```

### Bang Functions (raise on error)

Use bang functions (`!` suffix) for:

- Internal consistency checks that should never fail in production
- Cases where failure indicates a programming bug, not a recoverable error
- Convenience wrappers where the caller explicitly wants to crash on failure

**Rules for bang functions:**

1. Must be documented with `@doc` noting what exception is raised
2. Should have a non-bang counterpart that returns tuples
3. Name must end with `!`

```elixir
# Good - has non-bang counterpart, documents exception
@doc """
Gets a procedure by ID. Raises if not found.

## Raises

  * `Ecto.NoResultsError` if no procedure exists with the given ID
"""
def get_procedure!(id) do
  Repo.get!(Procedure, id)
end

# Also provide:
def get_procedure(id) do
  case Repo.get(Procedure, id) do
    nil -> {:error, :not_found}
    procedure -> {:ok, procedure}
  end
end
```

### Exceptions (raise/rescue)

Use exceptions for:

- Truly exceptional conditions that indicate bugs
- Violations of invariants that should never happen
- Early failure in development to catch bugs

```elixir
# Good - this should never happen if code is correct
def execute_step(%{type: type}) when type not in @valid_types do
  raise ArgumentError, "Invalid step type: #{inspect(type)}. Valid types: #{inspect(@valid_types)}"
end
```

### Never Use

1. **`throw` for control flow** - This is an anti-pattern. Use return values instead.

```elixir
# BAD - using throw for control flow
def execute(steps) do
  try do
    Enum.each(steps, fn step ->
      if should_abort?(step), do: throw(:abort)
      run_step(step)
    end)
    :ok
  catch
    :abort -> {:error, :aborted}
  end
end

# GOOD - use return values
def execute(steps) do
  Enum.reduce_while(steps, :ok, fn step, _acc ->
    if should_abort?(step) do
      {:halt, {:error, :aborted}}
    else
      run_step(step)
      {:cont, :ok}
    end
  end)
end
```

2. **Bare `raise` without a specific exception type**

```elixir
# BAD
raise "Something went wrong"

# GOOD
raise RuntimeError, "Something went wrong"

# BETTER - custom exception
raise Cadence.Procedures.ExecutionError,
  type: :step_failed,
  message: "Step timed out",
  step_name: step_name
```

## Error Structs

For domain-specific errors, define custom exception structs:

```elixir
defmodule Cadence.Procedures.ExecutionError do
  @moduledoc """
  Error raised during procedure execution.
  """

  defexception [:type, :message, :step_name, :details]

  @type error_type ::
    :validation_error
    | :step_failed
    | :step_timeout
    | :executor_crash
    | :condition_error
    | :cancelled

  @impl true
  def message(%{type: type, message: msg, step_name: nil}) do
    "[#{type}] #{msg}"
  end

  def message(%{type: type, message: msg, step_name: step}) do
    "[#{type}] Step '#{step}': #{msg}"
  end
end
```

## Error Handling in Different Layers

### Context Modules (e.g., `Cadence.Procedures`)

Always return tuples. Let callers decide how to handle errors.

```elixir
def start_execution(attrs) do
  case validate(attrs) do
    :ok ->
      %ProcedureExecution{}
      |> changeset(attrs)
      |> Repo.insert()

    {:error, _} = error ->
      error
  end
end
```

### GenServers

- Use tuples in `handle_call` replies
- Log unexpected errors
- Consider whether to crash or handle gracefully

```elixir
def handle_call({:execute, params}, _from, state) do
  case do_execute(params, state) do
    {:ok, result} ->
      {:reply, {:ok, result}, state}

    {:error, reason} = error ->
      Logger.warning("Execution failed: #{inspect(reason)}")
      {:reply, error, state}
  end
end
```

### LiveViews

- Always handle errors gracefully with user-friendly messages
- Never expose internal error details to users

```elixir
def handle_event("submit", params, socket) do
  case Context.create(params) do
    {:ok, record} ->
      {:noreply,
       socket
       |> put_flash(:info, "Created successfully")
       |> push_navigate(to: ~p"/records/#{record}")}

    {:error, :validation_failed} ->
      {:noreply, put_flash(socket, :error, "Please check your input")}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "You don't have permission")}

    {:error, _reason} ->
      {:noreply, put_flash(socket, :error, "Something went wrong")}
  end
end
```

## Logging Errors

- Use appropriate log levels
- Include context for debugging
- Don't log sensitive data

```elixir
# Good
Logger.error("Step execution failed",
  execution_id: execution.id,
  step_name: step_name,
  error: inspect(reason)
)

# Bad - missing context
Logger.error("Error occurred")

# Bad - sensitive data
Logger.error("Auth failed for user #{email} with password #{password}")
```

## Testing Error Paths

Always test error cases:

```elixir
describe "start_execution/1" do
  test "returns error for invalid procedure" do
    assert {:error, :procedure_not_found} =
      Procedures.start_execution(%{procedure_id: "nonexistent"})
  end

  test "returns error when at concurrency limit" do
    # ... setup to hit limit ...
    assert {:error, :at_concurrency_limit} =
      Procedures.start_execution(valid_attrs)
  end
end
```
