defmodule CadenceWeb.DashboardAuthoringDraftTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    Authoring,
    AuthoringDraft,
    AuthoringWidget,
    Document,
    DocumentCodec,
    Documents,
    ResolutionContext
  }

  alias Cadence.Reads.Dashboards.Editor
  alias Cadence.Telemetry.Sample
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

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)
    [placement] = base.placements

    placement = %{
      placement
      | widget_def: %{
          placement.widget_def
          | binding: Map.put(placement.widget_def.binding, :overlays, [])
        }
    }

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "staging-" <> Ecto.UUID.generate(),
        placements: [placement]
    }

    assert {:ok, document} = Documents.persist(org.organization_id, document)
    assert {:ok, draft} = AuthoringDraft.open(scope, mission.mission_id, document.dashboard_id)
    %{org: org, user: user, mission: mission, scope: scope, document: document, draft: draft}
  end

  test "multiple staged changes create one attributed version only on save and never publish",
       c do
    assert {:ok, _} =
             Documents.publish(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               expected_version: 1
             )

    assert {:ok, renamed, %{}} =
             stage(c, c.draft, "rename", %{
               "name" => " Staged power ",
               "description" => " Reviewed "
             })

    assert {:ok, sectioned, %{section_id: section}} =
             stage(c, renamed, "add_section", %{
               "title" => "Power",
               "description" => "",
               "collapsed_by_default" => false
             })

    fields =
      Map.merge(AuthoringWidget.defaults(), %{"title" => "Candidate", "section_id" => section})

    assert {:ok, candidate, %{placement_id: widget}} =
             stage(c, sectioned, "add_widget", %{
               "fields" => fields,
               "observables" => ["tlm.hk.battery_voltage"]
             })

    assert {:ok, arranged, %{}} =
             stage(c, candidate, "layout", %{
               "layouts" => [%{"placement_id" => widget, "x" => 4, "y" => 3, "w" => 4, "h" => 2}]
             })

    assert arranged.revision == 4
    assert Document.version(arranged.document) == 1
    assert AuthoringDraft.dirty?(arranged)
    assert fetch(c) == c.document
    assert length(versions(c)) == 1
    assert {:ok, saved, receipt} = AuthoringDraft.save(c.scope, arranged, control(arranged))

    assert receipt == %{
             version: 1,
             event: "save_draft",
             dashboard_id: c.document.dashboard_id,
             document_version: 2,
             changed: true
           }

    assert saved.revision == 5
    refute AuthoringDraft.dirty?(saved)
    document = fetch(c)
    assert document == saved.document
    assert document.name == "Staged power"
    assert document.description == "Reviewed"
    assert Enum.find(document.placements, &(&1.placement_id == widget)).section_id == section
    assert Enum.find(document.placements, &(&1.placement_id == widget)).layout.x == 4
    assert length(versions(c)) == 2
    version = List.last(versions(c))
    assert version.created_by == c.user.user_id

    assert version.change_summary ==
             "Dashboard editor: staged changes (add_section x1, add_widget x1, layout x1, rename x1)"

    assert {:ok, published} =
             Documents.fetch_published(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id
             )

    assert published.name == c.document.name
    assert Document.version(published) == 1
    assert {:error, :conflict} = AuthoringDraft.save(c.scope, arranged, control(arranged))
    assert length(versions(c)) == 2
  end

  test "discard restores the starting document without writes and invalidates previous revisions",
       c do
    assert {:ok, staged, _} =
             stage(c, c.draft, "remove_widget", %{"placement_id" => "placement_battery_voltage"})

    assert staged.document.placements == []
    assert {:ok, discarded} = AuthoringDraft.discard(c.scope, staged, control(staged))
    assert discarded.document == c.document
    assert discarded.baseline == c.document
    assert discarded.revision == 2
    refute AuthoringDraft.dirty?(discarded)
    assert discarded.changes == %{}
    assert {:error, :conflict} = AuthoringDraft.save(c.scope, discarded, control(staged))

    assert {:ok, clean, %{changed: false, document_version: 1}} =
             AuthoringDraft.save(c.scope, discarded, control(discarded))

    assert clean.revision == 3
    assert fetch(c) == c.document
    assert length(versions(c)) == 1
  end

  test "staged revisions reject duplicate, reordered, malformed and durable commands", c do
    payload = %{"title" => "Once", "description" => "", "collapsed_by_default" => false}
    assert {:ok, staged, _} = stage(c, c.draft, "add_section", payload)

    assert {:error, :conflict} =
             AuthoringDraft.stage(
               c.scope,
               staged,
               "add_section",
               Map.merge(payload, control(c.draft))
             )

    for input <- [
          Map.put(control(staged), "expected_revision", -1),
          Map.put(control(staged), "expected_revision", "1"),
          Map.put(control(staged), "expected_version", nil),
          Map.put(control(staged), "document", %{}),
          %{}
        ] do
      assert {:error, :invalid_input} = AuthoringDraft.save(c.scope, staged, input)
    end

    for event <- ["publish", "save_draft", "delete", "unknown"] do
      assert {:error, :invalid_input} = stage(c, staged, event, %{})
    end

    assert {:error, :invalid_input} =
             stage(c, staged, "rename", %{"name" => "", "description" => ""})

    assert staged.revision == 1
    assert length(staged.document.sections) == 1
    assert fetch(c) == c.document
    assert length(versions(c)) == 1
  end

  test "another saved draft never silently replaces the starting version or staged content", c do
    assert {:ok, other} =
             AuthoringDraft.open(c.scope, c.mission.mission_id, c.document.dashboard_id)

    assert {:ok, mine, _} = stage(c, c.draft, "rename", %{"name" => "Mine", "description" => ""})

    assert {:ok, theirs, _} =
             stage(c, other, "rename", %{"name" => "Theirs", "description" => ""})

    assert {:ok, _, _} = AuthoringDraft.save(c.scope, theirs, control(theirs))
    assert {:error, :conflict} = AuthoringDraft.current(c.scope, mine)
    assert {:error, :conflict} = AuthoringDraft.save(c.scope, mine, control(mine))
    assert {:error, :conflict} = AuthoringDraft.discard(c.scope, mine, control(mine))

    assert {:error, :conflict} =
             stage(c, mine, "remove_widget", %{"placement_id" => "placement_battery_voltage"})

    assert {:error, :conflict} = Editor.staged(c.scope, mine)
    assert mine.document.name == "Mine"
    assert fetch(c).name == "Theirs"
    assert length(versions(c)) == 2

    assert {:ok, reopened} =
             AuthoringDraft.open(c.scope, c.mission.mission_id, c.document.dashboard_id)

    assert reopened.document.name == "Theirs"
    assert Document.version(reopened.baseline) == 2
  end

  test "actor binding, revoked authority and archived resources reject every retained-draft operation",
       c do
    assert {:ok, staged, _} =
             stage(c, c.draft, "rename", %{"name" => "Mine", "description" => ""})

    other_user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(other_user, c.org)

    other_scope =
      Scope.new(%{
        user: other_user,
        organization_id: c.org.organization_id,
        organization_membership: membership
      })

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"},
          other_scope
        ] do
      assert {:error, _} = AuthoringDraft.current(scope, staged)

      assert {:error, _} =
               AuthoringDraft.stage(
                 scope,
                 staged,
                 "rename",
                 Map.merge(control(staged), %{"name" => "Other", "description" => ""})
               )

      assert {:error, _} = AuthoringDraft.save(scope, staged, control(staged))
      assert {:error, _} = AuthoringDraft.discard(scope, staged, control(staged))
      assert {:error, _} = Editor.staged(scope, staged, preview_opts())
    end

    assert fetch(c) == c.document

    refute_received {:preview_point, _}

    assert :ok =
             Documents.archive(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               []
             )

    assert {:error, :unavailable} = AuthoringDraft.current(c.scope, staged)
    assert {:error, :unavailable} = AuthoringDraft.save(c.scope, staged, control(staged))
    assert {:error, :unavailable} = AuthoringDraft.discard(c.scope, staged, control(staged))
    assert length(versions(c)) == 1
  end

  test "staging retains explicit defaults and unedited binding semantics", c do
    defaults = put_in(c.document.defaults, ["time", "axis"], "receipt_time")

    assert {:ok, staged, _} =
             stage(c, c.draft, "runtime_defaults", %{"defaults_json" => Jason.encode!(defaults)})

    [placement] = staged.document.placements
    fields = Map.put(AuthoringWidget.fields(placement), "title", "Reviewed voltage")

    assert {:ok, staged, _} =
             stage(c, staged, "update_widget", %{
               "placement_id" => placement.placement_id,
               "fields" => fields,
               "observables" => AuthoringWidget.observables(placement)
             })

    [updated] = staged.document.placements
    assert updated.widget_def.binding == placement.widget_def.binding
    assert updated.scope_override == placement.scope_override
    assert updated.data_override == placement.data_override
    assert staged.document.defaults == defaults
    assert fetch(c) == c.document
    assert {:ok, saved, _} = AuthoringDraft.save(c.scope, staged, control(staged))
    assert saved.document.defaults == defaults
    assert Document.version(saved.document) == 2
  end

  test "staged preview resolves the actual candidate through production and renders without persisting",
       c do
    fields = Map.put(AuthoringWidget.defaults(), "title", "Unsaved candidate")

    assert {:ok, staged, %{placement_id: id}} =
             stage(c, c.draft, "add_widget", %{
               "fields" => fields,
               "observables" => ["tlm.hk.battery_voltage"]
             })

    assert {:ok, read} = Editor.staged(c.scope, staged, preview_opts())
    assert read.version == 1 and read.revision == 1 and read.dirty
    assert read.model.document_version == 1
    assert Enum.any?(read.model.placements, &(&1.id == id))
    assert read.model.preview.document_version == 1
    candidate = Enum.find(read.model.preview.placements, &(&1.id == id))
    assert candidate.widget.title == "Unsaved candidate"

    assert Enum.any?(candidate.frames, fn frame ->
             Enum.any?(frame.fields, &(&1.values == [28.4]))
           end)

    assert_received {:preview_point, "tlm.hk.battery_voltage"}
    assert fetch(c) == c.document
    assert length(versions(c)) == 1

    page = %{
      id: "dashboards.editor",
      slot: "ops.page",
      version: 1,
      context: %{
        organizationId: c.org.organization_id,
        missionId: c.mission.mission_id,
        resourceId: c.document.dashboard_id
      },
      data: %{
        version: 2,
        sequence: 0,
        phase: "editing",
        revision: read.revision,
        dirty: read.dirty,
        model: read.model
      }
    }

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @renderer, Jason.encode!([page])],
               stderr_to_stdout: true
             )

    assert output =~ "Editor producer/renderer contract passed"
    refute Map.has_key?(read, :baseline)
    refute Map.has_key?(read, :document)
    assert {:ok, failed_preview} = Editor.staged(c.scope, staged, resolution_context: :invalid)
    assert failed_preview.model.preview == nil
    assert failed_preview.model.placements == read.model.placements
    assert failed_preview.dirty
  end

  test "immediate authoring still uses the same transformations and error contract", c do
    assert {:ok, staged, _} =
             stage(c, c.draft, "rename", %{"name" => " Shared ", "description" => " Same "})

    assert {:ok, _} =
             Authoring.execute(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               "rename",
               %{"expected_version" => 1, "name" => " Shared ", "description" => " Same "}
             )

    saved = fetch(c)
    assert Document.version(saved) == 2

    assert Document.to_map(Document.put_version(staged.document, 2)) ==
             Document.to_map(Document.put_version(saved, 2))
  end

  defp preview_opts do
    parent = self()

    context =
      ResolutionContext.new!(
        validate_dashboard_contract?: true,
        source_execution_opts: [
          source_health_events?: false,
          record_source_health_events?: false,
          source_watermark_events?: false,
          source_opts: %{
            telemetry: [
              latest_fun: fn _, mission, point, _ ->
                send(parent, {:preview_point, point})

                %Sample{
                  sample_id: "preview",
                  mission_id: mission,
                  point_id: point,
                  spacecraft_id: "sc_001",
                  point_name: point,
                  raw_value: 284,
                  engineering_value: 28.4,
                  quality_state: :good,
                  generation_time: ~U[2026-09-07 00:00:00Z],
                  receipt_time: ~U[2026-09-07 00:00:01Z]
                }
              end,
              watermark_fun: fn _, _, _, _ -> nil end
            ]
          }
        ]
      )

    [
      resolution_context: context,
      runtime: %{scope_context: %{primary: %{kind: :spacecraft, mode: :one, ids: ["sc_001"]}}}
    ]
  end

  defp control(draft),
    do: %{
      "expected_version" => Document.version(draft.baseline),
      "expected_revision" => draft.revision
    }

  defp stage(c, draft, event, fields),
    do: AuthoringDraft.stage(c.scope, draft, event, Map.merge(fields, control(draft)))

  defp versions(c),
    do:
      Documents.list_versions(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )

  defp fetch(c) do
    assert {:ok, document} =
             Documents.fetch_for_mode(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               :edit
             )

    document
  end
end
