defmodule CadenceWeb.Console.DashboardImportAPITest do
  @moduledoc "Dashboards D4b: create a dashboard from its exported document (#746)."
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardPageTestSupport

  alias Cadence.Dashboards.Documents
  alias CadenceWeb.TestFixtures

  setup do: dashboard_page_setup()

  defp base(c, mission \\ nil),
    do: "/api/console/v1/missions/#{mission || c.mission.mission_id}/dashboards"

  defp member(c), do: TestFixtures.member_conn(c.user)
  defp post_json(conn, path, body), do: post(conn, path, body)

  # The bundle `GET /dashboards/:id/export` returns, decoded.
  defp export(c, id \\ nil) do
    id = id || c.document.dashboard_id
    c |> member() |> get(base(c) <> "/#{id}/export") |> json_response(200)
  end

  # The same bundle for another dashboard id: the integrity hash covers bindings, not identity.
  defp bundle_with_id(bundle, id, overrides \\ %{}) do
    Map.update!(bundle, "document", fn document ->
      document |> Map.put("dashboard_id", id) |> Map.merge(overrides)
    end)
  end

  defp import_keep(c, bundle, mission \\ nil) do
    c |> member() |> post_json(base(c, mission), %{"document" => bundle, "identity" => "keep"})
  end

  defp new_id, do: "imported-" <> Ecto.UUID.generate()

  defp comparable(document),
    do: update_in(document, ["metadata"], &Map.drop(&1 || %{}, ["version", "dashboard_version"]))

  test "keep creates the dashboard as version 1 and exporting it returns the same document", c do
    id = new_id()
    bundle = c |> export() |> bundle_with_id(id)

    assert %{"data" => %{"id" => ^id, "version" => 1}} =
             c |> import_keep(bundle) |> json_response(201)

    assert {:ok, saved} =
             Documents.fetch_for_mode(c.org.organization_id, c.mission.mission_id, id, :edit)

    assert saved.organization_id == c.org.organization_id and
             saved.mission_id == c.mission.mission_id

    # Round trip: the imported dashboard exports as the document it was made from.
    assert comparable(export(c, id)["document"]) == comparable(bundle["document"])
  end

  test "the session user is the author of the first version", c do
    id = new_id()
    assert c |> import_keep(bundle_with_id(export(c), id)) |> json_response(201)

    version = Documents.list_versions(c.org.organization_id, c.mission.mission_id, id) |> hd()
    assert inspect(version) =~ c.user.user_id
  end

  test "re-running keep with the identical document is 200 and changes nothing", c do
    id = new_id()
    bundle = c |> export() |> bundle_with_id(id)

    assert c |> import_keep(bundle) |> json_response(201)

    assert %{"data" => %{"id" => ^id, "version" => 1, "existing" => true}} =
             c |> import_keep(bundle) |> json_response(200)

    assert length(Documents.list_versions(c.org.organization_id, c.mission.mission_id, id)) == 1
  end

  test "the same id with a different document is 409 with a diff summary", c do
    id = new_id()
    bundle = c |> export() |> bundle_with_id(id)
    assert c |> import_keep(bundle) |> json_response(201)

    renamed = bundle_with_id(bundle, id, %{"name" => "Another name"})

    assert %{
             "error" => %{
               "code" => "dashboard_import_conflict",
               "details" => %{
                 "differences" => %{"fields" => ["name"], "placements" => placements}
               }
             }
           } = c |> import_keep(renamed) |> json_response(409)

    assert placements == %{"added" => [], "removed" => [], "changed" => []}
  end

  test "an id another mission of the organization holds is refused, naming that mission", c do
    other = TestFixtures.persist_mission!(c.org)

    assert %{"error" => %{"code" => "dashboard_id_in_use", "details" => details}} =
             c |> import_keep(export(c), other.mission_id) |> json_response(409)

    assert details == %{"mission_id" => c.mission.mission_id}
  end

  test "an id another organization holds is refused without naming anything", c do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    body = %{"document" => export(c), "identity" => "keep"}
    conn = user |> TestFixtures.member_conn() |> post_json(base(c, mission.mission_id), body)

    assert %{"error" => %{"code" => "dashboard_id_in_use"} = error} = json_response(conn, 409)
    refute Map.has_key?(error, "details")
    refute inspect(error) =~ c.mission.mission_id
  end

  test "copy (the default) makes a new dashboard with a new id and a renamed copy", c do
    bundle = export(c)
    original = c.document.dashboard_id

    assert %{"data" => %{"id" => copy_id, "version" => 1}} =
             c |> member() |> post_json(base(c), %{"document" => bundle}) |> json_response(201)

    refute copy_id == original

    assert {:ok, copy} =
             Documents.fetch_for_mode(c.org.organization_id, c.mission.mission_id, copy_id, :edit)

    assert copy.name == "Copy of " <> c.document.name

    assert %{"data" => %{"id" => named_id}} =
             c
             |> member()
             |> post_json(base(c), %{"document" => bundle, "identity" => "copy", "name" => "Mine"})
             |> json_response(201)

    assert {:ok, %{name: "Mine"}} =
             Documents.fetch_for_mode(
               c.org.organization_id,
               c.mission.mission_id,
               named_id,
               :edit
             )
  end

  test "bad input is a 422 naming the field", c do
    bundle = export(c)
    post = fn body -> c |> member() |> post_json(base(c), body) |> json_response(422) end

    assert %{"error" => %{"details" => %{"field" => "identity"}}} =
             post.(%{"document" => bundle, "identity" => "bogus"})

    # A kept id keeps the document, so a rename is refused.
    assert %{"error" => %{"details" => %{"field" => "name"}}} =
             post.(%{"document" => bundle, "identity" => "keep", "name" => "Renamed"})

    # A bundle whose content no longer matches its integrity hash.
    tampered = put_in(bundle, ["document", "defaults"], %{"tampered" => true})

    assert %{"error" => %{"details" => %{"field" => "document"}}} =
             post.(%{"document" => tampered, "identity" => "keep"})

    assert %{"error" => %{"details" => %{"field" => "document"}}} =
             post.(%{"document" => %{"unrelated" => 1}, "identity" => "keep"})
  end

  test "a document that is not ready for this mission is 422 and leaves no dashboard", c do
    before = length(Documents.list(c.org.organization_id, c.mission.mission_id))
    id = new_id()
    bundle = c |> export() |> bundle_with_id(id) |> break_binding()

    assert %{"error" => %{"code" => code}} = c |> import_keep(bundle) |> json_response(422)
    assert code in ["dashboard_not_ready", "invalid_params"]

    assert Documents.fetch_for_mode(c.org.organization_id, c.mission.mission_id, id, :edit)
           |> elem(0) == :error

    assert length(Documents.list(c.org.organization_id, c.mission.mission_id)) == before
  end

  # An observable no mission has, in every placement's binding.
  defp break_binding(bundle) do
    update_in(bundle, ["document", "placements"], fn placements ->
      Enum.map(placements, fn placement ->
        put_in(placement, ["content", "widget_def", "binding", "observables"], [
          "no.such.observable"
        ])
      end)
    end)
  end
end
