defmodule Cadence.UseCaseCase do
  @moduledoc """
  Test case for application-layer use cases with in-memory adapters.

  Use this for unit-style tests that exercise application services while
  avoiding the database.
  """

  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      use Cadence.PureCase, async: false

      @moduletag :use_case
    end
  end

  setup do
    # Some use cases emit Outbox events, which write to the database even when
    # domain repositories are swapped to in-memory adapters.
    owner = Sandbox.start_owner!(Cadence.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    cleanup = Cadence.TestSupport.enable_in_memory_adapters()
    on_exit(cleanup)
    :ok
  end
end
