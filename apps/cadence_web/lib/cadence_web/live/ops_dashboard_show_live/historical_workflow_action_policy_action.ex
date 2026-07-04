defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionPolicyAction do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: String.t() | nil,
          stage: String.t() | nil,
          label: String.t() | nil,
          icon: String.t() | nil,
          class: String.t() | nil,
          eligible?: boolean(),
          disabled?: boolean(),
          eligible_count: non_neg_integer(),
          reason: String.t() | nil,
          preview: String.t() | nil,
          explanation: String.t() | nil,
          state_summary: String.t() | nil,
          correction_tasks: String.t() | nil,
          available_when: String.t() | nil
        }

  defstruct [
    :id,
    :kind,
    :stage,
    :label,
    :icon,
    :class,
    :reason,
    :preview,
    :explanation,
    :state_summary,
    :correction_tasks,
    :available_when,
    eligible?: false,
    disabled?: true,
    eligible_count: 0
  ]

  @spec normalize(map() | term()) :: t()
  def normalize(action) when is_map(action) do
    %__MODULE__{
      id: text_value(Map.get(action, :id)),
      kind: text_value(Map.get(action, :kind)),
      stage: text_value(Map.get(action, :stage)),
      label: text_value(Map.get(action, :label)),
      icon: text_value(Map.get(action, :icon)),
      class: text_value(Map.get(action, :class)),
      eligible?: truthy?(Map.get(action, :eligible?)),
      disabled?: truthy?(Map.get(action, :disabled?)),
      eligible_count: count_value(Map.get(action, :eligible_count)),
      reason: text_value(Map.get(action, :reason)),
      preview: text_value(Map.get(action, :preview)),
      explanation: text_value(Map.get(action, :explanation)),
      state_summary: text_value(Map.get(action, :state_summary)),
      correction_tasks: text_value(Map.get(action, :correction_tasks)),
      available_when: text_value(Map.get(action, :available_when))
    }
  end

  def normalize(_action), do: %__MODULE__{}

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp truthy?(true), do: true
  defp truthy?(_value), do: false

  defp count_value(value) when is_integer(value) and value >= 0, do: value

  defp count_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp count_value(_value), do: 0
end
