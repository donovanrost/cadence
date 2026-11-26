defmodule CadenceWeb.Console.DashboardLibraryAPITest do
  @moduledoc "Dashboards slice 8 D21/D22: the widget library."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias Cadence.Dashboards.WidgetDef
  alias CadenceWeb.TestFixtures

  setup do: authoring_draft_setup()

  defp base(c), do: "/api/v1/missions/#{c.mission.mission_id}/dashboard-library"

  defp call(c, method, suffix, body \\ %{}) do
    conn = TestFixtures.member_conn(c.user)
    path = base(c) <> suffix

    case method do
      :get -> get(conn, path)
      :post -> post(conn, path, body)
      :patch -> patch(conn, path, body)
      :delete -> delete(conn, path)
    end
  end

  defp definition(c),
    do:
      c.document.placements
      |> hd()
      |> Map.fetch!(:widget_def)
      |> WidgetDef.to_map()
      |> Jason.encode!()

  test "create, list, read, add a version, rename, retire; stale writes are 409", c do
    create = %{
      "name" => "Battery tile",
      "description" => "",
      "definition_json" => definition(c),
      "summary" => "First"
    }

    assert %{"id" => id, "version" => 1} =
             c |> call(:post, "", create) |> json_response(201) |> Map.fetch!("data")

    list = c |> call(:get, "?q=battery") |> json_response(200) |> Map.fetch!("data")

    assert %{"total" => 1, "page" => 1, "pages" => 1, "page_size" => 25, "can_edit" => true} =
             list

    assert [%{"id" => ^id, "used_by_count" => 0, "latest_version" => 1, "kind" => _}] =
             list["items"]

    item = c |> call(:get, "/" <> id) |> json_response(200) |> Map.fetch!("data")
    assert %{"version" => %{"version" => 1, "definition_json" => json}, "versions" => [_]} = item
    assert is_binary(json)
    assert item["used_by"] == %{"dashboards" => []}

    version = %{
      "definition_json" => definition(c),
      "summary" => "Second",
      "expected_version" => 1
    }

    assert %{"version" => 2} =
             c
             |> call(:post, "/#{id}/versions", version)
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"code" => "library_item_changed", "details" => %{"latest_version" => 2}} =
             c
             |> call(:post, "/#{id}/versions", version)
             |> json_response(409)
             |> Map.fetch!("error")

    # Two tabs read the item; the first renames, the second's stale rename is refused (qa).
    read_at =
      c |> call(:get, "/" <> id) |> json_response(200) |> get_in(["data", "item", "updated_at"])

    first = %{"name" => "Battery", "expected_version" => 2, "expected_updated_at" => read_at}
    renamed = c |> call(:patch, "/" <> id, first) |> json_response(200)
    assert renamed["data"]["name"] == "Battery"

    assert %{"code" => "library_item_changed"} =
             c
             |> call(:patch, "/" <> id, %{first | "name" => "Tab two"})
             |> json_response(409)
             |> Map.fetch!("error")

    assert %{"code" => "library_item_changed"} =
             c
             |> call(:delete, "/#{id}?expected_version=1")
             |> json_response(409)
             |> Map.fetch!("error")

    assert c |> call(:delete, "/#{id}?expected_version=2") |> response(204)

    assert %{"code" => "library_item_not_found"} =
             c |> call(:get, "/" <> id) |> json_response(404) |> Map.fetch!("error")

    assert [] = c |> call(:get, "") |> json_response(200) |> get_in(["data", "items"])
  end

  test "a bad definition or name is 422", c do
    bad = %{"name" => "X", "description" => "", "definition_json" => "{}", "summary" => ""}
    assert c |> call(:post, "", bad) |> json_response(422)
    assert c |> call(:post, "", %{bad | "name" => " "}) |> json_response(422)
  end
end
