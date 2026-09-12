defmodule Cadence.Dashboards.AuthoringInputTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{AuthoringInput, AuthoringWidget}

  test "every command requires a bounded observed version and an exact payload" do
    for version <- [nil, "1", 0, -1, 1.0, 9_007_199_254_740_991] do
      assert {:error, :invalid_input} =
               AuthoringInput.admit("publish", %{"expected_version" => version})
    end

    assert {:ok, 1, %{}} = AuthoringInput.admit("publish", %{"expected_version" => 1})

    for input <- [%{}, %{"expected_version" => 1, "organization_id" => "foreign"}] do
      assert {:error, :invalid_input} = AuthoringInput.admit("publish", input)
    end

    assert {:error, :invalid_input} =
             AuthoringInput.admit("save_editor", %{"expected_version" => 1})
  end

  test "widget form fields and observables have finite exact shapes" do
    fields = AuthoringWidget.defaults()
    input = %{"expected_version" => 1, "fields" => fields, "observables" => ["battery"]}
    assert {:ok, 1, _} = AuthoringInput.admit("add_widget", input)

    for invalid <- [
          Map.put(fields, "point_q", "battery"),
          Map.put(fields, "title", <<255>>),
          Map.put(fields, "title", String.duplicate("x", 513)),
          Map.put(fields, "show_unit", true),
          Map.put(fields, "precision", "2.5"),
          Map.put(fields, "precision", "02"),
          Map.put(fields, "legend_mode", "never"),
          Map.put(fields, "line_width", "thick"),
          Map.delete(fields, "scope_id")
        ] do
      assert {:error, :invalid_input} =
               AuthoringInput.admit("add_widget", %{input | "fields" => invalid})
    end

    for observables <- [["battery", "battery"], [""], [nil], Enum.map(1..25, &to_string/1)] do
      assert {:error, :invalid_input} =
               AuthoringInput.admit("add_widget", %{input | "observables" => observables})
    end
  end

  test "runtime defaults require a bounded JSON field and the observed version" do
    input = %{"expected_version" => 2, "defaults_json" => "{}"}
    assert {:ok, 2, %{"defaults_json" => "{}"}} = AuthoringInput.admit("runtime_defaults", input)

    for invalid <- [
          Map.delete(input, "expected_version"),
          Map.put(input, "defaults_json", %{}),
          Map.put(input, "defaults_json", String.duplicate("x", 32_769)),
          Map.put(input, "mission_id", "foreign")
        ] do
      assert {:error, :invalid_input} = AuthoringInput.admit("runtime_defaults", invalid)
    end
  end

  test "layout admission rejects duplicate identities and malformed geometry before mutation" do
    layout = %{"placement_id" => "battery", "x" => 0, "y" => 0, "w" => 3, "h" => 2}

    assert {:ok, 1, _} =
             AuthoringInput.admit("layout", %{"expected_version" => 1, "layouts" => [layout]})

    for layouts <- [
          [],
          [layout, layout],
          [Map.put(layout, "x", -1)],
          [Map.put(layout, "w", 0)],
          [Map.put(layout, "h", 1.5)],
          [Map.put(layout, "widget_id", "other")],
          [nil]
        ] do
      assert {:error, :invalid_input} =
               AuthoringInput.admit("layout", %{"expected_version" => 1, "layouts" => layouts})
    end
  end

  test "section defaults are real booleans and text cannot be empty or malformed" do
    section = %{
      "expected_version" => 1,
      "title" => "Power",
      "description" => "",
      "collapsed_by_default" => true
    }

    assert {:ok, 1, _} = AuthoringInput.admit("add_section", section)

    for invalid <- [
          Map.put(section, "collapsed_by_default", "true"),
          Map.put(section, "title", "  "),
          Map.put(section, "description", <<255>>)
        ] do
      assert {:error, :invalid_input} = AuthoringInput.admit("add_section", invalid)
    end
  end
end
