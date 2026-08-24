defmodule CadenceWeb.OpsDashboardShowLive.VersionListComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardSummary, Document, Version}
  alias CadenceWeb.OpsDashboardShowLive.{VersionHistoryPresentation, VersionListComponents}

  test "version_overview renders pointers and version actions" do
    version_history =
      VersionHistoryPresentation.build(
        %DashboardSummary{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          latest_version: 2,
          draft_version: 2,
          published_version: 1
        },
        [
          version(1, :publish, "published save"),
          version(2, :draft_save, "draft save")
        ]
      )

    html =
      render_component(&VersionListComponents.version_overview/1,
        version_history: version_history
      )

    presentation = version_overview_presentation(html)

    assert presentation |> Map.keys() |> Enum.sort() == ~w(pointers root versions)
    assert presentation["root"] == %{"attrs" => %{"class" => "space-y-5"}}
    assert presentation["pointers"]["attrs"] == %{"class" => "grid grid-cols-3 gap-2 text-xs"}

    assert Enum.map(presentation["pointers"]["items"], fn pointer ->
             {
               pointer["key"],
               pointer["order"],
               pointer["attrs"],
               pointer["label"],
               pointer["value"]
             }
           end) == [
             {
               "pointer-0",
               0,
               %{"class" => "border border-base-300/70 bg-base-100/40 px-2 py-1.5"},
               %{"attrs" => %{"class" => "hud-label"}, "text" => "latest"},
               %{"attrs" => %{"class" => "font-mono text-sm"}, "text" => "v2"}
             },
             {
               "pointer-1",
               1,
               %{"class" => "border border-base-300/70 bg-base-100/40 px-2 py-1.5"},
               %{"attrs" => %{"class" => "hud-label"}, "text" => "draft"},
               %{"attrs" => %{"class" => "font-mono text-sm"}, "text" => "v2"}
             },
             {
               "pointer-2",
               2,
               %{"class" => "border border-base-300/70 bg-base-100/40 px-2 py-1.5"},
               %{"attrs" => %{"class" => "hud-label"}, "text" => "published"},
               %{"attrs" => %{"class" => "font-mono text-sm"}, "text" => "v1"}
             }
           ]

    versions = presentation["versions"]

    assert versions["section"] == %{"attrs" => %{"class" => "space-y-2"}}

    assert versions["header"] == %{
             "attrs" => %{"class" => "flex items-center justify-between"},
             "heading" => %{
               "attrs" => %{"class" => "hud-label"},
               "text" => "Versions"
             },
             "count" => %{
               "attrs" => %{"class" => "font-mono text-xs text-base-content/50"},
               "text" => "2"
             }
           }

    assert versions["list"]["attrs"] == %{
             "class" => "space-y-2",
             "id" => "dashboard-version-list"
           }

    [draft, published] = versions["list"]["rows"]

    assert Enum.map(versions["list"]["rows"], fn row ->
             {row["key"], row["attrs"]["id"], row["order"], row["identity"]["version"]["text"]}
           end) == [
             {"dashboard-version-2", "dashboard-version-2", 0, "v2"},
             {"dashboard-version-1", "dashboard-version-1", 1, "v1"}
           ]

    assert Enum.map(published["identity"]["pointers"], & &1["attrs"]["data-version-pointer"]) ==
             ["published"]

    assert draft["attrs"]["data-version-publish-available"] == "true"
    assert draft["attrs"]["data-version-restore-reason"] == "already_latest"
    assert draft["summary"]["text"] == "draft save"
    assert draft["attrs"]["data-version-lineage-kind"] == "draft_save"
    assert draft["attrs"]["data-version-lineage-source-version"] == "1"
    assert detail_value(draft, "origin") == "Draft saved from v1"

    assert draft["attrs"] == %{
             "class" => "border border-base-300/70 bg-base-100/40 p-2",
             "data-version-lineage-kind" => "draft_save",
             "data-version-lineage-source-version" => "1",
             "data-version-publish-available" => "true",
             "data-version-publish-reason" => "available",
             "data-version-restore-available" => "false",
             "data-version-restore-reason" => "already_latest",
             "id" => "dashboard-version-2"
           }

    assert published["attrs"] == %{
             "class" => "border border-base-300/70 bg-base-100/40 p-2",
             "data-version-lineage-kind" => "publish",
             "data-version-publish-available" => "false",
             "data-version-publish-reason" => "already_published",
             "data-version-restore-available" => "true",
             "data-version-restore-reason" => "available",
             "id" => "dashboard-version-1"
           }

    assert draft["identity"] == %{
             "attrs" => %{"class" => "flex flex-wrap items-center gap-1.5"},
             "version" => %{
               "attrs" => %{"class" => "font-mono text-sm font-semibold"},
               "text" => "v2"
             },
             "snapshot" => %{
               "attrs" => %{"class" => "badge badge-xs badge-outline"},
               "text" => "draft save"
             },
             "pointers" => [
               %{
                 "attrs" => %{
                   "class" => "badge badge-xs badge-ghost",
                   "data-version-pointer" => "latest"
                 },
                 "key" => "version-pointer-0",
                 "order" => 0,
                 "text" => "latest"
               },
               %{
                 "attrs" => %{
                   "class" => "badge badge-xs badge-warning",
                   "data-version-pointer" => "draft"
                 },
                 "key" => "version-pointer-1",
                 "order" => 1,
                 "text" => "draft"
               }
             ]
           }

    assert published["identity"] == %{
             "attrs" => %{"class" => "flex flex-wrap items-center gap-1.5"},
             "version" => %{
               "attrs" => %{"class" => "font-mono text-sm font-semibold"},
               "text" => "v1"
             },
             "snapshot" => %{
               "attrs" => %{"class" => "badge badge-xs badge-outline"},
               "text" => "publish"
             },
             "pointers" => [
               %{
                 "attrs" => %{
                   "class" => "badge badge-xs badge-primary",
                   "data-version-pointer" => "published"
                 },
                 "key" => "version-pointer-0",
                 "order" => 0,
                 "text" => "published"
               }
             ]
           }

    assert detail_contract(draft) == [
             {"saved", 0, "Saved", %{"class" => "font-mono text-base-content/70"},
              "2026-06-24 12:00:00 UTC"},
             {"author", 1, "Author",
              %{
                "class" => "truncate text-base-content/70",
                "data-version-field" => "Author"
              }, "operator"},
             {"origin", 2, "Origin",
              %{
                "class" => "font-mono text-base-content/70",
                "data-version-field" => "Origin"
              }, "Draft saved from v1"},
             {"parent", 3, "Parent", %{"class" => "font-mono text-base-content/70"}, "1"},
             {"based-on", 4, "Based on", %{"class" => "font-mono text-base-content/70"}, "1"}
           ]

    assert detail_contract(published) == [
             {"saved", 0, "Saved", %{"class" => "font-mono text-base-content/70"},
              "2026-06-24 12:00:00 UTC"},
             {"author", 1, "Author",
              %{
                "class" => "truncate text-base-content/70",
                "data-version-field" => "Author"
              }, "operator"},
             {"origin", 2, "Origin",
              %{
                "class" => "font-mono text-base-content/70",
                "data-version-field" => "Origin"
              }, "Published for operators"},
             {"parent", 3, "Parent", %{"class" => "font-mono text-base-content/70"}, "-"},
             {"based-on", 4, "Based on", %{"class" => "font-mono text-base-content/70"}, "-"}
           ]

    assert draft["details"]["attrs"] == %{
             "class" => "mt-2 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-xs"
           }

    assert draft["summary"] == %{
             "attrs" => %{
               "class" => "mt-2 text-xs text-base-content/70",
               "data-version-field" => "Summary"
             },
             "text" => "draft save",
             "visible" => true
           }

    assert published["summary"] == %{
             "attrs" => %{
               "class" => "mt-2 text-xs text-base-content/70",
               "data-version-field" => "Summary"
             },
             "text" => "published save",
             "visible" => true
           }

    assert draft["layout"] == %{
             "attrs" => %{"class" => "flex items-start justify-between gap-3"}
           }

    assert draft["content"] == %{"attrs" => %{"class" => "min-w-0"}}

    assert draft["actions"]["attrs"] == %{
             "class" => "flex shrink-0 flex-col gap-1"
           }

    assert action(draft, "publish") == %{
             "attrs" => %{
               "class" => "btn btn-ghost btn-xs",
               "data-confirm" => "Publish version 2 for operators?",
               "data-version-action" => "publish",
               "data-version-action-available" => "true",
               "data-version-action-reason" => "available",
               "id" => "publish-version-2",
               "phx-click" => "publish_dashboard_version",
               "phx-value-version" => "2",
               "type" => "button"
             },
             "icon" => %{
               "attrs" => %{"class" => "hero-arrow-up-tray h-3.5 w-3.5"}
             },
             "key" => "publish",
             "text" => "Publish"
           }

    assert action(draft, "restore") == %{
             "attrs" => %{
               "class" => "btn btn-ghost btn-xs",
               "data-confirm" => "Restore version 2 as the latest draft?",
               "data-version-action" => "restore",
               "data-version-action-available" => "false",
               "data-version-action-reason" => "already_latest",
               "disabled" => "",
               "id" => "restore-version-2",
               "phx-click" => "restore_version_as_draft",
               "phx-value-version" => "2",
               "type" => "button"
             },
             "icon" => %{
               "attrs" => %{"class" => "hero-arrow-uturn-left h-3.5 w-3.5"}
             },
             "key" => "restore",
             "text" => "Restore"
           }

    assert action(published, "publish") == %{
             "attrs" => %{
               "class" => "btn btn-ghost btn-xs",
               "data-confirm" => "Publish version 1 for operators?",
               "data-version-action" => "publish",
               "data-version-action-available" => "false",
               "data-version-action-reason" => "already_published",
               "disabled" => "",
               "id" => "publish-version-1",
               "phx-click" => "publish_dashboard_version",
               "phx-value-version" => "1",
               "type" => "button"
             },
             "icon" => %{
               "attrs" => %{"class" => "hero-arrow-up-tray h-3.5 w-3.5"}
             },
             "key" => "publish",
             "text" => "Publish"
           }

    assert action(published, "restore") == %{
             "attrs" => %{
               "class" => "btn btn-ghost btn-xs",
               "data-confirm" => "Restore version 1 as the latest draft?",
               "data-version-action" => "restore",
               "data-version-action-available" => "true",
               "data-version-action-reason" => "available",
               "id" => "restore-version-1",
               "phx-click" => "restore_version_as_draft",
               "phx-value-version" => "1",
               "type" => "button"
             },
             "icon" => %{
               "attrs" => %{"class" => "hero-arrow-uturn-left h-3.5 w-3.5"}
             },
             "key" => "restore",
             "text" => "Restore"
           }
  end

  test "version_overview renders empty state" do
    version_history = VersionHistoryPresentation.build(nil, [])

    html =
      render_component(&VersionListComponents.version_overview/1,
        version_history: version_history
      )

    presentation = version_overview_presentation(html)

    assert presentation["versions"]["list"]["rows"] == []

    assert presentation["versions"]["empty"] == %{
             "attrs" => %{"class" => "text-sm text-base-content/60"},
             "text" => "No saved versions.",
             "visible" => true
           }

    assert presentation["versions"]["header"]["count"]["text"] == "0"
  end

  test "version_overview preserves HEEx attribute, body, and truthiness semantics" do
    values = [nil, false, true, "", 7]

    version_history = %{
      pointers:
        values
        |> Enum.with_index()
        |> Enum.map(fn {value, index} -> %{label: value, value: Enum.at(values, 4 - index)} end),
      count: false,
      empty: "",
      versions:
        values
        |> Enum.with_index()
        |> Enum.map(fn {value, index} -> semantic_version(index, value) end)
    }

    html =
      render_component(&VersionListComponents.version_overview/1,
        version_history: version_history
      )

    presentation = version_overview_presentation(html)
    rows = presentation["versions"]["list"]["rows"]

    assert Enum.map(presentation["pointers"]["items"], & &1["label"]["text"]) ==
             ["", "false", "true", "", "7"]

    assert Enum.map(presentation["pointers"]["items"], & &1["value"]["text"]) ==
             ["7", "", "true", "false", ""]

    assert Enum.map(rows, & &1["identity"]["version"]["text"]) ==
             ["v", "vfalse", "vtrue", "v", "v7"]

    assert Enum.map(rows, & &1["summary"]["text"]) == ["", "false", "true", "", "7"]
    assert Enum.map(rows, & &1["summary"]["visible"]) == [false, false, true, true, true]

    assert Enum.map(rows, fn row ->
             Map.fetch(row["attrs"], "data-version-lineage-source-version")
           end) == [:error, :error, {:ok, ""}, {:ok, ""}, {:ok, "7"}]

    assert Enum.map(rows, fn row ->
             row
             |> Map.fetch!("identity")
             |> Map.fetch!("pointers")
             |> List.first()
             |> Map.fetch!("attrs")
             |> Map.fetch("data-version-pointer")
           end) == [:error, :error, {:ok, ""}, {:ok, ""}, {:ok, "7"}]

    assert Enum.map(rows, fn row ->
             row
             |> action("publish")
             |> Map.fetch!("attrs")
             |> Map.fetch("phx-value-version")
           end) == [:error, :error, {:ok, ""}, {:ok, ""}, {:ok, "7"}]

    assert Enum.map(rows, fn row ->
             row
             |> action("publish")
             |> Map.fetch!("attrs")
             |> Map.take([
               "data-confirm",
               "data-version-action-available",
               "data-version-action-reason",
               "disabled"
             ])
           end) == [
             %{"disabled" => ""},
             %{"disabled" => ""},
             %{
               "data-confirm" => "",
               "data-version-action-available" => "",
               "data-version-action-reason" => "",
               "disabled" => ""
             },
             %{
               "data-confirm" => "",
               "data-version-action-available" => "",
               "data-version-action-reason" => "",
               "disabled" => ""
             },
             %{
               "data-confirm" => "7",
               "data-version-action-available" => "7",
               "data-version-action-reason" => "7",
               "disabled" => ""
             }
           ]

    assert Enum.map(rows, fn row ->
             Enum.map(row["details"]["rows"], & &1["value"]["text"])
           end) == [
             ["", "", "", "", ""],
             ["false", "false", "false", "false", "false"],
             ["true", "true", "true", "true", "true"],
             ["", "", "", "", ""],
             ["7", "7", "7", "7", "7"]
           ]

    assert presentation["versions"]["header"]["count"]["text"] == "false"
    assert presentation["versions"]["empty"]["visible"]

    for {empty, expected} <- [{nil, false}, {false, false}, {true, true}, {"", true}, {7, true}] do
      html =
        render_component(&VersionListComponents.version_overview/1,
          version_history: %{pointers: [], count: 0, empty: empty, versions: []}
        )

      presentation = version_overview_presentation(html)

      assert presentation["versions"]["empty"]["visible"] == expected
    end
  end

  defp version(version, snapshot_kind, change_summary) do
    %Version{
      dashboard_version_id: "version-#{version}",
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      version: version,
      document: dashboard_document(),
      snapshot_kind: snapshot_kind,
      parent_version: previous_version(version),
      based_on_version: previous_version(version),
      change_summary: change_summary,
      created_by: "operator",
      inserted_at: ~U[2026-06-24 12:00:00Z]
    }
  end

  defp semantic_version(index, value) do
    %{
      dom_id: "semantic-version-#{index}",
      version: value,
      publish_button_id: "semantic-publish-#{index}",
      restore_button_id: "semantic-restore-#{index}",
      publish_confirm: value,
      restore_confirm: value,
      snapshot_label: value,
      pointer_labels: [%{label: value, badge_class: "badge-ghost"}],
      lineage: %{kind: value, label: value, source_version_text: value},
      saved_at: value,
      created_by: value,
      parent_version: value,
      based_on_version: value,
      change_summary: value,
      publish_action: %{available: false, available_text: value, reason_text: value},
      restore_action: %{available: true, available_text: value, reason_text: value}
    }
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp previous_version(version) when is_integer(version) and version > 1, do: version - 1
  defp previous_version(_version), do: nil

  defp version_overview_presentation(html) do
    vue = LiveVue.Test.get_vue(html, id: "dashboard-version-overview-component")

    assert vue.id == "dashboard-version-overview-component"
    assert vue.component == "VersionList"
    refute vue.ssr
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

  defp detail_value(version, key) do
    version["details"]["rows"]
    |> Enum.find(&(&1["key"] == key))
    |> get_in(["value", "text"])
  end

  defp detail_contract(version) do
    Enum.map(version["details"]["rows"], fn detail ->
      {
        detail["key"],
        detail["order"],
        detail["label"]["text"],
        detail["value"]["attrs"],
        detail["value"]["text"]
      }
    end)
  end

  defp action(version, key) do
    Enum.find(version["actions"]["buttons"], &(&1["key"] == key))
  end
end
