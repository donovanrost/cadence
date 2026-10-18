defmodule Cadence.TestReleaseContributors.Throwing do
  @moduledoc false

  def release_contributions, do: throw(:synthetic_release_contributor_throw)
end
