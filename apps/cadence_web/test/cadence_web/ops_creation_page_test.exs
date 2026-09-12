defmodule CadenceWeb.OpsCreationPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{Creation, Document, DocumentCodec, Documents}
  alias Cadence.Reads.Dashboards.Creation, as: CreationRead
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/creation/producer-render-check.mjs",
              __DIR__
            )

  test "the real Vue consumer renders authorized producer DTOs for all creation modes", c do
    models =
      for params <- [
            %{},
            %{"mode" => "import"},
            %{"mode" => "clone", "source_dashboard_id" => c.source.dashboard_id}
          ] do
        {:ok, model} = CreationRead.load(c.scope, c.mission.mission_id, params)
        model
      end

    node =
      System.find_executable("node") || flunk("Node is required for the creation DTO contract")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!(models)],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    %Document{} = base = DocumentCodec.load!(@fixture)

    source = %Document{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "creation-source-#{System.unique_integer([:positive])}",
        name: "Flight"
    }

    {:ok, source} = Documents.persist(org.organization_id, source)

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      source: source,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/dashboards/new"
    }
  end

  test "blank, clone and import create fresh scoped documents with copied content", c do
    for mode <- ~w(new clone import) do
      params =
        if mode == "clone",
          do: %{"mode" => mode, "source_dashboard_id" => c.source.dashboard_id},
          else: %{"mode" => mode}

      assert {:ok, model} = CreationRead.load(c.scope, c.mission.mission_id, params)
      {:ok, json} = DocumentCodec.encode_bundle(c.source)
      fields = %{"name" => "Created #{mode}", "description" => "Description"}
      fields = if mode == "import", do: Map.put(fields, "document_json", json), else: fields
      assert {:ok, receipt} = Creation.create(c.scope, c.mission.mission_id, model, fields)
      assert receipt.version == 1
      refute receipt.dashboard_id == c.source.dashboard_id

      assert {:ok, saved} =
               Documents.fetch(c.org.organization_id, c.mission.mission_id, receipt.dashboard_id)

      assert saved.name == "Created #{mode}"
      assert saved.organization_id == c.org.organization_id
      assert saved.mission_id == c.mission.mission_id
      assert saved.metadata["created_by"] == c.user.user_id
      if mode != "new", do: assert(saved.placements == c.source.placements)
    end
  end

  test "invalid mode, source, scope and input never create documents", c do
    for params <- [
          %{"mode" => "other"},
          %{"mode" => "clone"},
          %{"source_dashboard_id" => c.source.dashboard_id},
          %{"mode" => "clone", "source_dashboard_id" => "missing"},
          %{"extra" => true}
        ] do
      assert {:error, _} = CreationRead.load(c.scope, c.mission.mission_id, params)
    end

    {:ok, model} = CreationRead.load(c.scope, c.mission.mission_id)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"}
        ] do
      assert {:error, _} = CreationRead.load(scope, c.mission.mission_id)

      assert {:error, _} =
               Creation.create(scope, c.mission.mission_id, model, %{
                 "name" => "Denied",
                 "description" => ""
               })
    end

    for fields <- [
          %{"name" => "", "description" => ""},
          %{"name" => String.duplicate("x", 513), "description" => ""},
          %{"name" => "Invalid", "description" => "", "organization_id" => "foreign"}
        ] do
      assert {:invalid, :fields} = Creation.create(c.scope, c.mission.mission_id, model, fields)
    end

    {:ok, imported} = CreationRead.load(c.scope, c.mission.mission_id, %{"mode" => "import"})

    assert {:invalid, :document} =
             Creation.create(c.scope, c.mission.mission_id, imported, %{
               "name" => "Invalid",
               "description" => "",
               "document_json" => "{invalid"
             })

    assert length(Documents.list(c.org.organization_id, c.mission.mission_id)) == 1
  end

  test "host admits the displayed mode, consumes one creation and retains its lock on refresh",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    page = page(view)
    assert page["id"] == "dashboards.creation"
    assert page["slot"] == "ops.page"
    assert page["status"] == "ready"

    input = %{
      "sequence" => 1,
      "source_version" => nil,
      "dashboard" => %{"name" => "Blank", "description" => ""}
    }

    assert action(view, c.path, %{page | "token" => Ecto.UUID.generate()}, input)["ok"] == false

    assert action(view, c.path, page, Map.put(input, "sequence", 1.0))["snapshot"]["status"] ==
             "rejected"

    assert action(view, c.path, page, Map.put(input, "source_version", 1))["snapshot"]["status"] ==
             "rejected"

    reply = action(view, c.path, page, input)
    assert reply["snapshot"]["status"] == "ok"
    assert action(view, c.path, page, input)["snapshot"]["status"] == "rejected"
    refresh(view, c.path)
    assert page(view)["token"] == page["token"]
    assert page(view)["data"]["phase"] == "submitted"

    assert action(view, c.path, page, Map.put(input, "sequence", 2))["snapshot"]["status"] ==
             "rejected"

    assert length(Documents.list(c.org.organization_id, c.mission.mission_id)) == 2
    refresh(view, String.replace_suffix(c.path, "/new", ""))
    assert action(view, c.path, page, input)["ok"] == false
  end

  test "clone query is admitted, stale source is rejected before persistence, refresh permits reviewed version",
       c do
    path = c.path <> "?mode=clone&source_dashboard_id=" <> c.source.dashboard_id
    {:ok, view, _} = live(c.conn, path)
    page = page(view)
    assert page["data"]["model"]["source"]["id"] == c.source.dashboard_id

    input = %{
      "sequence" => 1,
      "source_version" => 1,
      "dashboard" => %{"name" => "Clone", "description" => ""}
    }

    %Document{} = source = c.source

    {:ok, _} =
      Documents.update(
        c.org.organization_id,
        c.mission.mission_id,
        source.dashboard_id,
        %Document{source | name: "Changed"},
        []
      )

    assert action(view, path, page, input)["snapshot"] == %{
             "status" => "invalid",
             "code" => "source_changed",
             "sequence" => 1
           }

    assert length(Documents.list(c.org.organization_id, c.mission.mission_id)) == 1
    refresh(view, path)
    assert page(view)["data"]["model"]["source"]["version"] == 2

    assert action(view, path, page, %{input | "sequence" => 2, "source_version" => 2})["snapshot"][
             "status"
           ] == "ok"
  end

  test "invalid import can be corrected, while revoked authentication rejects effects", c do
    path = c.path <> "?mode=import"
    {:ok, view, _} = live(c.conn, path)
    page = page(view)
    assert page["data"]["model"]["mode"] == "import"

    input = %{
      "sequence" => 1,
      "source_version" => nil,
      "dashboard" => %{"name" => "Import", "description" => "", "document_json" => "{invalid"}
    }

    assert action(view, path, page, input)["snapshot"]["status"] == "invalid"
    assert length(Documents.list(c.org.organization_id, c.mission.mission_id)) == 1
    {:ok, json} = DocumentCodec.encode_bundle(c.source)

    corrected = %{
      input
      | "sequence" => 2,
        "dashboard" => Map.put(input["dashboard"], "document_json", json)
    }

    assert action(view, path, page, corrected)["snapshot"]["status"] == "ok"
    {:ok, denied, _} = live(c.conn, c.path)
    denied_page = page(denied)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(denied, "host:ops-page", %{
      "id" => denied_page["id"],
      "token" => denied_page["token"],
      "path" => c.path,
      "event" => "create",
      "input" => input
    })

    assert_redirect(denied, "/sign-in")
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, input) do
    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => path,
      "event" => "create",
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
