defmodule CadenceWeb.Console.DashboardSharingAPITest do
  @moduledoc "Dashboard slice 5 D14-D16: settings, General save, shares and snapshots."
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport

  import Ecto.Query

  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Dashboards.StatelessAuthoring
  alias Cadence.Repo
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

  # #469 (ca-security): who revoked a share or deleted a snapshot is named only while a member of
  # the organization. Once the creator has left, another member sees {id: null, name: null}: no
  # email and no id in the record or its message.
  test "D20 records name an outsider by neither email nor id (#469)", c do
    base = "/api/console/v1/missions/#{c.mission.mission_id}"
    rename = %{"event" => "rename", "input" => %{"name" => "Current", "description" => ""}}

    assert {:ok, _saved} =
             StatelessAuthoring.save(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               [rename],
               nil
             )

    share =
      c
      |> call(:post, "/shares", %{"data_visibility" => "definition_only", "expires_at" => nil})
      |> json_response(201)
      |> Map.fetch!("data")

    c |> call(:delete, "/shares/" <> share["id"]) |> json_response(200)

    runtime = %{"from" => "2026-11-12T21:00:00Z", "to" => "2026-11-12T23:00:00Z"}

    snapshot =
      c
      |> call(:post, "/snapshots", %{"data_visibility" => "definition_only", "runtime" => runtime})
      |> json_response(201)
      |> Map.fetch!("data")

    c |> call(:delete, "/snapshots/" <> snapshot["id"]) |> response(204)

    reader = TestFixtures.persist_user!(display_name: "Reader")
    TestFixtures.grant_membership!(reader, c.org)
    creator = c.user.user_id

    Repo.update_all(
      from(m in OrganizationMembershipRow, where: m.user_id == ^creator),
      set: [lifecycle_state: "revoked"]
    )

    open = fn suffix -> reader |> TestFixtures.member_conn() |> get(base <> suffix) end

    for {suffix, key} <- [
          {"/dashboard-shares/" <> share["id"], "revoked_by"},
          {"/dashboard-snapshots/" <> snapshot["id"], "deleted_by"}
        ] do
      error = open.(suffix) |> json_response(404) |> Map.fetch!("error")
      assert error["details"][key] == %{"id" => nil, "name" => nil}
      refute Jason.encode!(error) =~ "@"
      refute Jason.encode!(error) =~ creator
    end
  end

  test "D20: a share's link opens until revoked; a snapshot's says who deleted it", c do
    base = "/api/console/v1/missions/#{c.mission.mission_id}"
    open = fn suffix -> c.user |> TestFixtures.member_conn() |> get(base <> suffix) end

    # A share shows the current version: save once so the fixture has one.
    rename = %{"event" => "rename", "input" => %{"name" => "Current", "description" => ""}}

    assert {:ok, _saved} =
             StatelessAuthoring.save(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               [rename],
               nil
             )

    share =
      c
      |> call(:post, "/shares", %{"data_visibility" => "definition_only", "expires_at" => nil})
      |> json_response(201)
      |> Map.fetch!("data")

    view = open.("/dashboard-shares/" <> share["id"]) |> json_response(200) |> Map.fetch!("data")

    assert %{"kind" => "share", "snapshot_row" => nil, "snapshot" => nil} = view
    assert view["share"]["id"] == share["id"]
    assert view["dashboard"]["id"] == c.document.dashboard_id
    assert %{"version" => 3} = view["definition"]

    c |> call(:delete, "/shares/" <> share["id"]) |> json_response(200)

    assert %{"code" => "share_revoked", "message" => "Revoked by " <> _} =
             open.("/dashboard-shares/" <> share["id"])
             |> json_response(404)
             |> Map.fetch!("error")

    runtime = %{"from" => "2026-11-12T21:00:00Z", "to" => "2026-11-12T23:00:00Z"}

    snapshot =
      c
      |> call(:post, "/snapshots", %{"data_visibility" => "definition_only", "runtime" => runtime})
      |> json_response(201)
      |> Map.fetch!("data")

    view =
      open.("/dashboard-snapshots/" <> snapshot["id"]) |> json_response(200) |> Map.fetch!("data")

    assert %{
             "kind" => "snapshot",
             "share" => nil,
             "snapshot_row" => %{"window" => %{"from" => _}}
           } = view

    c |> call(:delete, "/snapshots/" <> snapshot["id"]) |> response(204)

    assert %{"code" => "snapshot_deleted", "message" => "Deleted by " <> _, "details" => details} =
             open.("/dashboard-snapshots/" <> snapshot["id"])
             |> json_response(404)
             |> Map.fetch!("error")

    assert %{"deleted_by" => %{"id" => _}, "deleted_at" => _} = details

    assert open.("/dashboard-snapshots/nope") |> json_response(404) |> get_in(["error", "code"]) ==
             "not_found"
  end
end
