defmodule CadenceWeb.Console.DashboardPlaylistAPITest do
  @moduledoc "Dashboards slice 6 D23/D24: playlists."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias CadenceWeb.TestFixtures

  setup do: authoring_draft_setup()

  defp base(c), do: "/api/v1/missions/#{c.mission.mission_id}/dashboard-playlists"

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

  test "create, list, read, edit with the row's updated_at, refuse a stale edit, delete", c do
    body = %{
      "name" => "Ops wall",
      "dashboard_ids" => [c.document.dashboard_id],
      "dwell_seconds" => 30,
      "wallboard_mode" => true
    }

    assert %{"id" => id} = c |> call(:post, "", body) |> json_response(201) |> Map.fetch!("data")

    list = c |> call(:get, "?q=ops") |> json_response(200) |> Map.fetch!("data")
    assert list["can_edit"] == true

    assert [%{"id" => ^id, "dashboard_count" => 1, "updated_by" => %{"id" => _}}] =
             list["playlists"]

    %{"playlist" => playlist} =
      c |> call(:get, "/" <> id) |> json_response(200) |> Map.fetch!("data")

    assert [%{"id" => _, "name" => _, "archived" => false}] = playlist["dashboards"]
    stale = playlist["updated_at"]

    edit = %{"name" => "Ops wall 2", "dwell_seconds" => 60, "expected_updated_at" => stale}

    assert %{"id" => ^id} =
             c |> call(:patch, "/" <> id, edit) |> json_response(200) |> Map.fetch!("data")

    assert %{"code" => "version_conflict", "details" => %{"current" => %{"name" => "Ops wall 2"}}} =
             c |> call(:patch, "/" <> id, edit) |> json_response(409) |> Map.fetch!("error")

    assert %{"code" => "invalid_params"} =
             c
             |> call(:post, "", %{body | "dwell_seconds" => 1})
             |> json_response(422)
             |> Map.fetch!("error")

    assert c |> call(:delete, "/" <> id) |> response(204)

    assert %{"code" => "playlist_not_found"} =
             c |> call(:get, "/" <> id) |> json_response(404) |> Map.fetch!("error")

    assert c |> call(:delete, "/" <> id) |> json_response(404)
  end
end
