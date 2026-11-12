defmodule Cadence.Catalog.MissionModelReferenceTest do
  @moduledoc "Stored references decode their kind and role however modules have loaded."
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Declaration, Reference}

  @cold_decode_probe Path.expand(
                       "../../support/mission_model_reference_cold_decode_helper.exs",
                       __DIR__
                     )

  test "stored reference kinds and roles decode in a fresh VM before any importer loads" do
    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "--erl",
          "+S 2:2",
          "-pa",
          Application.app_dir(:cadence_catalog, "ebin"),
          @cold_decode_probe
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "MISSION_MODEL_REFERENCE_COLD_DECODE_OK"
  end

  test "a reference expects exactly the declaration kinds" do
    assert Enum.sort(Reference.kinds()) == Enum.sort(Declaration.kinds())
  end

  test "an unknown stored kind or role is named, not an atom-table accident" do
    assert_raise ArgumentError, ~r/unknown mission model reference role: "nope"/, fn ->
      Reference.new(%{"expected_kind" => "parameter", "source_ref" => "/x", "role" => "nope"})
    end

    assert_raise ArgumentError, ~r/unknown mission model reference kind: "nope"/, fn ->
      Reference.new(%{"expected_kind" => "nope", "source_ref" => "/x"})
    end

    assert %Reference{role: nil} =
             Reference.new(%{"expected_kind" => "parameter", "source_ref" => "/x"})
  end
end
