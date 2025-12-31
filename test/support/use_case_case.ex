defmodule Cadence.UseCaseCase do
  @moduledoc """
  Test case for application-layer use cases with in-memory adapters.

  Use this for unit-style tests that exercise application services while
  avoiding the database.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Cadence.PureCase, async: false

      @moduletag :use_case
    end
  end

  setup do
    cleanup = Cadence.TestSupport.enable_in_memory_adapters()
    on_exit(cleanup)
    :ok
  end
end
