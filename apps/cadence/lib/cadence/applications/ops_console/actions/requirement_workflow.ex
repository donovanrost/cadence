defmodule Cadence.Applications.OpsConsole.Actions.RequirementWorkflow do
  @moduledoc "Displayed requirement admission and governed requirement contribution effects."
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning
  @actions ~w(plan create-plan)
  @rejected ~w(forbidden authenticated_user_required scope_mismatch invalid_requirement_evidence
    invalid_requirement_decision contact_requirement_inactive stale_contact_requirement_evidence
    planning_run_scope_mismatch planning_run_requirement_version_mismatch
    contact_plan_planning_run_incomplete opportunity_scope_mismatch invalid_opportunity_selection
    contact_requirement_not_found contact_requirement_version_not_found)a
  def actions, do: @actions

  def admitted?(%{"requirement" => requirement, "context" => context} = detail, event, input)
      when event in @actions and is_map(input) do
    expected = %{
      "contract_version" => 1,
      "organization_id" => context["organization_id"],
      "mission_id" => context["mission_id"],
      "requirement_id" => requirement["id"],
      "requirement_version" => requirement["version"],
      "content_sha256" => requirement["content_sha256"]
    }

    requirement["lifecycle_state"] == "active" and requirement["direction"] == "downlink" and
      requirement["current_version"] == requirement["version"] and
      input["contact_requirement_id"] == requirement["id"] and
      input["requirement_evidence"] === expected and run_admitted?(detail, event, input)
  end

  def admitted?(_, _, _), do: false

  defp run_admitted?(_, "plan", _), do: true

  defp run_admitted?(%{"selected_run" => %{"id" => id, "state" => state}}, "create-plan", input),
    do: state != "running" and input["planning_run_id"] == id

  defp run_admitted?(_, _, _), do: false

  def execute(scope, mission, event, input) when event in @actions do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "contact_requirement_show",
      surface_version: 1,
      action_id: event,
      params: input
    }

    case ContactPlanning.execute(
           scope,
           HostContext.mission(mission),
           "contact_requirement_show",
           request
         ) do
      {:error, reason} when reason in @rejected -> {:rejected, reason}
      other -> other
    end
  end

  def execute(_, _, _, _), do: {:rejected, :undeclared_action}
end
