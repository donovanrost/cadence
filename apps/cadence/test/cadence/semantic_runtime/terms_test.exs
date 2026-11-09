defmodule Cadence.SemanticRuntime.TermsTest do
  use ExUnit.Case, async: false

  alias Cadence.SemanticRuntime.Terms

  # Built at runtime so this test module doesn't create the atom by mentioning it.
  @field_name "semantic_runtime_probe_" <> "field_q7x"
  @module_name "Elixir.Cadence.SemanticRuntime." <> "TestProbe"

  test "a commit holding a not-yet-loaded semantic runtime struct decodes after loading it" do
    refute :code.is_loaded(String.to_atom(@module_name))
    assert_raise ArgumentError, fn -> String.to_existing_atom(@field_name) end

    commit = probe_commit()

    # The dev failure: a safe decode refuses the atom while the struct's module isn't loaded.
    assert_raise ArgumentError, fn -> :erlang.binary_to_term(commit, [:safe]) end

    assert {:ok, %{__struct__: module} = probe} = Terms.decode(commit)
    assert Atom.to_string(module) == @module_name
    assert Map.fetch!(probe, String.to_existing_atom(@field_name)) == 42
  end

  test "an atom no semantic runtime module defines still fails closed" do
    assert {:error, :semantic_runtime_commit_decode_failed} =
             Terms.decode(map_term([{"no_module_defines_" <> "this_atom_z9", 1}]))
  end

  test "terms round-trip" do
    term = %Cadence.SemanticRuntime.Result{}
    assert {:ok, ^term} = term |> Terms.encode() |> Terms.decode()
  end

  # %{__struct__: TestProbe, <field>: 42} in external term format, with atoms written as
  # SMALL_ATOM_UTF8_EXT so no atom is created while building it.
  defp probe_commit, do: map_term([{"__struct__", {:atom, @module_name}}, {@field_name, 42}])

  defp map_term(pairs) do
    body = Enum.map_join(pairs, fn {key, value} -> atom(key) <> value(value) end)
    <<131, 116, length(pairs)::32>> <> body
  end

  defp atom(name), do: <<119, byte_size(name)>> <> name
  defp value({:atom, name}), do: atom(name)
  defp value(int) when is_integer(int) and int in 0..255, do: <<97, int>>
end
