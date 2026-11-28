defmodule Cadence.TestSupport.ContentBasisCanary do
  @moduledoc "Test assertion that every struct field has a reviewed identity role."

  import ExUnit.Assertions

  @spec assert_struct_fields!(module(), binary(), pos_integer(), keyword()) :: true
  def assert_struct_fields!(module, name, version, opts) do
    included = Keyword.fetch!(opts, :included)
    excluded = Keyword.fetch!(opts, :excluded)
    actual = module.__struct__() |> Map.from_struct() |> Map.keys() |> Enum.sort()
    listed = included ++ excluded

    assert Enum.uniq(listed) == listed,
           "#{name}:v#{version} lists a struct field more than once"

    assert Enum.sort(listed) == actual,
           "#{inspect(module)} changed fields for #{name}:v#{version}; decide whether each " <>
             "new field enters the identity (then bump the basis version) or is excluded"
  end
end
