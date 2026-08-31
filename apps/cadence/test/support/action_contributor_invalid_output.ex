defmodule Cadence.TestActionContributors.InvalidOutput do
  @moduledoc false

  def application_key, do: "synthetic_invalid_output"
  def action_provider, do: Cadence.TestActionProviders.InvalidOutput
end
