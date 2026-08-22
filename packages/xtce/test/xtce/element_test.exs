defmodule XTCE.ElementTest do
  use ExUnit.Case, async: true

  alias XTCE.Element

  test "direct-child, descendant, text, and map helpers preserve tree meaning" do
    grandchild = %Element{name: "Unit", text: " degC ", line: 3}
    child = %Element{name: "UnitSet", children: [grandchild], line: 2}
    root = %Element{name: "SpaceSystem", attributes: %{"name" => "Vehicle"}, children: [child]}

    assert Element.attr(root, "name") == "Vehicle"
    assert Element.attr(root, "missing", "default") == "default"
    assert Element.child(root, "UnitSet") == child
    assert Element.children(root, "UnitSet") == [child]
    assert Element.descendants(root, "Unit") == [grandchild]
    assert Element.text(grandchild) == "degC"

    assert get_in(Element.to_map(root), [
             "children",
             Access.at(0),
             "children",
             Access.at(0),
             "line"
           ]) == 3
  end
end
