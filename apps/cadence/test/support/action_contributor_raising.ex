defmodule Cadence.TestActionContributors.Raising do
  @moduledoc false

  def application_key, do: raise("synthetic contributor failure")
  def action_provider, do: Cadence.TestActionProviders.Alpha
end
