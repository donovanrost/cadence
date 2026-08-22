defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStartPresentation do
  @moduledoc false

  @type t :: %__MODULE__{
          present: boolean(),
          next_action: binary(),
          eligible_count: binary(),
          eligible: binary(),
          expected_jobs: binary(),
          reason: binary() | nil,
          preview: binary() | nil,
          state: binary() | nil,
          available_when: binary() | nil,
          guidance: binary()
        }

  defstruct present: false,
            next_action: "inspect_group_state",
            eligible_count: "0",
            eligible: "false",
            expected_jobs: "0",
            reason: nil,
            preview: nil,
            state: nil,
            available_when: nil,
            guidance: "Inspect group state before dispatching jobs for this workflow group."

  @spec build(map() | nil, map() | nil) :: t()
  def build(workflow_context, workflow_controls)
      when is_map(workflow_context) and is_map(workflow_controls) do
    case start_action(workflow_controls) do
      nil ->
        %__MODULE__{}

      action ->
        %__MODULE__{
          present: true,
          next_action: next_action(action),
          eligible_count: count(action),
          eligible: bool_attr(action_value(action, :eligible?)),
          expected_jobs: count(action),
          reason: action_value(action, :reason),
          preview: action_value(action, :preview),
          state: action_value(action, :state_summary),
          available_when: action_value(action, :available_when),
          guidance: guidance(workflow_context, action)
        }
    end
  end

  def build(_workflow_context, _workflow_controls), do: %__MODULE__{}

  defp start_action(workflow_controls) do
    workflow_controls
    |> Map.get(:group_stage_actions, [])
    |> Enum.find(&(action_value(&1, :stage) == "started"))
  end

  defp next_action(action) do
    cond do
      action_value(action, :eligible?) == true ->
        "start_eligible_items"

      action_value(action, :reason) == "no_eligible_group_items" ->
        "wait_for_eligibility"

      true ->
        "inspect_group_state"
    end
  end

  defp guidance(workflow_context, action) do
    review_count = Map.get(workflow_context, :comparison_review_open_count)

    cond do
      action_value(action, :eligible?) == true ->
        review_prefix(review_count) <>
          (action_value(action, :preview) || "Start eligible workflow items in this group.")

      action_value(action, :reason) == "no_eligible_group_items" ->
        review_prefix(review_count) <>
          "No items are startable yet; approve eligible items before dispatching jobs."

      true ->
        review_prefix(review_count) <>
          "Inspect group state before dispatching jobs for this workflow group."
    end
  end

  defp count(action) do
    case action_value(action, :eligible_count) do
      count when is_integer(count) -> Integer.to_string(count)
      count when is_binary(count) and count != "" -> count
      _other -> "0"
    end
  end

  defp action_value(action, key) when is_map(action), do: Map.get(action, key)
  defp action_value(_action, _key), do: nil

  defp bool_attr(true), do: "true"
  defp bool_attr(_value), do: "false"

  defp review_prefix(value) when is_binary(value) and value != "",
    do: "#{value} review findings are attached. "

  defp review_prefix(_value), do: ""
end
