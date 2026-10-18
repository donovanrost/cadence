defmodule CadenceWeb.DashboardAuthoringTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{Authoring, AuthoringWidget, Document, DocumentCodec, Documents}
  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
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
        dashboard_id: "authoring-" <> Ecto.UUID.generate()
    }

    assert {:ok, document} = Documents.persist(org.organization_id, document)
    %{org: org, user: user, mission: mission, scope: scope, document: document}
  end

  test "commands use the version the operator saw and attribute immutable snapshots", c do
    assert {:ok, %{document_version: 2, event: "rename"}} =
             execute(c, "rename", 1, %{"name" => " Draft ", "description" => " Updated "})

    assert {:error, :conflict} =
             execute(c, "rename", 1, %{"name" => "Stale overwrite", "description" => ""})

    assert {:ok, saved} = fetch(c)
    assert saved.name == "Draft"
    assert saved.description == "Updated"
    assert Document.version(saved) == 2

    [first, second] =
      Documents.list_versions(c.org.organization_id, c.mission.mission_id, saved.dashboard_id)

    assert first.document.name == c.document.name
    assert second.created_by == c.user.user_id
    assert second.change_summary == "Dashboard editor: rename"
  end

  test "runtime defaults are versioned independently, preserve the rest of the document and publish separately",
       c do
    assert {:ok, _} = execute(c, "publish", 1, %{})
    defaults = put_in(c.document.defaults, ["time", "axis"], "receipt_time")
    payload = %{"defaults_json" => Jason.encode!(defaults)}

    assert {:ok, %{document_version: 2, event: "runtime_defaults"}} =
             execute(c, "runtime_defaults", 1, payload)

    assert {:ok, saved} = fetch(c)
    assert saved.defaults == defaults
    assert Document.version(saved) == 2

    assert Map.drop(Document.to_map(saved), [:defaults, :metadata]) ==
             Map.drop(Document.to_map(c.document), [:defaults, :metadata])

    assert Map.drop(saved.metadata, ["version", :version]) ==
             Map.drop(c.document.metadata, ["version", :version])

    assert {:error, :conflict} = execute(c, "runtime_defaults", 1, payload)

    assert {:error, :forbidden} =
             execute(
               %{c | scope: %{c.scope | organization_membership: nil}},
               "runtime_defaults",
               2,
               payload
             )

    assert {:ok, published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert published.defaults == c.document.defaults
    assert {:ok, _} = execute(c, "publish", 2, %{})

    assert {:ok, published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert published.defaults == defaults

    assert {:ok, %{document_version: 3}} =
             execute(c, "runtime_defaults", 2, %{"defaults_json" => "{}"})

    assert {:ok, %{defaults: %{}}} = fetch(c)

    versions =
      Documents.list_versions(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )

    assert length(versions) == 3
    assert List.last(versions).created_by == c.user.user_id
    assert List.last(versions).change_summary == "Dashboard editor: runtime_defaults"
  end

  test "invalid runtime defaults fail before writes with a stable non-diagnostic error", c do
    for json <- [
          "{",
          "[]",
          "{\"time\":{\"mode\":\"bad\"}}",
          "{\"scope\":{\"primary\":[]}}",
          "{\"data\":{\"realm\":\"private-source-error\"}}"
        ] do
      assert {:error, :invalid_defaults} =
               execute(c, "runtime_defaults", 1, %{"defaults_json" => json})
    end

    assert {:ok, saved} = fetch(c)
    assert saved == c.document

    assert length(
             Documents.list_versions(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )
           ) == 1
  end

  test "unauthorized, foreign and revoked scopes cannot mutate a document", c do
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | actor_kind: :system},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_id: other_org.organization_id}
        ] do
      assert {:error, :forbidden} =
               execute(%{c | scope: scope}, "rename", 1, %{
                 "name" => "Forbidden",
                 "description" => ""
               })
    end

    assert {:error, :forbidden} =
             Authoring.execute(
               c.scope,
               other_mission.mission_id,
               c.document.dashboard_id,
               "publish",
               %{"expected_version" => 1}
             )

    assert {:error, :unavailable} =
             Authoring.execute(c.scope, c.mission.mission_id, "missing", "publish", %{
               "expected_version" => 1
             })

    assert {:ok, saved} = fetch(c)
    assert saved == c.document
  end

  test "sections preserve collapse defaults, reorder and release their placements on removal",
       c do
    section = %{"title" => "Power", "description" => "Subsystem", "collapsed_by_default" => true}
    assert {:ok, %{section_id: power}} = execute(c, "add_section", 1, section)

    assert {:ok, %{section_id: thermal}} =
             execute(c, "add_section", 2, %{section | "title" => "Thermal"})

    assert {:ok, saved} = fetch(c)
    assert Enum.all?(saved.sections, & &1.collapsed_by_default?)

    assert {:ok, _} =
             execute(c, "move_section", 3, %{"section_id" => thermal, "direction" => "up"})

    assert {:ok, saved} = fetch(c)
    assert Enum.map(saved.sections, & &1.section_id) == [thermal, power]

    updated = section |> Map.put("section_id", power) |> Map.put("collapsed_by_default", false)
    assert {:ok, _} = execute(c, "update_section", 4, updated)
    [placement] = saved.placements
    fields = Map.put(AuthoringWidget.fields(placement), "section_id", power)

    assert {:ok, _} =
             execute(c, "update_widget", 5, %{
               "placement_id" => placement.placement_id,
               "fields" => fields,
               "observables" => AuthoringWidget.observables(placement)
             })

    assert {:ok, saved} = fetch(c)
    assert Enum.find(saved.sections, &(&1.section_id == power)).collapsed_by_default? == false
    assert hd(saved.placements).section_id == power
    assert {:ok, _} = execute(c, "remove_section", 6, %{"section_id" => power})
    assert {:ok, saved} = fetch(c)
    assert Enum.map(saved.sections, & &1.section_id) == [thermal]
    assert hd(saved.placements).section_id == nil
  end

  test "widget edits preserve persisted binding semantics and missing IDs never become adds", c do
    [placement] = c.document.placements
    fields = Map.put(AuthoringWidget.fields(placement), "title", "Battery renamed")

    payload = %{
      "placement_id" => placement.placement_id,
      "fields" => fields,
      "observables" => AuthoringWidget.observables(placement)
    }

    assert {:error, :missing_placement} =
             execute(c, "update_widget", 1, %{payload | "placement_id" => "missing"})

    assert {:error, :missing_section} =
             execute(c, "update_widget", 1, %{
               payload
               | "fields" => Map.put(fields, "section_id", "missing")
             })

    assert {:ok, _} = execute(c, "update_widget", 1, payload)
    assert {:ok, saved} = fetch(c)
    assert [next] = saved.placements
    assert next == %{placement | widget_def: %{placement.widget_def | title: "Battery renamed"}}

    assert {:error, :missing_placement} =
             execute(c, "remove_widget", 2, %{"placement_id" => "missing"})

    assert {:ok, _} = execute(c, "remove_widget", 2, %{"placement_id" => placement.placement_id})
    assert {:ok, %{placements: []}} = fetch(c)
  end

  test "adding a chart persists multiple observables and style settings", c do
    fields =
      Map.merge(AuthoringWidget.defaults(), %{
        "type" => "time_series",
        "title" => "Power",
        "legend_mode" => "hidden",
        "line_width" => "bold"
      })

    observables = ["tlm.hk.battery_voltage", "tlm.hk.battery_current"]

    assert {:ok, %{placement_id: id}} =
             execute(c, "add_widget", 1, %{"fields" => fields, "observables" => observables})

    assert {:ok, saved} = fetch(c)
    chart = Enum.find(saved.placements, &(&1.placement_id == id))
    assert chart.widget_def.binding.observables == observables
    assert chart.widget_def.options["legend_mode"] == "hidden"
    assert chart.widget_def.options["line_width"] == "bold"
  end

  test "layout admits only authored IDs and applies canonical document geometry", c do
    [placement] = c.document.placements

    layout = %{
      "placement_id" => placement.placement_id,
      "x" => 47,
      "y" => 100,
      "w" => 48,
      "h" => 1024
    }

    assert {:error, :missing_placement} =
             execute(c, "layout", 1, %{
               "layouts" => [
                 Map.put(
                   layout,
                   "placement_id",
                   placement.placement_id <> "__repeat__spacecraft__sc-1"
                 )
               ]
             })

    assert {:ok, _} = execute(c, "layout", 1, %{"layouts" => [layout]})
    assert {:ok, saved} = fetch(c)
    expected = Document.apply_layouts(c.document, [layout])
    assert saved.placements == expected.placements
    assert hd(saved.placements).layout.w <= saved.grid.columns
  end

  test "publishing pins the observed draft while later edits leave the viewer unchanged", c do
    assert {:ok, %{document_version: 1}} = execute(c, "publish", 1, %{})
    assert {:ok, _} = execute(c, "rename", 1, %{"name" => "Unpublished", "description" => ""})
    assert {:error, :conflict} = execute(c, "publish", 1, %{})

    assert {:ok, published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert published.name == c.document.name
    assert Document.version(published) == 1
    assert {:ok, %{document_version: 2}} = execute(c, "publish", 2, %{})

    assert {:ok, published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert published.name == "Unpublished"
  end

  test "archived documents reject authoring without creating versions", c do
    assert :ok =
             Documents.archive(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               actor_id: c.user.user_id
             )

    assert {:error, :unavailable} =
             execute(c, "rename", 1, %{"name" => "No", "description" => ""})

    assert length(
             Documents.list_versions(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )
           ) == 1
  end

  test "publish readiness failures are contained without exposing source diagnostics", c do
    source = DataSources.default_managed_data_source()

    defaults =
      Map.put(c.document.defaults, "scope", %{
        "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc_001"]}
      })

    assert {:ok, document} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | defaults: defaults},
               expected_version: 1
             )

    assert {:ok, persisted_source} =
             DataSources.persist_data_source(
               %{
                 source
                 | data_source_id: "authoring-source-" <> Ecto.UUID.generate(),
                   organization_id: c.org.organization_id,
                   mission_id: c.mission.mission_id,
                   isolation_level: :mission_isolated,
                   capabilities: %{latest?: false, range_scan?: false}
               },
               event_bus: __MODULE__.UnusedEventBus
             )

    binding = DataSources.default_flight_telemetry_binding()

    assert {:ok, _} =
             DataSources.persist_data_binding(
               %{
                 binding
                 | binding_id: "authoring-binding-" <> Ecto.UUID.generate(),
                   organization_id: c.org.organization_id,
                   mission_id: c.mission.mission_id,
                   data_source_id: persisted_source.data_source_id
               },
               event_bus: __MODULE__.UnusedEventBus
             )

    # This explicit binding cannot satisfy the widget's latest-value request.
    assert {:error, :invalid_document} = execute(c, "publish", 2, %{})

    assert {:error, :dashboard_not_published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert {:ok, saved} = fetch(c)
    assert saved == document

    assert length(
             Documents.list_versions(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )
           ) == 2
  end

  test "a dashboard from another authorized mission cannot be addressed through this mission",
       c do
    mission = TestFixtures.persist_mission!(c.org)
    assert :ok = Authoring.authorize(c.scope, mission.mission_id)

    assert {:error, :unavailable} =
             Authoring.execute(c.scope, mission.mission_id, c.document.dashboard_id, "rename", %{
               "expected_version" => 1,
               "name" => "Wrong mission",
               "description" => ""
             })

    assert {:ok, saved} = fetch(c)
    assert saved == c.document
  end

  test "invalid fields do not create versions or leak validation internals", c do
    input = %{
      "fields" => Map.put(AuthoringWidget.defaults(), "title", ""),
      "observables" => ["battery"]
    }

    assert {:error, :invalid_title} = execute(c, "add_widget", 1, input)

    assert {:error, :invalid_input} =
             execute(c, "rename", 1, %{
               "name" => "No",
               "description" => "",
               "organization_id" => "foreign"
             })

    assert {:error, :missing_section} =
             execute(c, "remove_section", 1, %{"section_id" => "missing"})

    assert {:ok, saved} = fetch(c)
    assert saved == c.document

    assert length(
             Documents.list_versions(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )
           ) == 1
  end

  defp execute(c, event, version, fields),
    do:
      Authoring.execute(
        c.scope,
        c.mission.mission_id,
        c.document.dashboard_id,
        event,
        Map.put(fields, "expected_version", version)
      )

  defp fetch(c),
    do:
      Documents.fetch_for_mode(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        :edit
      )
end
