defmodule CadenceWeb.API.CommandingParams do
  @moduledoc "Commanding request parsing boundary."

  alias CadenceWeb.ControlPlaneParams.Commanding, as: LegacyParams

  defdelegate command_stage(organization_id, mission_id, params, opts \\ []), to: LegacyParams
  defdelegate command_stage(existing_command_stage, params), to: LegacyParams
  defdelegate command_stage_filters(params), to: LegacyParams

  defdelegate staged_command_item(organization_id, mission_id, command_stage_id, params),
    to: LegacyParams

  defdelegate staged_command_item(existing_staged_command_item, params), to: LegacyParams
  defdelegate staged_command_item_filters(params), to: LegacyParams
  defdelegate command_stage_submission(params, opts \\ []), to: LegacyParams
  defdelegate command_request(organization_id, mission_id, params, opts \\ []), to: LegacyParams
  defdelegate command_request_filters(params), to: LegacyParams
  defdelegate command_approval(command_request_id, params, opts \\ []), to: LegacyParams
  defdelegate command_approval_filters(params), to: LegacyParams
  defdelegate command_queue_entry(params, opts \\ []), to: LegacyParams
  defdelegate command_queue_entry_filters(params), to: LegacyParams
  defdelegate command_release_attempt(params, opts \\ []), to: LegacyParams
  defdelegate command_release_attempt_filters(params), to: LegacyParams
  defdelegate command_verifier_instance_filters(params), to: LegacyParams
end
