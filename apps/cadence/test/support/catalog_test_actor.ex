defmodule Cadence.TestSupport.CatalogTestActor do
  @moduledoc """
  The explicit system actor test fixtures import catalogs as (lead 11-17): an import must name who
  ran it (`Catalog.Actor`), and a fixture is not a person, so it never counts as an importer for
  the model approval gate. A test about importers passes a user's actor instead.
  """

  alias Cadence.Catalog.Actor

  @spec system() :: Actor.t()
  # #513: a system actor names the person who ran it; for fixtures, a runner id no test approves as.
  def system,
    do: Actor.system("test:catalog-fixture", "Cadence test fixture", "test-fixture-runner")

  @doc "`opts` with the test system actor as `requested_by`, unless it names one already."
  @spec opts(keyword()) :: keyword()
  def opts(opts \\ []), do: Keyword.put_new(opts, :requested_by, system())
end
