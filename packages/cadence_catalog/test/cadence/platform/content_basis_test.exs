defmodule Cadence.Platform.ContentBasisTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Reference
  alias Cadence.Platform.ContentBasis
  alias Cadence.TestSupport.ContentBasisCanary

  @golden_bytes ~s(example:v2:{"a":{"$cadence_atom":"active"},"b":[null,true,-7,"x"],"map":{"a":1,"z":2}})
  @golden_digest "example:v2:c8fdbf534c358e4b43814605bf71bbf53a6592656eae0db83f25c5d745016fa7"

  test "pins canonical bytes and the digest across map insertion order" do
    fields = [map: %{z: 2, a: 1}, b: [nil, true, -7, "x"], a: :active]

    assert ContentBasis.encoded("example", 2, fields) == @golden_bytes
    assert ContentBasis.digest("example", 2, fields) == @golden_digest

    assert ContentBasis.digest("example", 2,
             a: :active,
             b: [nil, true, -7, "x"],
             map: %{"a" => 1, "z" => 2}
           ) ==
             @golden_digest
  end

  test "rejects implicit Erlang terms and ambiguous data" do
    for value <- [
          %Reference{expected_kind: :parameter, source_ref: "x"},
          self(),
          make_ref(),
          fn -> :ok end,
          {:tuple},
          1.5,
          <<255>>
        ] do
      assert_raise ArgumentError, fn -> ContentBasis.digest("example", 1, value: value) end
    end

    assert_raise ArgumentError, fn ->
      ContentBasis.digest("example", 1, first: 1, first: 2)
    end

    assert_raise ArgumentError, fn ->
      ContentBasis.digest("example", 1, value: %{"a" => 2, a: 1})
    end
  end

  test "raw bytes require an explicit tag" do
    assert ContentBasis.encoded("bytes", 1, value: ContentBasis.raw_bytes(<<0, 255>>)) ==
             ~s(bytes:v1:{"value":{"$cadence_bytes":"AP8"}})
  end

  test "user keys cannot collide with scalar tags" do
    assert ContentBasis.encoded("tag", 1, value: %{"$cadence_atom" => "active"}) ==
             ~s(tag:v1:{"value":{"$$cadence_atom":"active"}})

    refute ContentBasis.digest("tag", 1, value: %{"$cadence_atom" => "active"}) ==
             ContentBasis.digest("tag", 1, value: :active)

    refute ContentBasis.digest("tag", 1, value: %{"$cadence_bytes" => "AP8"}) ==
             ContentBasis.digest("tag", 1, value: ContentBasis.raw_bytes(<<0, 255>>))
  end

  test "the canary fails on an unreviewed struct field" do
    fields = Reference.__struct__() |> Map.from_struct() |> Map.keys()

    assert_raise ExUnit.AssertionError, ~r/changed fields for reference:v1/, fn ->
      ContentBasisCanary.assert_struct_fields!(Reference, "reference", 1,
        included: List.delete(fields, :role),
        excluded: []
      )
    end
  end
end
