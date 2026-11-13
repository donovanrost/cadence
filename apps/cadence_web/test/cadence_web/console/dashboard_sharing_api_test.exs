defmodule CadenceWeb.Console.DashboardSharingAPITest do
  @moduledoc "Dashboard slice 5 D14-D16: settings, General save, shares and snapshots."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  alias CadenceWeb.TestFixtures

  setup do: authoring_draft_setup()

  defp path(c, suffix),
    do:
      "/api/console/v1/missions/#{c.mission.mission_id}/dashboards/#{c.document.dashboard_id}" <>
        suffix

  defp call(c, method, suffix, body \\ %{}) do
    conn = TestFixtures.member_conn(c.user)

    case method do
      :get -> get(conn, path(c, suffix))
      :post -> post(conn, path(c, suffix), body)
      :patch -> patch(conn, path(c, suffix), body)
      :delete -> delete(conn, path(c, suffix))
    end
  end

  test "D14 reads the settings; D15 saves them as a version; a stale save is 409", c do
    data = c |> call(:get, "/settings") |> json_response(200) |> Map.fetch!("data")

    assert %{"dashboard" => %{"current_version" => version}, "limits" => %{"name" => 120}} = data
    assert %{"time" => _, "scope" => _} = data["defaults"]
    assert %{"rows" => [], "next" => nil} = data["shares"]

    body = %{
      "name" => "Bus overview",
      "description" => "Power and thermal",
      "tags" => ["power"],
      "defaults" => %{"time" => %{"mode" => "relative", "range" => "now-6h"}, "scope" => nil},
      "expected_version" => version
    }

    assert %{"version" => saved} =
             c |> call(:patch, "/settings", body) |> json_response(200) |> Map.fetch!("data")

    assert saved == version + 1

    after_save = c |> call(:get, "/settings") |> json_response(200) |> Map.fetch!("data")
    assert after_save["dashboard"]["name"] == "Bus overview"
    assert after_save["defaults"]["time"] == %{"mode" => "relative", "range" => "now-6h"}

    assert %{"code" => "version_conflict", "details" => %{"current_version" => ^saved}} =
             c |> call(:patch, "/settings", body) |> json_response(409) |> Map.fetch!("error")

    assert %{"code" => "invalid_params", "details" => %{"name" => _}} =
             c
             |> call(:patch, "/settings", %{body | "name" => " ", "expected_version" => saved})
             |> json_response(422)
             |> Map.fetch!("error")
  end

  test "D16 shares: create with an expiry date, revoke once, then 409", c do
    expires = DateTime.utc_now() |> DateTime.add(3 * 86_400) |> DateTime.to_iso8601()

    share =
      c
      |> call(:post, "/shares", %{"data_visibility" => "definition_only", "expires_at" => expires})
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{"state" => "active", "data_visibility" => "definition_only", "url" => url} = share
    assert url =~ "/telemetry/dashboards/shares/" <> share["id"]
    assert %{"name" => _} = share["created_by"]

    revoked =
      c |> call(:delete, "/shares/" <> share["id"]) |> json_response(200) |> Map.fetch!("data")

    assert revoked["state"] == "revoked"

    assert %{"code" => "share_not_active"} =
             c
             |> call(:delete, "/shares/" <> share["id"])
             |> json_response(409)
             |> Map.fetch!("error")

    past = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()

    assert %{"details" => %{"expires_at" => _}} =
             c
             |> call(:post, "/shares", %{"data_visibility" => "with_data", "expires_at" => past})
             |> json_response(422)
             |> Map.fetch!("error")
  end

  test "D16 snapshots: a frozen window is required; delete leaves 204", c do
    runtime = %{"from" => "2026-11-12T21:00:00Z", "to" => "2026-11-12T23:00:00Z"}

    snapshot =
      c
      |> call(:post, "/snapshots", %{"data_visibility" => "definition_only", "runtime" => runtime})
      |> json_response(201)
      |> Map.fetch!("data")

    assert snapshot["window"] == %{"from" => runtime["from"], "to" => runtime["to"]}
    assert snapshot["url"] =~ "/telemetry/dashboards/snapshots/" <> snapshot["id"]

    assert %{"code" => "invalid_params"} =
             c
             |> call(:post, "/snapshots", %{
               "data_visibility" => "definition_only",
               "runtime" => %{}
             })
             |> json_response(422)
             |> Map.fetch!("error")

    assert c |> call(:delete, "/snapshots/" <> snapshot["id"]) |> response(204)
    assert c |> call(:delete, "/snapshots/" <> snapshot["id"]) |> json_response(404)
  end
end
