defmodule Cadence.SemanticRuntime.TermsTest do
  use ExUnit.Case, async: false

  alias Cadence.SemanticRuntime.Terms

  # Built at runtime so this test module doesn't create the atom by mentioning it.
  @field_name "semantic_runtime_probe_" <> "field_q7x"
  @module_name "Elixir.Cadence.SemanticRuntime." <> "TestProbe"

  # Runs in a fresh peer VM: any earlier test in this VM that reaches Terms.decode's fallback
  # loads every Cadence.SemanticRuntime module (TestProbe included), and atoms are never freed,
  # so "not yet loaded" can only be guaranteed in a VM nothing else has run in.
  test "a commit holding a not-yet-loaded semantic runtime struct decodes after loading it" do
    peer = start_fresh_peer()
    module = String.to_atom(@module_name)
    commit = probe_commit()

    # Load only the :cadence application spec (Terms reads its module list); no module loads.
    assert :ok = :peer.call(peer, :application, :load, [:cadence])
    refute :peer.call(peer, :code, :is_loaded, [module])

    assert_raise ArgumentError, fn ->
      :peer.call(peer, :erlang, :binary_to_existing_atom, [@field_name, :utf8])
    end

    # The dev failure: a safe decode refuses the atom while the struct's module isn't loaded.
    assert_raise ArgumentError, fn ->
      :peer.call(peer, :erlang, :binary_to_term, [commit, [:safe]])
    end

    assert {:ok, %{__struct__: ^module} = probe} = :peer.call(peer, Terms, :decode, [commit])
    assert Map.fetch!(probe, String.to_existing_atom(@field_name)) == 42
    assert {:file, _path} = :peer.call(peer, :code, :is_loaded, [module])
  end

  test "an atom no semantic runtime module defines still fails closed" do
    assert {:error, :semantic_runtime_commit_decode_failed} =
             Terms.decode(map_term([{"no_module_defines_" <> "this_atom_z9", 1}]))
  end

  test "terms round-trip" do
    term = %Cadence.SemanticRuntime.Result{}
    assert {:ok, ^term} = term |> Terms.encode() |> Terms.decode()
  end

  # A VM with this one's code paths and nothing loaded beyond boot. :standard_io keeps it off
  # distribution, so the test needs neither epmd nor a named node. Unlinked, so on_exit (which
  # runs after the test process exits) is the one place that stops it. Boot gets 45 s, not
  # :peer's default 15 s, because a loaded machine can take longer than that.
  defp start_fresh_peer do
    {:ok, peer, _node} =
      :peer.start(%{
        connection: :standard_io,
        args: [~c"-pa" | :code.get_path()],
        wait_boot: 45_000
      })

    on_exit(fn -> :peer.stop(peer) end)
    peer
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
