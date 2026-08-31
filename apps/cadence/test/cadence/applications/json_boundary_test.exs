defmodule Cadence.Applications.JSONBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.JSONBoundary

  test "preserves valid values while safe normalizes keys for transport" do
    value = %{application: "alpha", values: [nil, true, 7, 1.5]}

    assert :ok = JSONBoundary.validate(value)

    assert {:ok, %{"application" => "alpha", "values" => [nil, true, 7, 1.5]}} =
             JSONBoundary.safe(value)
  end

  test "rejects unsupported scalar types and invalid keys" do
    assert {:error, :unsupported} = JSONBoundary.validate(%{"pid" => self()})
    assert {:error, :unsupported} = JSONBoundary.validate(%{"atom" => :not_json})
    assert {:error, :key} = JSONBoundary.validate(%{{:tuple_key, :second} => "value"})
  end

  test "rejects exact string, map, list, and document bounds" do
    assert {:error, :string} = JSONBoundary.validate(String.duplicate("s", 241))
    assert {:error, :map_items} = JSONBoundary.validate(Map.new(1..65, &{"key-#{&1}", &1}))
    assert {:error, :list_items} = JSONBoundary.validate(Enum.to_list(1..101))

    oversized_document =
      Map.new(1..64, fn index ->
        {"key-#{index}", Enum.map(1..100, fn _item -> String.duplicate("x", 10) end)}
      end)

    assert {:error, :document_bytes} = JSONBoundary.validate(oversized_document)
  end

  test "rejects values deeper than the recursive boundary" do
    assert :ok = JSONBoundary.validate(nested_map(8))
    assert {:error, :depth} = JSONBoundary.validate(nested_map(9))
  end

  defp nested_map(0), do: %{}
  defp nested_map(depth), do: %{"next" => nested_map(depth - 1)}
end
