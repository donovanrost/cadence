defmodule Cadence.TestReleaseContributors.Malformed do
  @moduledoc false

  def release_contributions, do: [:not_a_release_contribution]
end
