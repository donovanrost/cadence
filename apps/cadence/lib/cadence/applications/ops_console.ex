defmodule Cadence.Applications.OpsConsole do
  @moduledoc """
  The Ops Console platform application: always installed on a mission, headless like every
  application. Its data-source writes (`Cadence.Applications.OpsConsole.Actions`) are what the
  console's Data Sources screens call.
  """

  alias Cadence.Applications.ApplicationDefinition

  @identity %{
    application_key: "ops_console",
    application_version: 1,
    package_id: "cadence.ops_console",
    package_version: 1
  }

  @spec identity() :: map()
  def identity, do: @identity

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Ops Console",
      description: "Mission operations, dashboard runtime, evidence, and control surfaces.",
      trust: :first_party,
      installation_policy: :platform,
      availability: :available,
      installable_scopes: [:mission],
      settings_sections: []
    }
  end
end
