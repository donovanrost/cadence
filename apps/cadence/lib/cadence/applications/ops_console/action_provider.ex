defmodule Cadence.Applications.OpsConsole.ActionProvider do
  @moduledoc "Fail-closed action seam retained until the Ops LiveView cutover is composed."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Auth.Scope

  @application_key "ops_console"

  @impl true
  def application_key, do: @application_key

  @impl true
  def execute(
        %Scope{},
        %HostContext{placement: :mission},
        %ActionRequest{application_key: @application_key, application_version: 1}
      ) do
    {:error, :ops_console_liveview_action_pending_central_cutover}
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  @impl true
  def result(value), do: value
end
