defmodule Cadence.TestActionProviders.Exiting do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "ops_console"

  @impl true
  def execute(_scope, _host_context, _request), do: exit(:synthetic_action_provider_exit)
end
