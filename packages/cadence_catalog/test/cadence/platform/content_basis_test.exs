defmodule Cadence.Platform.ContentBasisTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Reference
  alias Cadence.Platform.ContentBasis
  alias Cadence.TestSupport.ContentBasisCanary

  @golden_bytes ~s(example:v2:{"a":{"$cadence_atom":"active"},"b":[null,true,-7,"x"],"float":{"$cadence_float":"1.5"},"map":{"a":1,"z":2},"negative_zero":{"$cadence_float":"0.0"}})
  @golden_digest "example:v2:0fd18ecbe4f388d6496bf771e00c7a66bcb01dcd5df5834afe845a9aedbcf99b"

  test "pins canonical bytes and the digest across map insertion order" do
    fields = [
      map: %{z: 2, a: 1},
      b: [nil, true, -7, "x"],
      a: :active,
      float: 1.5,
      negative_zero: -0.0
    ]

    assert ContentBasis.encoded("example", 2, fields) == @golden_bytes
    assert ContentBasis.digest("example", 2, fields) == @golden_digest

    assert ContentBasis.digest("example", 2,
             a: :active,
             b: [nil, true, -7, "x"],
             float: 1.5,
             negative_zero: 0.0,
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

  test "float and integer values have different bases; both zero signs match" do
    refute ContentBasis.digest("number", 1, value: 1) ==
             ContentBasis.digest("number", 1, value: 1.0)

    assert ContentBasis.encoded("number", 1, value: -0.0) ==
             ContentBasis.encoded("number", 1, value: 0.0)
  end

  test "user keys cannot collide with scalar tags" do
    assert ContentBasis.encoded("tag", 1, value: %{"$cadence_atom" => "active"}) ==
             ~s(tag:v1:{"value":{"$$cadence_atom":"active"}})

    refute ContentBasis.digest("tag", 1, value: %{"$cadence_atom" => "active"}) ==
             ContentBasis.digest("tag", 1, value: :active)

    refute ContentBasis.digest("tag", 1, value: %{"$cadence_bytes" => "AP8"}) ==
             ContentBasis.digest("tag", 1, value: ContentBasis.raw_bytes(<<0, 255>>))

    assert ContentBasis.encoded("tag", 1, value: %{"$cadence_float" => "1.5"}) ==
             ~s(tag:v1:{"value":{"$$cadence_float":"1.5"}})

    refute ContentBasis.digest("tag", 1, value: %{"$cadence_float" => "1.5"}) ==
             ContentBasis.digest("tag", 1, value: 1.5)
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
