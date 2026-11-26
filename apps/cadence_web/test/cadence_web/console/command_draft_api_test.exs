defmodule CadenceWeb.Console.CommandDraftAPITest do
  @moduledoc "Compose's current draft: one per user per mission, revisioned, author-only."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.ControlPlaneApiFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    other = TestFixtures.persist_user!(display_name: "Ana R.")
    TestFixtures.grant_membership!(user, org)
    TestFixtures.grant_membership!(other, org)
    mission = TestFixtures.persist_mission!(org)
    ControlPlaneApiFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)
    %{user: user, other: other, mission: mission}
  end

  defp path(c), do: "/api/v1/missions/#{c.mission.mission_id}/command-draft"
  defp as(user), do: TestFixtures.member_conn(user)

  defp document(title, stack \\ [%{"key" => "k1", "command_id" => "NOOP", "values" => %{}}]) do
    %{
      "schema_version" => 1,
      "title" => title,
      "stack" => stack,
      "target_query" => %{"plane" => 7, "profile" => nil, "states" => [], "explicit" => []},
      "release" => %{"mode" => "next_contact", "not_before" => nil}
    }
  end

  defp put_draft(c, user, doc, expected),
    do: user |> as() |> put(path(c), %{document: doc, expected_revision: expected})

  test "autosave overwrites the one draft; a stale save is 409 with the current revision", c do
    assert %{"data" => %{"revision" => 1, "saved_at" => _}} =
             c |> put_draft(c.user, document("Load shed"), nil) |> json_response(200)

    assert %{"data" => %{"revision" => 2}} =
             c |> put_draft(c.user, document("Load shed v2"), 1) |> json_response(200)

    # Another tab still at revision 1, or a first save when one exists.
    for expected <- [1, nil] do
      assert %{"error" => %{"code" => "command_draft_changed", "details" => %{"revision" => 2}}} =
               c |> put_draft(c.user, document("stale"), expected) |> json_response(409)
    end

    data = c.user |> as() |> get(path(c)) |> json_response(200) |> get_in(["data", "draft"])
    assert %{"revision" => 2, "document" => %{"title" => "Load shed v2"}} = data

    assert %{"revision_saved" => _, "revision_now" => _, "missing_command_ids" => _} =
             data["catalog"]
  end

  test "a draft is its author's alone; delete discards it", c do
    assert c |> put_draft(c.user, document("Mine"), nil) |> json_response(200)

    # Someone else's draft isn't visible: no draft is 200 with null, not an error.
    assert %{"data" => %{"draft" => nil}} = c.other |> as() |> get(path(c)) |> json_response(200)

    # The other operator's first save is their own draft, not a conflict with mine.
    assert %{"data" => %{"revision" => 1}} =
             c |> put_draft(c.other, document("Theirs"), nil) |> json_response(200)

    assert c.user |> as() |> delete(path(c)) |> response(204)
    assert %{"data" => %{"draft" => nil}} = c.user |> as() |> get(path(c)) |> json_response(200)

    assert %{"data" => %{"draft" => %{"document" => %{"title" => "Theirs"}}}} =
             c.other |> as() |> get(path(c)) |> json_response(200)
  end

  test "malformed documents and revisions are 422", c do
    for {doc, expected, key} <- [
          {%{"stack" => []}, nil, "document"},
          {document("x", [%{"values" => %{}}]), nil, "document.stack"},
          {document("x"), "two", "expected_revision"}
        ] do
      assert %{"error" => %{"code" => "invalid_params", "details" => details}} =
               c |> put_draft(c.user, doc, expected) |> json_response(422)

      assert Map.has_key?(details, key)
    end
  end
end
