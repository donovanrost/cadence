defmodule CadenceWeb.Console.DashboardAuthoringAPITest do
  @moduledoc "D7-D13: stateless dashboard editing for the console (docs/apogee/api/dashboards.md)."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias Cadence.Dashboards.StatelessAuthoring
  alias CadenceWeb.TestFixtures

  setup do: authoring_draft_setup()

  @placement "placement_battery_voltage"

  defp rename(name), do: %{"event" => "rename", "input" => %{"name" => name, "description" => ""}}
  defp remove(id), do: %{"event" => "remove_widget", "input" => %{"placement_id" => id}}

  defp path(c, suffix),
    do:
      "/api/console/v1/missions/#{c.mission.mission_id}/dashboards/#{c.document.dashboard_id}" <>
        suffix

  defp post_json(c, suffix, body),
    do: c.user |> TestFixtures.member_conn() |> post(path(c, suffix), body)

  defp get_json(c, suffix), do: c.user |> TestFixtures.member_conn() |> get(path(c, suffix))

  test "D7 preview: the staged snapshot, its changes and outline; nothing is written", c do
    data =
      c
      |> post_json("/preview", %{"base_version" => 1, "commands" => [rename("Staged")]})
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["snapshot"]["name"] == "Staged"
    assert data["current_version"] == 1
    assert [_ | _] = data["changes"]
    assert %{"version" => 3, "name" => "Staged", "placements" => [_]} = data["outline"]

    # Entering edit mode is a preview with no commands.
    empty =
      c |> post_json("/preview", %{"base_version" => 1, "commands" => []}) |> json_response(200)

    assert empty["data"]["changes"] == []

    assert %{"current_version" => 1, "versions" => [_]} =
             c |> get_json("/versions") |> json_response(200) |> Map.fetch!("data")
  end

  test "D7 errors: the first bad command by index, the cap, an unadmitted range", c do
    response =
      post_json(c, "/preview", %{
        "base_version" => 1,
        "commands" => [rename("Ok"), remove("nope")]
      })

    assert %{
             "code" => "invalid_command",
             "details" => %{"index" => 1, "code" => "missing_placement"}
           } =
             json_response(response, 422)["error"]

    too_many = List.duplicate(rename("x"), 257)

    assert %{"code" => "too_many_commands"} =
             json_response(
               post_json(c, "/preview", %{"base_version" => 1, "commands" => too_many}),
               422
             )["error"]

    bad_range = %{"base_version" => 1, "commands" => [], "runtime" => %{"from" => "yesterday"}}

    assert %{"details" => %{"field" => "range"}} =
             json_response(post_json(c, "/preview", bad_range), 422)["error"]
  end

  test "D9 save, D12 versions, a stale save's 409 says who saved, D10 rebase skips what no longer applies",
       c do
    assert %{"version" => 2, "changed" => true} =
             json_response(
               post_json(c, "/save", %{
                 "base_version" => 1,
                 "commands" => [remove(@placement)],
                 "message" => "Drop it"
               }),
               201
             )["data"]

    assert %{"current_version" => 2, "versions" => [newest, _first]} =
             c |> get_json("/versions") |> json_response(200) |> Map.fetch!("data")

    assert %{
             "version" => 2,
             "kind" => "save",
             "message" => "Drop it",
             "current" => true,
             "saved_by" => %{"kind" => "user"}
           } =
             newest

    late = post_json(c, "/save", %{"base_version" => 1, "commands" => [rename("Late")]})

    assert %{
             "code" => "version_conflict",
             "details" => %{"current_version" => 2, "saved_by" => %{"id" => _}, "saved_at" => _}
           } =
             json_response(late, 409)["error"]

    mine = [rename("Mine"), remove(@placement)]

    assert %{
             "base_version" => 2,
             "applied" => [applied],
             "skipped" => [skipped],
             "snapshot" => snapshot
           } =
             json_response(post_json(c, "/rebase", %{"commands" => mine}), 200)["data"]

    assert applied == rename("Mine")
    assert skipped == %{"index" => 1, "event" => "remove_widget", "reason" => "missing_placement"}
    assert snapshot["name"] == "Mine"
  end

  test "D11 copy keeps unsaved edits; D12 compare; D13 restore makes a new current version", c do
    assert %{"id" => copy_id, "version" => 1} =
             json_response(
               post_json(c, "/copy", %{
                 "name" => "My copy",
                 "base_version" => 1,
                 "commands" => [remove(@placement)]
               }),
               201
             )["data"]

    refute copy_id == c.document.dashboard_id

    assert {:ok, %{version: 2}} =
             StatelessAuthoring.save(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               [rename("Two")],
               nil
             )

    assert %{"from" => 1, "to" => 2, "changes" => [_ | _], "from_json" => _, "to_json" => _} =
             c
             |> get_json("/versions/compare?from=1&to=2")
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"version" => 3} =
             json_response(post_json(c, "/versions/1/restore", %{"expected_version" => 2}), 201)[
               "data"
             ]

    assert %{
             "current_version" => 3,
             "versions" => [%{"kind" => "revert", "based_on_version" => 1} | _]
           } =
             c |> get_json("/versions") |> json_response(200) |> Map.fetch!("data")

    assert %{"code" => "version_conflict"} =
             json_response(post_json(c, "/versions/1/restore", %{"expected_version" => 2}), 409)[
               "error"
             ]
  end

  test "D8 observable choices need the widget's form fields", c do
    assert %{"details" => %{"fields" => _}} =
             json_response(
               post_json(c, "/observables", %{
                 "query" => "bat",
                 "base_version" => 1,
                 "fields" => %{}
               }),
               422
             )["error"]
  end
end
