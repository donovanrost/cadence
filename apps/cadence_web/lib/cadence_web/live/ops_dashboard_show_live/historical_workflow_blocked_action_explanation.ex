defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowBlockedActionExplanation do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: String.t() | nil,
          label: String.t() | nil,
          reason: String.t() | nil,
          explanation: String.t() | nil,
          state_summary: String.t() | nil,
          available_when: String.t() | nil
        }

  defstruct [:id, :kind, :label, :reason, :explanation, :state_summary, :available_when]

  @spec normalize(map() | term()) :: t()
  def normalize(attrs) when is_map(attrs) do
    %__MODULE__{
      id: text_value(Map.get(attrs, :id)),
      kind: text_value(Map.get(attrs, :kind)),
      label: text_value(Map.get(attrs, :label)),
      reason: text_value(Map.get(attrs, :reason)),
      explanation: text_value(Map.get(attrs, :explanation)),
      state_summary: text_value(Map.get(attrs, :state_summary)),
      available_when: text_value(Map.get(attrs, :available_when))
    }
  end

  def normalize(_attrs), do: %__MODULE__{}

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil
end
