defmodule CadenceWeb.API.CommandingJSON do
  @moduledoc "Commanding response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON.Commanding, as: LegacyJSON

  defdelegate command_stage(value), to: LegacyJSON
  defdelegate staged_command_item(value), to: LegacyJSON
  defdelegate command_request(value), to: LegacyJSON
  defdelegate command_approval(value), to: LegacyJSON
  defdelegate command_queue_entry(value), to: LegacyJSON
  defdelegate command_release_attempt(value), to: LegacyJSON
  defdelegate command_verifier_instance(value), to: LegacyJSON
  defdelegate command_request_decision_result(value), to: LegacyJSON
  defdelegate command_request_enqueue_result(value), to: LegacyJSON
  defdelegate command_queue_entry_release_result(value), to: LegacyJSON
end
