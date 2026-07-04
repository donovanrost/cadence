defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryFormPresentation do
  @moduledoc false

  @group_name "historical_workflow_group"
  @submit_event "record_historical_workflow_group_stage"
  @replacement_scope "replacement_corrections"

  @context_fields [
    {"workflow", :workflow},
    {"request_group_id", :request_group_id},
    {"realm", :realm},
    {"data_source_id", :data_source_id},
    {"source_binding_id", :source_binding_id},
    {"dashboard_id", :dashboard_id},
    {"dashboard_version", :dashboard_version},
    {"dashboard_time_mode", :dashboard_time_mode},
    {"dashboard_replay_run_id", :dashboard_replay_run_id},
    {"dashboard_data_view", :dashboard_data_view},
    {"dashboard_limit_mode", :dashboard_limit_mode}
  ]

  @empty_form %{
    present: false,
    id: nil,
    submit_event: @submit_event,
    request_group_id: nil,
    stage: nil,
    eligible: "false",
    count: "0",
    reason: nil,
    preview: nil,
    action_id: nil,
    disabled_bool: true,
    correction_tasks: nil,
    hidden_fields: []
  }

  @type hidden_field :: %{name: binary(), value: binary()}
  @type form :: %{
          present: boolean(),
          id: binary() | nil,
          submit_event: binary(),
          request_group_id: binary() | nil,
          stage: binary() | nil,
          eligible: binary(),
          count: binary(),
          reason: binary() | nil,
          preview: binary() | nil,
          action_id: binary() | nil,
          disabled_bool: boolean(),
          correction_tasks: binary() | nil,
          hidden_fields: [hidden_field()]
        }

  @type t :: %__MODULE__{
          replacement_advancement: form(),
          completion: form()
        }

  defstruct replacement_advancement: @empty_form,
            completion: @empty_form

  @spec build(map() | nil, map() | nil) :: t()
  def build(workflow_context, replacement_recovery)
      when is_map(workflow_context) and is_map(replacement_recovery) do
    %__MODULE__{
      replacement_advancement:
        replacement_advancement_form(
          workflow_context,
          Map.get(replacement_recovery, :replacement_action)
        ),
      completion:
        completion_form(
          workflow_context,
          Map.get(replacement_recovery, :completion_action)
        )
    }
  end

  def build(_workflow_context, _replacement_recovery), do: %__MODULE__{}

  defp replacement_advancement_form(workflow_context, %{present: true} = action) do
    fields =
      workflow_context
      |> context_hidden_fields()
      |> append_field("reason", Map.get(action, :submit_reason))
      |> append_field("group_transition_scope", @replacement_scope)
      |> append_field("group_correction_tasks", Map.get(action, :correction_tasks))
      |> append_field("confirmed", "confirmed")

    action_form(
      "dashboard-historical-workflow-group-recovery-advance-corrected-form",
      workflow_context,
      action,
      fields
    )
  end

  defp replacement_advancement_form(_workflow_context, _action), do: @empty_form

  defp completion_form(workflow_context, %{present: true} = action) do
    fields =
      workflow_context
      |> context_hidden_fields()
      |> append_field("reason", Map.get(action, :submit_reason))
      |> append_field("confirmed", "confirmed")

    action_form(
      "dashboard-historical-workflow-group-recovery-complete-form",
      workflow_context,
      action,
      fields
    )
  end

  defp completion_form(_workflow_context, _action), do: @empty_form

  defp action_form(id, workflow_context, action, fields) do
    %{
      present: true,
      id: id,
      submit_event: @submit_event,
      request_group_id: text_value(Map.get(workflow_context, :request_group_id)),
      stage: Map.get(action, :stage),
      eligible: Map.get(action, :eligible, "false"),
      count: Map.get(action, :count, "0"),
      reason: Map.get(action, :reason),
      preview: Map.get(action, :preview),
      action_id: Map.get(action, :id),
      disabled_bool: Map.get(action, :disabled_bool, true),
      correction_tasks: Map.get(action, :correction_tasks),
      hidden_fields: fields
    }
  end

  defp context_hidden_fields(workflow_context) do
    Enum.map(@context_fields, fn {field, key} ->
      hidden_field(field, Map.get(workflow_context, key))
    end)
  end

  defp append_field(fields, field, value), do: fields ++ [hidden_field(field, value)]

  defp hidden_field(field, value) do
    %{
      name: "#{@group_name}[#{field}]",
      value: text_value(value)
    }
  end

  defp text_value(value) when is_binary(value), do: value
  defp text_value(nil), do: ""
  defp text_value(value), do: to_string(value)
end
