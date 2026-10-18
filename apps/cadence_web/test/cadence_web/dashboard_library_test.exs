defmodule CadenceWeb.DashboardLibraryTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    Document,
    DocumentCodec,
    Documents,
    LibraryAuthoring,
    LibraryInput,
    Management,
    WidgetDef
  }

  alias Cadence.Reads.Dashboards.Library
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/library/producer-render-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "library-target-" <> Ecto.UUID.generate()
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    widget = hd(document.placements).widget_def |> WidgetDef.to_map()

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      document: document,
      widget: widget,
      json: Jason.encode!(widget)
    }
  end

  test "real producer metadata, definitions and consumers render in Vue", c do
    {:ok, empty} = Library.load(c.scope, c.mission.mission_id)
    {:ok, item} = execute(c, "create_item", creation(c))

    {:ok, _} =
      execute(c, "add_to_draft", %{
        "item_id" => item.item_id,
        "version" => 1,
        "dashboard_id" => c.document.dashboard_id,
        "expected_version" => 1
      })

    {:ok, selected} =
      Library.load(c.scope, c.mission.mission_id, %{
        "item_id" => item.item_id,
        "target_id" => c.document.dashboard_id
      })

    {:ok, historical} =
      Library.load(c.scope, c.mission.mission_id, %{"item_id" => item.item_id, "version" => "1"})

    node =
      System.find_executable("node") ||
        flunk("Node is required for the library producer contract")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!([empty, selected, historical])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "consumer and target pages are bounded and exclude foreign and archived documents", c do
    {:ok, item} = execute(c, "create_item", creation(c))

    pin = %Cadence.Dashboards.Placement{
      placement_id: "pin",
      content_kind: :library,
      library_widget_id: item.item_id,
      library_version: 1,
      overrides: %{"private" => "not-in-consumer-metadata"}
    }

    document = Document.put_placement(c.document, pin)

    for number <- 1..28 do
      {:ok, _} =
        Documents.persist(c.org.organization_id, %{
          document
          | dashboard_id: "consumer-" <> String.pad_leading(to_string(number), 2, "0"),
            name: "Consumer #{number}"
        })
    end

    :ok = Documents.archive(c.org.organization_id, c.mission.mission_id, "consumer-28", [])
    mission = TestFixtures.persist_mission!(c.org)

    {:ok, _} =
      Documents.persist(c.org.organization_id, %{
        document
        | dashboard_id: "foreign-consumer",
          mission_id: mission.mission_id
      })

    {:ok, first} = Library.load(c.scope, c.mission.mission_id, %{"item_id" => item.item_id})
    assert length(first.dashboards) == 25
    assert length(first.selected.consumers.rows) == 25
    assert first.selected.consumers.total == 27
    refute Jason.encode!(first) =~ "not-in-consumer-metadata"

    {:ok, next} =
      Library.load(c.scope, c.mission.mission_id, %{
        "item_id" => item.item_id,
        "consumer_after" => first.selected.consumers.next,
        "dashboard_after" => first.next_dashboard
      })

    assert length(next.selected.consumers.rows) == 2
    assert next.selected.consumers.next == nil
    assert length(next.dashboards) == 3
    assert Enum.all?(next.selected.consumers.rows, &(&1.id != "foreign-consumer"))
  end

  test "library versions are immutable, attributed and require the observed latest version", c do
    assert {:ok, created} = execute(c, "create_item", creation(c))

    input = %{
      "item_id" => created.item_id,
      "expected_version" => 1,
      "widget_json" => c.json,
      "change_summary" => "Revised"
    }

    assert {:ok, %{library_version: 2}} = execute(c, "add_version", input)
    assert {:error, :conflict} = execute(c, "add_version", input)

    assert {:ok, model} =
             Library.load(c.scope, c.mission.mission_id, %{
               "item_id" => created.item_id,
               "version" => "1"
             })

    assert model.selected.item.latest_version == 2
    assert model.selected.version == 1
    assert [%{version: 2, actor_id: actor}, %{version: 1}] = model.selected.versions
    assert actor == c.user.user_id
    assert Jason.decode!(model.selected.widget_json) == Jason.decode!(c.json)
  end

  test "adding an exact pin changes only the draft and consumers do not auto-upgrade", c do
    {:ok, item} = execute(c, "create_item", creation(c))

    {:ok, _} =
      Documents.publish(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        1,
        []
      )

    input = %{
      "item_id" => item.item_id,
      "version" => 1,
      "dashboard_id" => c.document.dashboard_id,
      "expected_version" => 1
    }

    assert {:ok, %{document_version: 2, placement_id: pin}} = execute(c, "add_to_draft", input)
    assert {:error, :conflict} = execute(c, "add_to_draft", input)

    assert {:ok, _} =
             execute(c, "add_version", %{
               "item_id" => item.item_id,
               "expected_version" => 1,
               "widget_json" => c.json,
               "change_summary" => "Second"
             })

    {:ok, model} =
      Library.load(c.scope, c.mission.mission_id, %{
        "item_id" => item.item_id,
        "target_id" => c.document.dashboard_id
      })

    assert model.target.version == 2
    assert model.selected.consumers.total == 1
    assert [%{id: dashboard, pins: [%{id: ^pin, version: 1}]}] = model.selected.consumers.rows
    assert dashboard == c.document.dashboard_id

    {:ok, published} =
      Documents.fetch_published(c.org.organization_id, c.mission.mission_id, dashboard)

    assert published.placements == c.document.placements
    {:ok, saved} = Documents.fetch(c.org.organization_id, c.mission.mission_id, dashboard)
    assert Document.version(saved) == 2
    assert hd(saved.placements) == hd(c.document.placements)
    assert Enum.find(saved.placements, &(&1.placement_id == pin)).library_version == 1
    [_, latest] = Documents.list_versions(c.org.organization_id, c.mission.mission_id, dashboard)
    assert latest.created_by == c.user.user_id
  end

  test "library and history pages remain bounded and search treats wildcard characters literally",
       c do
    {:ok, item} = execute(c, "create_item", creation(c))

    for number <- 2..28 do
      assert {:ok, _} = execute(c, "create_item", %{creation(c) | "name" => "Library #{number}"})

      assert {:ok, _} =
               execute(c, "add_version", %{
                 "item_id" => item.item_id,
                 "expected_version" => number - 1,
                 "widget_json" => c.json,
                 "change_summary" => "Version #{number}"
               })
    end

    {:ok, first} = Library.load(c.scope, c.mission.mission_id, %{"item_id" => item.item_id})
    assert length(first.items) == 25
    assert length(first.selected.versions) == 25

    {:ok, next} =
      Library.load(c.scope, c.mission.mission_id, %{
        "item_id" => item.item_id,
        "after" => first.next_item,
        "before_version" => to_string(first.selected.next_version)
      })

    assert length(next.items) == 3
    assert Enum.map(next.selected.versions, & &1.version) == [3, 2, 1]
    assert next.next_item == nil
    {:ok, empty} = Library.load(c.scope, c.mission.mission_id, %{"q" => "%"})
    assert empty.items == []
    {:ok, match} = Library.load(c.scope, c.mission.mission_id, %{"q" => "POWER"})
    assert [%{id: id}] = match.items
    assert id == item.item_id
  end

  test "invalid input, archived targets and foreign scopes cannot create a pin or a version", c do
    {:ok, item} = execute(c, "create_item", creation(c))

    for json <- [
          "{",
          "[]",
          "{}",
          String.duplicate(" ", 32_769),
          Jason.encode!(%{"widget_type_id" => "cadence.value_tile", "binding" => []})
        ] do
      assert {:error, :invalid_widget} =
               execute(c, "create_item", %{creation(c) | "widget_json" => json})
    end

    assert {:error, :invalid_input} =
             execute(c, "create_item", Map.put(creation(c), "created_by", "forged"))

    for query <- [
          %{"version" => "1"},
          %{"item_id" => item.item_id, "version" => "01"},
          %{"item_id" => "missing"},
          %{"after" => "\n"}
        ] do
      assert {:error, _} = Library.load(c.scope, c.mission.mission_id, query)
    end

    foreign = TestFixtures.persist_mission!(c.org)

    assert {:error, :unavailable} =
             Library.load(c.scope, foreign.mission_id, %{"item_id" => item.item_id})

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: foreign.mission_id}
        ] do
      assert {:error, _} = Library.load(scope, c.mission.mission_id)

      assert {:error, _} =
               LibraryAuthoring.execute(scope, c.mission.mission_id, "create_item", creation(c))
    end

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id, [])

    assert {:error, :unavailable} =
             execute(c, "add_to_draft", %{
               "item_id" => item.item_id,
               "version" => 1,
               "dashboard_id" => c.document.dashboard_id,
               "expected_version" => 1
             })

    assert length(Management.list_library_items(c.org.organization_id, c.mission.mission_id)) == 1
    assert length(Management.list_library_versions(item.item_id)) == 1
  end

  test "JSON limits contain excessive nesting and field counts before domain normalization", c do
    nested = Enum.reduce(1..10, %{}, fn _, value -> %{"nested" => value} end)

    for options <- [
          nested,
          Map.new(1..65, &{to_string(&1), true}),
          %{"list" => List.duplicate(0, 101)}
        ] do
      assert {:error, :invalid_widget} =
               LibraryInput.decode(Jason.encode!(Map.put(c.widget, :options, options)))
    end
  end

  test "widget JSON defaults do not admit malformed explicit fields" do
    for value <- [
          %{"widget_type_id" => "type"},
          %{"widget_type_id" => "type", "title" => nil, "binding" => %{}, "options" => %{}}
        ] do
      assert {:ok, ^value} = LibraryInput.decode(Jason.encode!(value))
    end

    for fields <- [
          %{"binding" => nil},
          %{"options" => nil},
          %{"title" => %{}},
          %{"title" => 42},
          %{"widget_type_id" => String.duplicate("x", 257)},
          %{"widget_type_id" => String.duplicate("é", 129)},
          %{"widget_type_id" => "bad\nidentifier"},
          %{"widget_type_version" => 9_007_199_254_740_991}
        ] do
      json = Jason.encode!(Map.merge(%{"widget_type_id" => "type"}, fields))
      assert {:error, :invalid_widget} = LibraryInput.decode(json)
    end
  end

  defp creation(c),
    do: %{
      "name" => "Power",
      "description" => "Reusable power tile",
      "change_summary" => "Initial",
      "widget_json" => c.json
    }

  defp execute(c, event, input),
    do: LibraryAuthoring.execute(c.scope, c.mission.mission_id, event, input)
end
