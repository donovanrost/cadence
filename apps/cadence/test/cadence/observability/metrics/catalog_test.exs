defmodule Cadence.Observability.Metrics.CatalogTest do
  use ExUnit.Case, async: true

  alias Cadence.Observability.Metrics.Catalog

  test "all metric definitions are valid and dimensionally bounded" do
    definitions = Catalog.definitions()

    assert Enum.all?(definitions, &Catalog.valid_definition?/1)

    refute Enum.any?(definitions, fn definition ->
             Enum.any?(definition.attributes, &MapSet.member?(Catalog.forbidden_attributes(), &1))
           end)
  end

  test "catalog event list is unique and excludes sampler-only metrics" do
    events = Catalog.events()

    assert events == Enum.uniq(events)
    assert Enum.all?(events, &is_list/1)
  end
end
