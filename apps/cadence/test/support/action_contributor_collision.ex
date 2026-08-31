defmodule Cadence.TestActionContributors.Collision do
  @moduledoc false

  def application_key, do: "synthetic_alpha"
  def action_provider, do: Cadence.TestActionProviders.Collision
end
