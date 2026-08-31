defmodule Cadence.TestHostQueryContributors.OversizedOutput do
  @moduledoc false

  def host_query_providers, do: [Cadence.TestHostQueryProviders.OversizedOutput]
end
