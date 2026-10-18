defmodule Cadence.TestActionContributors.Beta do
  @moduledoc false

  def application_key, do: "synthetic_beta"
  def action_provider, do: Cadence.TestActionProviders.Beta
end
