defmodule Cadence.TestActionContributors.Alpha do
  @moduledoc false

  def application_key, do: "synthetic_alpha"
  def action_provider, do: Cadence.TestActionProviders.Alpha
end
