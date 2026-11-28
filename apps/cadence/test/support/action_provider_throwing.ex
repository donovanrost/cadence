defmodule Cadence.TestActionProviders.Throwing do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "ops_console"

  @impl true
  def execute(_scope, _host_context, _request), do: throw(:synthetic_action_provider_throw)
end
