defmodule Cadence.TestReleaseContributors.Exiting do
  @moduledoc false

  def release_contributions, do: exit(:synthetic_release_contributor_exit)
end
