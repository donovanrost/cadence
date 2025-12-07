defmodule Cadence.Procedures.ExecutionError do
  @moduledoc """
  Structured error type for procedure execution failures.

  Provides consistent error reporting across all procedure execution paths
  with support for step-level context and error categorization.

  ## Error Types

  - `:validation_error` - Procedure or parameter validation failed
  - `:step_failed` - A step returned an error
  - `:step_timeout` - A step exceeded its timeout
  - `:executor_crash` - The DAG executor crashed unexpectedly
  - `:condition_error` - Condition evaluation failed
  - `:cancelled` - Execution was cancelled by user
  - `:aborted` - Execution was aborted due to step failure (abort mode)

  ## Example

      %ExecutionError{
        type: :step_failed,
        message: "Command DEPLOY failed: target unreachable",
        step_name: "deploy_satellite",
        details: %{command: "DEPLOY", reason: :timeout}
      }
  """

  @type error_type ::
          :validation_error
          | :step_failed
          | :step_timeout
          | :executor_crash
          | :condition_error
          | :cancelled
          | :aborted

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          step_name: String.t() | nil,
          details: map()
        }

  defexception [:type, :message, :step_name, :details]

  @impl true
  def message(%__MODULE__{type: type, message: msg, step_name: nil}) do
    "[#{type}] #{msg}"
  end

  def message(%__MODULE__{type: type, message: msg, step_name: step}) do
    "[#{type}] Step '#{step}': #{msg}"
  end

  @doc """
  Creates a validation error.
  """
  @spec validation_error(String.t(), map()) :: t()
  def validation_error(message, details \\ %{}) do
    %__MODULE__{
      type: :validation_error,
      message: message,
      step_name: nil,
      details: details
    }
  end

  @doc """
  Creates a step failure error.
  """
  @spec step_failed(String.t(), String.t(), map()) :: t()
  def step_failed(step_name, message, details \\ %{}) do
    %__MODULE__{
      type: :step_failed,
      message: message,
      step_name: step_name,
      details: details
    }
  end

  @doc """
  Creates a step timeout error.
  """
  @spec step_timeout(String.t(), non_neg_integer()) :: t()
  def step_timeout(step_name, timeout_ms) do
    %__MODULE__{
      type: :step_timeout,
      message: "Step exceeded timeout of #{timeout_ms}ms",
      step_name: step_name,
      details: %{timeout_ms: timeout_ms}
    }
  end

  @doc """
  Creates an executor crash error.
  """
  @spec executor_crash(term()) :: t()
  def executor_crash(reason) do
    %__MODULE__{
      type: :executor_crash,
      message: "DAG executor crashed: #{inspect(reason)}",
      step_name: nil,
      details: %{reason: reason}
    }
  end

  @doc """
  Creates a condition evaluation error.
  """
  @spec condition_error(String.t(), String.t(), term()) :: t()
  def condition_error(step_name, condition, reason) do
    %__MODULE__{
      type: :condition_error,
      message: "Condition evaluation failed: #{condition}",
      step_name: step_name,
      details: %{condition: condition, reason: reason}
    }
  end

  @doc """
  Creates a cancelled error.
  """
  @spec cancelled(String.t() | nil) :: t()
  def cancelled(reason \\ nil) do
    message = if reason, do: "Execution cancelled: #{reason}", else: "Execution cancelled by user"

    %__MODULE__{
      type: :cancelled,
      message: message,
      step_name: nil,
      details: %{reason: reason}
    }
  end

  @doc """
  Creates an aborted error (due to step failure in abort mode).
  """
  @spec aborted(String.t(), String.t()) :: t()
  def aborted(step_name, reason) do
    %__MODULE__{
      type: :aborted,
      message: "Execution aborted due to step failure: #{reason}",
      step_name: step_name,
      details: %{reason: reason}
    }
  end

  @doc """
  Converts an error tuple to an ExecutionError.
  """
  @spec from_tuple({:error, term()}, String.t() | nil) :: t()
  def from_tuple({:error, reason}, step_name \\ nil) do
    message = format_reason(reason)

    %__MODULE__{
      type: :step_failed,
      message: message,
      step_name: step_name,
      details: %{original_reason: reason}
    }
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
