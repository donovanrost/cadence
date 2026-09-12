defmodule Cadence.Dashboards.AuthoringDefaultsTest do
  use Cadence.UnitCase, async: true
  alias Cadence.Dashboards.AuthoringDefaults

  test "bounded JSON preserves complete runtime defaults and extension data" do
    defaults = %{
      "time" => %{"mode" => "live", "range" => %{"kind" => "relative", "duration_ms" => 300_000}},
      "overlays" => %{"quality" => true},
      "extension" => [nil, 1.5]
    }

    assert {:ok, json} = AuthoringDefaults.encode(defaults)
    assert {:ok, ^defaults} = AuthoringDefaults.decode(json)
    assert :ok = AuthoringDefaults.validate(defaults)
    assert {:ok, %{}} = AuthoringDefaults.decode("{}")
  end

  test "untrusted JSON has byte, depth, collection, string and number bounds" do
    deep = Enum.reduce(1..9, %{}, fn _, value -> %{"nested" => value} end)

    for json <- [
          nil,
          <<255>>,
          "",
          "{",
          "[]",
          "null",
          "true",
          String.duplicate(" ", 32_769) <> "{}",
          Jason.encode!(%{"text" => String.duplicate("x", 4097)}),
          Jason.encode!(%{"items" => Enum.to_list(1..101)}),
          Jason.encode!(Map.new(1..65, &{to_string(&1), 0})),
          Jason.encode!(deep),
          Jason.encode!(%{String.duplicate("k", 257) => 1}),
          "{\"number\":9007199254740992}",
          "{\"number\":1e400}"
        ] do
      assert {:error, :invalid_defaults} = AuthoringDefaults.decode(json)
    end
  end

  test "domain contexts validate before persistence and malformed nested objects are contained" do
    for defaults <- [
          %{"time" => []},
          %{"time" => %{"mode" => "latest"}},
          %{"time" => %{"range" => 1}},
          %{"scope" => %{"primary" => []}},
          %{"scope" => %{"primary" => %{"kind" => "unrecognized"}}},
          %{"data" => %{"realm" => "unrecognized"}},
          %{"data" => %{"source_contexts" => %{"telemetry" => false}}},
          %{"limits" => %{"semantics_mode" => "unrecognized"}}
        ] do
      assert {:error, :invalid_defaults} = AuthoringDefaults.validate(defaults)
    end
  end
end
