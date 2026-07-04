defmodule Cadence.Dashboards.ValidationResult do
  @moduledoc """
  Structured validation result for dashboard documents.
  """

  @type issue :: %{
          code: atom(),
          details: map()
        }

  @type t :: %__MODULE__{
          valid?: boolean(),
          errors: [issue()],
          warnings: [issue()]
        }

  defstruct valid?: true, errors: [], warnings: []

  @spec add_error(t(), atom(), map()) :: t()
  def add_error(%__MODULE__{} = result, code, details) when is_atom(code) and is_map(details) do
    %{result | valid?: false, errors: result.errors ++ [%{code: code, details: details}]}
  end

  @spec add_warning(t(), atom(), map()) :: t()
  def add_warning(%__MODULE__{} = result, code, details) when is_atom(code) and is_map(details) do
    %{result | warnings: result.warnings ++ [%{code: code, details: details}]}
  end
end
