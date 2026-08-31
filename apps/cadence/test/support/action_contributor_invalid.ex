defmodule Cadence.TestActionContributors.Invalid do
  @moduledoc false

  def application_key, do: "synthetic_invalid"
  def action_provider, do: nil
end
