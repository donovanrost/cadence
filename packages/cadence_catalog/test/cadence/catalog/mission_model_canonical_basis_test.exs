defmodule Cadence.Catalog.MissionModelCanonicalBasisTest do
  # Golden vectors for the versioned hash basis (#166, DECISIONS #108 as amended by #112). The JSON
  # literals are written from the spec by hand, and each hash literal is `shasum -a 256` of that
  # JSON, computed outside this code. Moving any of them means the encoding changed: every stored
  # hash built on it moves, so bump the affected types' basis versions instead.
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Canonical

  @flat {:mission_model_layer, 1,
         %{name: "a", count: 2, ok: true, none: nil, kind: :imported, ratio: 0.5}}
  @flat_json ~s(["mission_model_layer",1,[["count",2],["kind","imported"],["name","a"],["none",null],["ok",true],["ratio",0.5]]])
  @flat_sha "4233ef5182b492e76659eb172e279759f77eddf6808723e3da202c4f8393a70a"

  @nested_map {:t, 1, %{m: %{"b" => 1, :a => [2, 1]}}}
  @nested_map_json ~s(["t",1,[["m",{"a":[2,1],"b":1}]]])
  @nested_map_sha "74e37398f4bdf520420e898f289dbdcd8b9f41d4aae4c5f5099243256b4361ca"

  @nested_basis {:outer, 2, %{inner: {:inner, 1, %{x: "y"}}}}
  @nested_basis_json ~s(["outer",2,[["inner",{"$basis":["inner",1,[["x","y"]]]}]]])
  @nested_basis_sha "eb7c90f7e1f73f6ac500f9d0f26d6583b7297f92b9fe61c65d138b7e03139e7b"

  @list {:t, 1, %{l: [2, 1]}}
  @list_json ~s(["t",1,[["l",[2,1]]]])
  @list_sha "30cb774ff0f7a92ed3029d1c464325103c836905d02efb7697a458517a272fda"

  describe "golden vectors" do
    for {name, basis, json, sha} <- [
          {"flat basis", Macro.escape(@flat), @flat_json, @flat_sha},
          {"nested map", Macro.escape(@nested_map), @nested_map_json, @nested_map_sha},
          {"nested basis", Macro.escape(@nested_basis), @nested_basis_json, @nested_basis_sha},
          {"list", Macro.escape(@list), @list_json, @list_sha}
        ] do
      test "#{name} encodes and hashes to its pinned literals" do
        assert Canonical.basis_json(unquote(basis)) == unquote(json)
        assert Canonical.basis_sha256(unquote(basis)) == unquote(sha)
      end
    end

    # More than 32 keys: an Elixir map iterates in hash order above 32, so this fails if nested maps
    # are ever handed to Jason as maps instead of explicitly sorted pairs (domain, 11-19).
    test "a nested map of 40 keys encodes with its keys sorted" do
      keys = Map.new(0..39, &{"k" <> String.pad_leading(Integer.to_string(&1), 2, "0"), &1})

      pairs =
        Enum.map_join(
          0..39,
          ",",
          &~s("k#{String.pad_leading(Integer.to_string(&1), 2, "0")}":#{&1})
        )

      assert Canonical.basis_json({:t, 1, %{m: keys}}) == ~s(["t",1,[["m",{#{pairs}}]]])

      assert Canonical.basis_sha256({:t, 1, %{m: keys}}) ==
               "f752a7c468a3cb18b8b0478d3d1fb449c82ad0de7eadfbfd78b06ba55fc968a2"
    end

    # Raw UTF-8, and "/" unescaped. Vector made with python3:
    # json.dumps(["t", 1, [["s", "Ångström/ok ✓ 日本"]]], ensure_ascii=False, separators=(",", ":"))
    # and sha256 over its UTF-8 bytes.
    test "a non-ASCII value encodes as raw UTF-8" do
      basis = {:t, 1, %{s: "Ångström/ok ✓ 日本"}}
      assert Canonical.basis_json(basis) == ~s(["t",1,[["s","Ångström/ok ✓ 日本"]]])

      assert Canonical.basis_sha256(basis) ==
               "5fa75dd2da6cd3454406aba039d389729b76d40a0bada07c45517a95f943f0e2"
    end

    test "basis_content_id prefixes the hash and carries no version prefix" do
      assert Canonical.basis_content_id("mission_model_layer", @flat) ==
               "mission_model_layer:" <> @flat_sha
    end
  end

  describe "semantics" do
    test "list order matters; map key order doesn't" do
      refute Canonical.basis_sha256({:t, 1, %{l: [1, 2]}}) == @list_sha

      assert Canonical.basis_sha256({:t, 1, %{m: %{a: [2, 1], b: 1}}}) == @nested_map_sha
    end

    test "an atom hashes as its string, as a key and as a value" do
      assert Canonical.basis_sha256({:t, 1, %{k: :v}}) ==
               Canonical.basis_sha256({:t, 1, %{"k" => "v"}})
    end

    test "a map, a pair list and a nested basis never encode alike" do
      hashes = [
        Canonical.basis_sha256({:t, 1, %{v: %{"a" => 1}}}),
        Canonical.basis_sha256({:t, 1, %{v: [["a", 1]]}}),
        Canonical.basis_sha256({:t, 1, %{v: {:a, 1, %{}}}}),
        Canonical.basis_sha256({:t, 1, %{v: ["a", 1, []]}})
      ]

      assert length(Enum.uniq(hashes)) == length(hashes)
    end

    test "the shape and the version are inside the hash" do
      refute Canonical.basis_sha256({:t, 1, %{}}) == Canonical.basis_sha256({:t, 2, %{}})
      refute Canonical.basis_sha256({:t, 1, %{}}) == Canonical.basis_sha256({:u, 1, %{}})
    end

    test "an integer and the equal float differ" do
      refute Canonical.basis_sha256({:t, 1, %{n: 1}}) ==
               Canonical.basis_sha256({:t, 1, %{n: 1.0}})
    end
  end

  describe "refusals" do
    for {name, value} <- [
          {"a struct", quote(do: %URI{host: "x"})},
          {"a DateTime", quote(do: ~U[2026-11-19 05:00:00Z])},
          {"a tuple", quote(do: {1, 2})},
          {"a pid", quote(do: self())},
          {"a reference", quote(do: make_ref())},
          {"a function", quote(do: fn -> :ok end)},
          {"a non-UTF-8 binary", quote(do: <<255>>)}
        ] do
      test "#{name} raises, as a value and inside a list" do
        value = unquote(value)
        assert_raise ArgumentError, fn -> Canonical.basis_sha256({:t, 1, %{v: value}}) end
        assert_raise ArgumentError, fn -> Canonical.basis_sha256({:t, 1, %{v: [value]}}) end
      end
    end

    test "keys that collide as strings raise" do
      assert_raise ArgumentError, fn -> Canonical.basis_sha256({:t, 1, %{:a => 1, "a" => 2}}) end
    end

    test "a $-prefixed key and a non-string key raise" do
      assert_raise ArgumentError, fn -> Canonical.basis_sha256({:t, 1, %{"$basis" => 1}}) end
      assert_raise ArgumentError, fn -> Canonical.basis_sha256({:t, 1, %{v: %{1 => 2}}}) end
    end

    test "a malformed basis raises" do
      for basis <- [{:t, 0, %{}}, {"t", 1, %{}}, {nil, 1, %{}}, {:t, 1, []}, %{}, {:t, 1}] do
        assert_raise ArgumentError, fn -> Canonical.basis_sha256(basis) end
      end
    end
  end
end
