defmodule Cadence.Management.Commanding.ArgumentDocumentTest do
  use ExUnit.Case, async: true
  alias Cadence.Management.Commanding.ArgumentDocument

  test "exact unsigned64, signed64 and scalar types retain native values" do
    values = %{
      "unsigned" => 18_446_744_073_709_551_615,
      "signed" => -9_223_372_036_854_775_808,
      "text" => "18446744073709551615",
      "boolean" => false,
      "float" => 1.25
    }

    encoded = ArgumentDocument.encode!(values)
    assert {:ok, ^values} = ArgumentDocument.decode(encoded)
    assert encoded =~ "18446744073709551615"
  end

  test "duplicate, nested, invalid and oversized documents are rejected" do
    for input <- [
          ~s({"a":1,"a":2}),
          ~S({"a":1,"\u0061":2}),
          ~s({"a":[]}),
          ~s({"a":{}}),
          ~s({"a":null}),
          ~s({"":1}),
          ~S({"a":"\u0000"}),
          ~s([1]),
          ~s({"a":1e9999}),
          "{}" <> String.duplicate(" ", 32_769)
        ] do
      assert {:error, :invalid_command_arguments} = ArgumentDocument.decode(input)
    end
  end

  test "64 arguments are admitted and 65 are rejected" do
    values = Map.new(1..64, &{"argument_#{&1}", &1})
    assert {:ok, ^values} = ArgumentDocument.decode(Jason.encode!(values))

    assert {:error, :invalid_command_arguments} =
             ArgumentDocument.decode(Jason.encode!(Map.put(values, "extra", 65)))
  end

  test "resolved documents allow larger defaults without expanding input limits" do
    values = %{"default" => String.duplicate("x", 40_000)}
    text = ArgumentDocument.encode!(values, 131_072)
    assert {:ok, ^values} = ArgumentDocument.decode(text, 131_072)
    assert {:error, _} = ArgumentDocument.decode(text)
  end
end
