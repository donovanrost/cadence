defmodule Cadence.Catalog.Command.StateEffect do
  @moduledoc """
  Portable state transition caused by successful command execution.

  Effects identify their target by reference rather than by a
  persistence-owned row. A simulator can resolve a target such as `HK.mode`,
  while another consumer may project the same effect into its own state model.
  """

  alias Cadence.Catalog.Command.Normalize
  alias Cadence.Catalog.Ids

  @type operation :: :set | :increment | :decrement | :toggle

  @type t :: %__MODULE__{
          effect_id: binary(),
          target_ref: binary(),
          operation: operation(),
          argument_id: binary() | nil,
          value: term(),
          metadata: map()
        }

  defstruct [
    :effect_id,
    :target_ref,
    :operation,
    :argument_id,
    :value,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      effect_id: Normalize.get(attrs, :effect_id, Ids.new("command_state_effect")),
      target_ref: Normalize.fetch!(attrs, :target_ref),
      operation: Normalize.get(attrs, :operation, :set) |> normalize_operation(),
      argument_id: argument_ref(Normalize.get(attrs, :argument_ref)),
      value: Normalize.get(attrs, :value),
      metadata: Normalize.get(attrs, :metadata, %{})
    }
  end

  defp argument_ref(argument_id) when is_binary(argument_id), do: argument_id
  defp argument_ref(_other), do: nil

  defp normalize_operation(:set), do: :set
  defp normalize_operation("set"), do: :set
  defp normalize_operation(:increment), do: :increment
  defp normalize_operation("increment"), do: :increment
  defp normalize_operation(:decrement), do: :decrement
  defp normalize_operation("decrement"), do: :decrement
  defp normalize_operation(:toggle), do: :toggle
  defp normalize_operation("toggle"), do: :toggle
  defp normalize_operation(_other), do: :set
end
