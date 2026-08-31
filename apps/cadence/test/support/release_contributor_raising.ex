defmodule Cadence.TestReleaseContributors.Raising do
  @moduledoc false

  def release_contributions, do: raise("synthetic release contributor failure")
end
