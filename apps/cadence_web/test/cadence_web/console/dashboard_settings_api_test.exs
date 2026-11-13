defmodule CadenceWeb.Console.DashboardSettingsAPITest do
  @moduledoc "Dashboard slice 5 (D14-D19) for the console (docs/apogee/api/dashboards.md)."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias Cadence.Dashboards.StatelessAuthoring
  alias CadenceWeb.TestFixtures

  setup do: authoring_draft_setup()

  defp path(c, suffix),
    do:
      "/api/console/v1/missions/#{c.mission.mission_id}/dashboards/#{c.document.dashboard_id}" <>
        suffix

  defp get_path(c, suffix), do: c.user |> TestFixtures.member_conn() |> get(path(c, suffix))

  test "D18 diagnostics: one row per widget with a closed status, worst first", c do
    # Diagnostics read the current version: save once so the fixture has one.
    rename = %{"event" => "rename", "input" => %{"name" => "Current", "description" => ""}}

    assert {:ok, %{version: 2}} =
             StatelessAuthoring.save(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               [rename],
               nil
             )

    data = c |> get_path("/diagnostics") |> json_response(200) |> Map.fetch!("data")

    assert %{"version" => 2, "loaded_at" => _, "widgets" => [widget]} = data
    assert widget["placement_id"] == "placement_battery_voltage"
    assert widget["status"] in ~w(ok degraded failed not_run)

    for source <- widget["sources"] do
      assert source["status"] in ~w(ok degraded failed not_run)
      assert source["cache"] in ["cached", "fresh", nil]
      assert is_nil(source["duration_ms"])
    end

    assert json_response(get_path(c, "/../nope/diagnostics"), 404)
  end

  test "D19 export: the portable bundle as an attachment", c do
    conn = get_path(c, "/export")
    assert response(conn, 200)
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~r/attachment; filename=".+\.cadence-dashboard\.json"/
    assert %{} = Jason.decode!(conn.resp_body)
  end
end
