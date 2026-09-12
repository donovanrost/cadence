defmodule Cadence.Applications.OpsConsole.Actions.RequirementTemplateWorkflow do
  @moduledoc "Governed recurring-need creation and exact reviewed lifecycle transitions."
  alias Cadence.Applications.OpsConsole.Actions.RequirementTemplateInput, as: Input
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.ContactRequirementTemplates, as: Templates
  @actions ~w(validate-template create-template pause-template activate-template close-template)
  def actions, do: @actions

  def execute(scope, mission, "validate-template", input) do
    case prepare(scope, mission, input) do
      {:ok, _, _} -> {:ok, %{valid: true, feedback: []}}
      {:error, reason} -> {:ok, %{valid: false, feedback: [feedback(reason)]}}
    end
  end

  def execute(scope, mission, "create-template", input) do
    with :ok <- authorize(scope, mission),
         {:ok, form} <- Input.admit(input),
         {:ok, attrs} <- Input.parse(form),
         {:ok, template, version} <- Templates.create(scope, mission, attrs) do
      {:ok,
       %{
         contract_version: 1,
         actor_id: scope.user.user_id,
         reference: Templates.reference(template, version)
       }}
    else
      {:error, reason} -> {:rejected, [feedback(reason)]}
    end
  end

  def execute(scope, mission, action, %{"reference" => reference} = input)
      when action in ~w(pause-template activate-template close-template) and map_size(input) == 1 and
             is_map(reference) do
    with :ok <- authorize(scope, mission),
         true <-
           map_size(reference) == 8 and reference["organization_id"] == scope.organization_id and
             reference["mission_id"] == mission,
         id when is_binary(id) <- reference["template_id"],
         version when is_integer(version) and version > 0 <- reference["version"],
         {:ok, updated} <- transition(action, scope, mission, id, version, reference) do
      {:ok,
       %{
         contract_version: 1,
         actor_id: scope.user.user_id,
         reference:
           reference
           |> Map.put("lifecycle_state", Atom.to_string(updated.lifecycle_state))
           |> Map.put("lifecycle_changed_at", DateTime.to_iso8601(updated.lifecycle_changed_at))
           |> Map.put("lifecycle_changed_by", updated.lifecycle_changed_by)
       }}
    else
      {:error, reason} -> {:rejected, [feedback(reason)]}
      _ -> {:rejected, ["invalid_input"]}
    end
  end

  def execute(_, _, _, _), do: {:rejected, ["invalid_input"]}

  defp prepare(scope, mission, input) do
    with :ok <- authorize(scope, mission),
         {:ok, form} <- Input.admit(input),
         {:ok, attrs} <- Input.parse(form) do
      Templates.prepare_create(scope, mission, attrs)
    end
  end

  defp authorize(scope, mission) do
    if is_nil(scope.mission_id) or scope.mission_id == mission,
      do:
        Policy.authorize(scope, :manage_mission, %{
          organization_id: scope.organization_id,
          mission_id: mission
        }),
      else: {:error, :scope_mismatch}
  end

  defp transition("pause-template", scope, mission, id, version, reference),
    do:
      Templates.pause(scope, mission, id, version, "Paused by Ops Console",
        reviewed_evidence: reference
      )

  defp transition("activate-template", scope, mission, id, version, reference),
    do:
      Templates.activate(scope, mission, id, version, "Activated by Ops Console",
        reviewed_evidence: reference
      )

  defp transition("close-template", scope, mission, id, version, reference),
    do:
      Templates.close(scope, mission, id, version, "Closed by Ops Console",
        reviewed_evidence: reference
      )

  defp feedback(reason)
       when reason in [:forbidden, :scope_mismatch, :authenticated_actor_required],
       do: "forbidden"

  defp feedback(reason)
       when reason in [
              :stale_contact_requirement_template_version,
              :stale_contact_requirement_template_evidence,
              :invalid_template_lifecycle_transition
            ],
       do: "stale_evidence"

  defp feedback(:contact_requirement_template_spacecraft_not_found), do: "spacecraft_unavailable"

  defp feedback(reason) when reason in [:invalid_datetime, :invalid_daily_time],
    do: "invalid_time"

  defp feedback(reason)
       when reason in [:invalid_integer, :invalid_positive_integer, :invalid_nonnegative_integer],
       do: "invalid_number"

  defp feedback(:invalid_schedule_type), do: "invalid_schedule"
  defp feedback(:required_fields), do: "required_fields"
  defp feedback(:malformed_input), do: "invalid_input"
  defp feedback(_), do: "invalid_template"
end
