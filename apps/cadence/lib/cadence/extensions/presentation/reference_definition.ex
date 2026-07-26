defmodule Cadence.Extensions.Presentation.ReferenceDefinition do
  @moduledoc """
  Versioned lookup contract for one host-rendered reference field.

  Provider identities are compiled data resolved through a host registry. They
  never carry query functions, modules, or application-owned rendering code.
  """

  @type t :: %__MODULE__{
          provider_id: binary(),
          version: pos_integer(),
          mode: :select | :search,
          result_limit: pos_integer()
        }

  @enforce_keys [:provider_id, :version]
  defstruct [:provider_id, :version, mode: :select, result_limit: 25]

  @max_result_limits %{select: 500, search: 50}

  @spec validate(t()) :: :ok | {:error, :invalid_reference_definition}
  def validate(%__MODULE__{} = reference) do
    max_result_limit = Map.get(@max_result_limits, reference.mode)

    if valid_text?(reference.provider_id) and is_integer(reference.version) and
         reference.version > 0 and is_integer(reference.result_limit) and
         is_integer(max_result_limit) and reference.result_limit > 0 and
         reference.result_limit <= max_result_limit do
      :ok
    else
      {:error, :invalid_reference_definition}
    end
  end

  def validate(_reference), do: {:error, :invalid_reference_definition}

  @spec max_result_limit(:select | :search) :: pos_integer()
  def max_result_limit(mode) when mode in [:select, :search],
    do: Map.fetch!(@max_result_limits, mode)

  defp valid_text?(value), do: is_binary(value) and value != ""
end
