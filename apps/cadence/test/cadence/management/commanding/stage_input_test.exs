defmodule Cadence.Management.Commanding.StageInputTest do
  use ExUnit.Case, async: true
  alias Cadence.Management.Commanding.StageInput
  @digest String.duplicate("a", 64)

  test "ordered item cursors require an exact pair and canonical bounded integer strings" do
    assert {:ok, %{after_order: nil}} = StageInput.workbench(%{})

    assert {:ok, %{after_order: 0, after: "item:one"}} =
             StageInput.workbench(%{"after" => "item:one", "after_order" => "0"})

    for input <- [
          %{"after" => "item:one"},
          %{"after_order" => "0"},
          %{"after" => "item:one", "after_order" => "01"},
          %{"after" => "item:one", "after_order" => "+1"},
          %{"after" => "item:one", "after_order" => "2147483648"},
          %{"after" => "item:one", "after_order" => 1},
          %{"item" => "../private"},
          %{"state" => "unknown"},
          %{"owner_id" => "other"}
        ] do
      assert {:error, _} = StageInput.workbench(input)
    end
  end

  test "directory cursors and filters preserve durable IDs and reject foreign or unknown keys" do
    assert {:ok, %{after: "", state: "", query: ""}} = StageInput.directory(%{})
    assert {:ok, %{after: "stage:one"}} = StageInput.directory(%{"after" => "stage:one"})

    for input <- [
          %{"after" => "../stage"},
          %{"state" => "unknown"},
          %{"actor_id" => "other"},
          %{after: "stage"}
        ] do
      assert {:error, _} = StageInput.directory(input)
    end
  end

  test "creation admits bounded Unicode text and cannot accept browser identity or metadata" do
    input = %{
      "expected_write" => @digest,
      "name" => "Flight preparation",
      "description" => String.duplicate("é", 2_000),
      "visibility" => "private"
    }

    assert {:ok, %{description: description, visibility: "private"}} = StageInput.create(input)
    assert byte_size(description) == 4_000

    for {key, value} <- [
          {"description", description <> "x"},
          {"name", " \n"},
          {"name", <<255>>},
          {"name", "test\0"},
          {"visibility", "public"},
          {"expected_write", "bad"},
          {"owner", %{"user_id" => "other"}},
          {"metadata", %{}}
        ] do
      assert {:error, _} = StageInput.create(Map.put(input, key, value))
    end
  end

  test "edits cannot set submitted state, owner, derived arguments or a request pointer" do
    edit = %{
      "expected_write" => @digest,
      "expected_stage" => @digest,
      "name" => "Flight",
      "description" => nil,
      "visibility" => "shared",
      "state" => "ready_to_submit"
    }

    assert {:ok, _} = StageInput.edit_stage(edit)
    assert {:error, _} = StageInput.edit_stage(Map.put(edit, "state", "submitted"))
    assert {:error, _} = StageInput.edit_stage(Map.put(edit, "owner", %{}))

    item = %{
      "expected_write" => @digest,
      "expected_stage" => @digest,
      "expected_preview" => @digest,
      "notes" => nil,
      "order" => 2_147_483_647
    }

    assert {:ok, _} = StageInput.add_item(item)

    for {key, value} <- [
          {"order", 2_147_483_648},
          {"order", -1},
          {"order", 1.0},
          {"resolved_argument_values", %{}},
          {"submitted_command_request_id", "request"}
        ] do
      assert {:error, _} = StageInput.add_item(Map.put(item, key, value))
    end

    assert {:error, _} = StageInput.edit_item(item)
    assert {:ok, _} = StageInput.edit_item(Map.put(item, "expected_item", @digest))
  end

  test "submission selection is finite, explicit, distinct and bound to item evidence" do
    items = for i <- 1..25, do: %{"id" => "item_#{i}", "expected_item" => @digest}
    input = %{"expected_stage" => @digest, "items" => items}
    assert {:ok, %{items: ^items}} = StageInput.preview_submission(input)

    for selected <- [
          [],
          items ++ [%{"id" => "extra", "expected_item" => @digest}],
          [hd(items), hd(items)],
          [%{"id" => "item_1"}],
          [%{"id" => "item", "expected_item" => @digest, "arguments" => %{}}]
        ] do
      assert {:error, _} = StageInput.preview_submission(%{input | "items" => selected})
    end

    assert {:ok, _} =
             StageInput.submit(%{"expected_write" => @digest, "expected_preview" => @digest})

    assert {:error, _} = StageInput.submit(%{"expected_preview" => @digest})

    assert {:ok, _} =
             StageInput.cancel_item(%{
               "expected_write" => @digest,
               "expected_stage" => @digest,
               "expected_item" => @digest
             })
  end
end
