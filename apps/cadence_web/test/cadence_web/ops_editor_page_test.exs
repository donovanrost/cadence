defmodule CadenceWeb.OpsEditorPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{AuthoringWidget, Document, DocumentCodec, Documents}
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Governance
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/editor/producer-render-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "editor-" <> Ecto.UUID.generate(),
        metadata: %{secret: "private-authoring-metadata"}
    }

    {:ok, document} = Documents.persist(org.organization_id, document)

    %{
      org: org,
      mission: mission,
      user: user,
      scope:
        Scope.new(%{
          user: user,
          organization_id: org.organization_id,
          organization_membership: membership
        }),
      document: document,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}/edit"
    }
  end

  test "the editor route composes an authorized draft and its real Vue producer contract", c do
    {:ok, view, _} = live(c.conn, c.path)
    page = page(view)
    assert page["id"] == "dashboards.editor"
    assert page["status"] == "ready"
    assert page["context"]["resourceId"] == c.document.dashboard_id
    assert page["data"]["model"]["document_version"] == 1
    assert page["data"]["model"]["version"] == 3
    assert page["data"]["version"] == 2
    assert page["data"]["revision"] == 0
    refute page["data"]["dirty"]
    assert Jason.decode!(page["data"]["model"]["runtime_defaults_json"]) == c.document.defaults
    assert page["data"]["model"]["grid"]["columns"] == 12

    assert [%{"constraints" => %{"min_w" => 2, "min_h" => 2, "max_y" => 23}}] =
             page["data"]["model"]["placements"]

    refute Jason.encode!(page) =~ "private-authoring-metadata"
    assert page["data"]["model"]["preview"]["document_mode"] == "draft"

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @renderer, Jason.encode!([page])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "layout staging retains dragged and displaced neighbors until one explicit save", c do
    [first] = c.document.placements
    second = %{first | placement_id: "neighbor", layout: %{first.layout | x: 4}}

    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | placements: [first, second]},
               expected_version: 1
             )

    {:ok, view, _} = live(c.conn, c.path)
    initial = page(view)

    layouts = [
      %{"placement_id" => first.placement_id, "x" => 4, "y" => 0, "w" => 4, "h" => 3},
      %{"placement_id" => second.placement_id, "x" => 4, "y" => 3, "w" => 4, "h" => 2}
    ]

    render_hook(
      view,
      "host:ops-page",
      request(c.path, initial, "layout", 1, %{"expected_version" => 2, "layouts" => layouts})
    )

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{sequence: 1, revision: 1, dirty: true, model: %{document_version: 2}}
      }
    })

    assert [%{"layout" => %{"x" => 4, "y" => 0, "h" => 3}}, %{"layout" => %{"x" => 4, "y" => 3}}] =
             page(view)["data"]["model"]["placements"]

    assert fetch(c).placements == [first, second]

    render_hook(
      view,
      "host:ops-page",
      request(c.path, page(view), "save_draft", 2, %{"expected_version" => 2})
    )

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{revision: 2, dirty: false, model: %{document_version: 3}}
      }
    })

    assert Enum.map(fetch(c).placements, & &1.layout.y) == [0, 3]
    assert length(versions(c)) == 3
  end

  test "runtime defaults use the admitted editor command lifecycle and validation keeps the draft editable",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    initial = page(view)

    render_hook(
      view,
      "host:ops-page",
      request(c.path, initial, "runtime_defaults", 1, %{
        "expected_version" => 1,
        "defaults_json" => "[]"
      })
    )

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "invalid",
        code: "invalid_defaults",
        state: %{sequence: 1, phase: "editing", model: %{document_version: 1}}
      }
    })

    defaults = put_in(c.document.defaults, ["limits", "semantics_mode"], "current")

    request =
      request(c.path, initial, "runtime_defaults", 2, %{
        "expected_version" => 1,
        "defaults_json" => Jason.encode!(defaults)
      })

    render_hook(view, "host:ops-page", request)

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{sequence: 2, revision: 1, dirty: true, model: %{document_version: 1}}
      }
    })

    assert Jason.decode!(page(view)["data"]["model"]["runtime_defaults_json"]) == defaults
    render_hook(view, "host:ops-page", request)
    assert_reply(view, %{ok: true, snapshot: %{status: "rejected"}})
  end

  test "authoring binds token, sequence and the displayed version while retaining the published version",
       c do
    assert {:ok, _} =
             Documents.publish(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               expected_version: 1
             )

    {:ok, view, _} = live(c.conn, c.path)
    first = page(view)
    command = %{"expected_version" => 1, "name" => "Draft only", "description" => ""}
    request = request(c.path, first, "rename", 1, command)
    render_hook(view, "host:ops-page", request)

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{sequence: 1, revision: 1, dirty: true, model: %{document_version: 1}}
      }
    })

    assert length(versions(c)) == 1
    assert fetch(c).name == c.document.name
    assert page(view)["token"] == first["token"]
    assert page(view)["data"]["model"]["name"] == "Draft only"
    render_hook(view, "host:ops-page", request)
    assert_reply(view, %{ok: true, snapshot: %{status: "rejected"}})

    render_hook(
      view,
      "host:ops-page",
      request(c.path, page(view), "save_draft", 2, %{"expected_version" => 1})
    )

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{revision: 2, dirty: false, model: %{document_version: 2}}
      }
    })

    assert {:ok, published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert published.name == c.document.name

    assert length(
             Documents.list_versions(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )
           ) == 2
  end

  test "concurrent edits require explicit reload and cannot be silently retried", c do
    {:ok, view, _} = live(c.conn, c.path)
    first = page(view)

    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | name: "Other operator"},
               expected_version: 1
             )

    command = %{"expected_version" => 1, "name" => "Stale edit", "description" => ""}
    render_hook(view, "host:ops-page", request(c.path, first, "rename", 1, command))
    assert_reply(view, %{ok: true, snapshot: %{status: "conflict", state: %{phase: "review"}}})
    refresh(view, c.path)
    assert page(view)["data"]["phase"] == "review"
    assert page(view)["data"]["model"]["name"] == c.document.name

    render_hook(
      view,
      "host:ops-page",
      request(c.path, first, "rename", 2, %{command | "expected_version" => 2})
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "rejected"}})
    render_hook(view, "host:ops-page", request(c.path, first, "reload_editor", 2, %{}))

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{sequence: 2, phase: "editing", model: %{document_version: 2}}
      }
    })

    assert {:ok, saved} =
             Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    assert saved.name == "Other operator"
    assert Document.version(saved) == 2
  end

  test "foreign token, resource and stale route messages cannot author a draft", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    action = request(c.path, original, "save_draft", 1, %{"expected_version" => 1})
    render_hook(view, "host:ops-page", %{action | "token" => Ecto.UUID.generate()})
    assert_reply(view, %{ok: false})
    other = TestFixtures.persist_mission!(c.org)
    refresh(view, "/missions/#{other.mission_id}/ops/dashboards/#{c.document.dashboard_id}/edit")
    assert page(view)["status"] == "unavailable"
    render_hook(view, "host:ops-page", action)
    assert_reply(view, %{ok: false})
    refresh(view, "/missions/#{c.mission.mission_id}/ops/dashboards")
    assert page(view)["id"] == "dashboards.directory"
    refresh(view, c.path)
    refute page(view)["token"] == original["token"]
    render_hook(view, "host:ops-page", action)
    assert_reply(view, %{ok: false})
  end

  test "refresh, mutation and observable search recheck revoked sessions", c do
    for operation <- ["refresh", "save_draft", "search_observables"] do
      conn = TestFixtures.member_conn(c.user)
      {:ok, view, _} = live(conn, c.path)
      action = request(c.path, page(view), operation, 1, %{"expected_version" => 1})

      action =
        if operation == "search_observables",
          do:
            Map.put(action, "input", %{
              "query" => "",
              "fields" => AuthoringWidget.defaults(),
              "expected_version" => 1,
              "expected_revision" => 0
            }),
          else: action

      :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
      event = if operation == "refresh", do: "host:context", else: "host:ops-page"
      render_hook(view, event, if(operation == "refresh", do: %{"path" => c.path}, else: action))
      assert_redirect(view, "/sign-in")
    end
  end

  test "observable searches use the selected widget scope without consuming a save sequence", c do
    {:ok, view, _} = live(c.conn, c.path)
    first = page(view)

    fields =
      AuthoringWidget.defaults()
      |> Map.merge(%{
        "type" => "time_series",
        "binding_source" => "operational_observables",
        "mode" => "scope",
        "scope_kind" => "spacecraft",
        "scope_id" => "craft"
      })

    search(view, c.path, first, fields, "downlink")

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        choices: %{options: [%{value: "comms.transport.downlink_bitrate"}]}
      }
    })

    assert page(view) == first

    search(
      view,
      c.path,
      first,
      %{fields | "scope_kind" => "mission", "scope_id" => c.mission.mission_id},
      "downlink"
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "ok", choices: %{options: []}}})
    assert page(view) == first
  end

  test "canonical catalog choices are bounded and mission scoped and satisfy the Vue contract",
       c do
    for n <- 1..51 do
      definition =
        Definition.new(%{
          mission_id: c.mission.mission_id,
          point_id: "DERIVED.choice_#{n}",
          expression: "HK.counter * 2"
        })

      assert {:ok, _} = Governance.persist_derived_definition(definition)
    end

    other = TestFixtures.persist_mission!(c.org)

    foreign =
      Definition.new(%{
        mission_id: other.mission_id,
        point_id: "DERIVED.choice_FOREIGN",
        expression: "HK.counter * 2"
      })

    assert {:ok, _} = Governance.persist_derived_definition(foreign)
    {:ok, view, _} = live(c.conn, c.path)
    first = page(view)
    search(view, c.path, first, AuthoringWidget.defaults(), "DERIVED.choice")
    assert_reply(view, %{ok: true, snapshot: %{status: "ok", choices: choices}})
    assert length(choices.options) == 50
    assert choices.more
    refute Enum.any?(choices.options, &(&1.value == foreign.point_id))

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @renderer, Jason.encode!([first]), Jason.encode!([choices])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "malformed catalog identifiers are contained before returning a choices DTO", c do
    definition =
      Definition.new(%{
        mission_id: c.mission.mission_id,
        point_id: "DERIVED.invalid\nid",
        point_name: "Invalid identifier",
        expression: "HK.counter * 2"
      })

    assert {:ok, _} = Governance.persist_derived_definition(definition)
    {:ok, view, _} = live(c.conn, c.path)
    first = page(view)

    search(
      view,
      c.path,
      first,
      AuthoringWidget.defaults(),
      "DERIVED.invalid"
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})
    assert page(view) == first
  end

  test "search rejects stale versions, malformed input and foreign tokens", c do
    {:ok, view, _} = live(c.conn, c.path)
    first = page(view)
    fields = AuthoringWidget.defaults()
    search(view, c.path, first, fields, String.duplicate("x", 257))
    assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})
    search(view, c.path, first, Map.put(fields, "extra", "no"), "")
    assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})
    search(view, c.path, Map.put(first, "token", Ecto.UUID.generate()), fields, "")
    assert_reply(view, %{ok: false})

    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | name: "Changed elsewhere"},
               expected_version: 1
             )

    search(view, c.path, first, fields, "")
    assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})

    request =
      request(c.path, first, "search_observables", 0, %{})
      |> Map.put("input", %{"query" => "", "fields" => fields, "expected_version" => 2})

    render_hook(view, "host:ops-page", request)
    assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})
    assert page(view) == first
  end

  test "moving and resizing ten widgets with refreshes retains one candidate until Save", c do
    [base] = c.document.placements

    placements =
      for n <- 1..10,
          do: %{base | placement_id: "widget-#{n}", layout: %{base.layout | y: (n - 1) * 2}}

    document = %{
      c.document
      | dashboard_id: "ten-" <> Ecto.UUID.generate(),
        placements: placements
    }

    {:ok, document} = Documents.persist(c.org.organization_id, document)

    c = %{
      c
      | document: document,
        path: "/missions/#{c.mission.mission_id}/ops/dashboards/#{document.dashboard_id}/edit"
    }

    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    for revision <- 1..10 do
      current = page(view)

      layout = %{
        "placement_id" => "widget-#{revision}",
        "x" => 4,
        "y" => (revision - 1) * 2,
        "w" => 4,
        "h" => 2
      }

      render_hook(
        view,
        "host:ops-page",
        request(c.path, current, "layout", revision, %{
          "expected_version" => 1,
          "layouts" => [layout]
        })
      )

      assert_reply(view, %{
        ok: true,
        snapshot: %{
          status: "ok",
          state: %{revision: ^revision, dirty: true, model: %{document_version: 1}}
        }
      })

      staged = page(view)
      refresh(view, c.path)
      assert page(view) == staged
      assert page(view)["token"] == original["token"]
      assert fetch(c) == c.document
      assert length(versions(c)) == 1
    end

    render_hook(
      view,
      "host:ops-page",
      request(c.path, original, "save_draft", 11, %{"expected_version" => 1})
    )

    assert_reply(view, %{
      ok: true,
      snapshot: %{status: "rejected", state: %{revision: 10, sequence: 10}}
    })

    render_hook(
      view,
      "host:ops-page",
      request(c.path, page(view), "save_draft", 11, %{"expected_version" => 1})
    )

    assert_reply(view, %{
      ok: true,
      snapshot: %{
        status: "ok",
        state: %{revision: 11, dirty: false, model: %{document_version: 2}}
      }
    })

    assert length(versions(c)) == 2
    assert length(fetch(c).placements) == 10
    assert Enum.all?(fetch(c).placements, &(&1.layout.x == 4 and &1.layout.w == 4))
    assert Enum.map(fetch(c).placements, & &1.layout.y) == Enum.map(0..9, &(&1 * 2))
  end

  test "discard restores the starting document and rejects delayed or whole-document commands",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    render_hook(
      view,
      "host:ops-page",
      request(c.path, original, "rename", 1, %{
        "expected_version" => 1,
        "name" => "Staged",
        "description" => ""
      })
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
    staged = page(view)

    for {event, status, extra} <- [
          {"publish", "rejected", %{}},
          {"save_draft", "invalid", %{"document" => %{"name" => "Forged"}}}
        ] do
      command = Map.put(extra, "expected_version", 1)
      render_hook(view, "host:ops-page", request(c.path, page(view), event, 2, command))
      assert_reply(view, %{ok: true, snapshot: %{status: ^status}})
      assert fetch(c) == c.document
    end

    current = page(view)
    sequence = current["data"]["sequence"] + 1

    render_hook(
      view,
      "host:ops-page",
      request(c.path, current, "discard_draft", sequence, %{"expected_version" => 1})
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "ok", state: %{revision: 2, dirty: false}}})

    assert page(view)["data"]["model"]["name"] == c.document.name
    assert fetch(c) == c.document
    assert length(versions(c)) == 1

    render_hook(
      view,
      "host:ops-page",
      request(c.path, staged, "save_draft", sequence + 1, %{"expected_version" => 1})
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "rejected"}})

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @renderer, Jason.encode!([original, staged, page(view)])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "observable choices follow unsaved defaults and reject an earlier staging revision", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    fields =
      Map.merge(AuthoringWidget.defaults(), %{
        "type" => "time_series",
        "binding_source" => "operational_observables"
      })

    search(view, c.path, original, fields, "downlink")

    assert_reply(view, %{
      ok: true,
      snapshot: %{status: "ok", choices: %{staging_revision: 0, options: [_]}}
    })

    defaults =
      put_in(c.document.defaults, ["scope", "primary"], %{
        "kind" => "mission",
        "mode" => "one",
        "ids" => [c.mission.mission_id]
      })

    render_hook(
      view,
      "host:ops-page",
      request(c.path, original, "runtime_defaults", 1, %{
        "expected_version" => 1,
        "defaults_json" => Jason.encode!(defaults)
      })
    )

    assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
    staged = page(view)
    search(view, c.path, staged, fields, "downlink")

    assert_reply(view, %{
      ok: true,
      snapshot: %{status: "ok", choices: %{staging_revision: 1, document_version: 1, options: []}}
    })

    search(view, c.path, original, fields, "downlink")
    assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})
    assert page(view) == staged
    assert fetch(c).defaults == c.document.defaults
  end

  test "malformed actions clear retained content after authorization loss and old sessions rotate",
       c do
    route = %{
      route: "/missions/:mission_id/ops/dashboards/:dashboard_id/edit",
      params: %{"mission_id" => c.mission.mission_id, "dashboard_id" => c.document.dashboard_id}
    }

    socket =
      Phoenix.Component.assign(%Phoenix.LiveView.Socket{},
        current_scope: c.scope,
        host_path: c.path
      )

    socket = CadenceWeb.OpsEditorPage.prepare(socket, route, c.path)
    original = socket.assigns.ops_editor_session

    socket =
      Phoenix.Component.assign(socket, :ops_editor_session, Map.put(original, :contract, 1))

    socket = CadenceWeb.OpsEditorPage.prepare(socket, route, c.path)
    refute socket.assigns.ops_editor_session.token == original.token
    assert socket.assigns.ops_editor_session.contract == 2

    revoked = %{c.scope | organization_membership: nil}
    socket = Phoenix.Component.assign(socket, :current_scope, revoked)
    {response, socket} = CadenceWeb.OpsEditorPage.action(socket, "rename", %{})
    assert response.status == "rejected"
    assert response.state.model == nil
    assert socket.assigns.ops_editor_session.draft == nil
    assert socket.assigns.ops_page.status == "unavailable"
    refute Map.has_key?(socket.assigns.ops_page, :data)
    assert fetch(c) == c.document
  end

  defp search(view, path, page, fields, query) do
    request =
      request(path, page, "search_observables", 0, %{})
      |> Map.put("input", %{
        "query" => query,
        "fields" => fields,
        "expected_version" => page["data"]["model"]["document_version"],
        "expected_revision" => page["data"]["revision"]
      })

    render_hook(view, "host:ops-page", request)
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp request(path, page, event, sequence, command) do
    command =
      if event == "reload_editor",
        do: command,
        else: Map.put_new(command, "expected_revision", page["data"]["revision"])

    %{
      "path" => path,
      "id" => "dashboards.editor",
      "token" => page["token"],
      "event" => event,
      "input" => %{"sequence" => sequence, "command" => command}
    }
  end

  defp fetch(c) do
    {:ok, document} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    document
  end

  defp versions(c),
    do:
      Documents.list_versions(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )
end
