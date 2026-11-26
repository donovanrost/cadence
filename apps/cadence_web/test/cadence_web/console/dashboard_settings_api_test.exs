defmodule CadenceWeb.Console.DashboardSettingsAPITest do
  @moduledoc "Dashboard slice 5 (D14-D19) for the console (docs/apogee/api/dashboards.md)."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias Cadence.Dashboards.StatelessAuthoring
  alias CadenceWeb.Console.DashboardActivity
  alias CadenceWeb.TestFixtures

  setup do: authoring_draft_setup()

  defp path(c, suffix),
    do:
      "/api/v1/missions/#{c.mission.mission_id}/dashboards/#{c.document.dashboard_id}" <>
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

  test "D17 activity: saves newest first in closed kinds, paged by an opaque cursor", c do
    rename = fn name ->
      %{"event" => "rename", "input" => %{"name" => name, "description" => ""}}
    end

    for {name, base} <- [{"Two", 1}, {"Three", 2}] do
      assert {:ok, _} =
               StatelessAuthoring.save(
                 c.scope,
                 c.mission.mission_id,
                 c.document.dashboard_id,
                 base,
                 [rename.(name)],
                 "Named #{name}"
               )
    end

    assert {:ok, _} =
             StatelessAuthoring.restore(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               2,
               3
             )

    data = c |> get_path("/activity") |> json_response(200) |> Map.fetch!("data")

    assert [%{"kind" => "restored", "version" => 4, "detail" => "Restored from v2"} | rest] =
             data["events"]

    assert [
             %{"kind" => "saved", "version" => 3, "detail" => "Named Three"},
             %{"kind" => "saved", "version" => 2} | _
           ] = rest

    assert Enum.all?(data["events"], &(&1["kind"] in ~w(saved restored archived unarchived)))
    assert data["next"] == nil

    assert %{"details" => %{"before" => _}} =
             json_response(get_path(c, "/activity?before=nope"), 422)["error"]
  end

  test "D17 paging is exact across versions and lifecycle events" do
    at = fn s -> "2026-11-13T00:00:#{String.pad_leading(Integer.to_string(s), 2, "0")}Z" end

    versions =
      for v <- 30..6//-1,
          do: %{
            version: v,
            kind: "save",
            based_on_version: nil,
            summary: "",
            actor_id: nil,
            saved_at: at.(v)
          }

    events = [
      %{id: "e1", event_type: "archived", document_version: 6, actor_id: nil, occurred_at: at.(5)}
    ]

    history = %{
      versions: versions,
      next_version: 6,
      events: events,
      next_event: nil,
      query: %{before_version: nil, before_event: nil}
    }

    page = DashboardActivity.page(history, %{})

    # Versions have more pages, so the page stops at the oldest fetched version (v6) and the
    # older event waits for the next page.
    assert length(page.events) == 25
    assert List.last(page.events).version == 6
    refute Enum.any?(page.events, &(&1.kind == "archived"))
    assert is_binary(page.next)
  end

  test "D19 export: the portable bundle as an attachment", c do
    conn = get_path(c, "/export")
    assert response(conn, 200)
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~r/attachment; filename=".+\.cadence-dashboard\.json"/
    assert %{} = Jason.decode!(conn.resp_body)
  end
end
