defmodule Cadence.Comms.StationCodeTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.StationCode

  test "suggests the name's first three letters" do
    assert StationCode.suggest("Svalbard (Demo)", []) == "SVA"
    assert StationCode.suggest("st. john's", []) == "STJ"
  end

  test "de-duplicates against confirmed codes" do
    assert StationCode.suggest("Svalbard", ["SVA"]) == "SVA2"
    assert StationCode.suggest("Svalbard", ["SVA", "SVA2"]) == "SVA3"
  end

  test "suggests nothing for names without letters" do
    assert StationCode.suggest("42 / 7", []) == nil
    assert StationCode.suggest(nil, []) == nil
  end
end
