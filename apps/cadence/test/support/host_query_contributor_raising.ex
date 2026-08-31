defmodule Cadence.TestHostQueryContributors.Raising do
  @moduledoc false

  def host_query_providers, do: raise("synthetic contributor failure")
end
