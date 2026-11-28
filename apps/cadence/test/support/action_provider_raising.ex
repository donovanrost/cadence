defmodule Cadence.TestActionProviders.Raising do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "ops_console"

  @impl true
  def execute(_scope, _host_context, _request), do: raise("synthetic action provider failure")
end
