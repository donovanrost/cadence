defmodule Cadence.TestActionProviders.InvalidOutput do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "synthetic_invalid_output"

  @impl true
  def execute(_scope, _host_context, _request), do: {:ok, self()}
end
