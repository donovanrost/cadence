defmodule CadenceWeb.OpsDashboardSettingsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{Document, Management}
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  test "exposes the exact JSON-safe settings, form, URL, handler, and initial stream contracts" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Power Settings",
        description: "Mission power posture",
        metadata: %{"tags" => ["power", "flight"]}
      )

    assert {:ok, share} =
             Management.create_share(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{},
               created_by: user.user_id,
               data_visibility: "definition_only"
             )

    assert {:ok, snapshot} =
             Management.create_snapshot(
               org.organization_id,
               mission.mission_id,
               dashboard,
               %{},
               created_by: user.user_id,
               data_visibility: "authorized_runtime_data"
             )

    assert {:ok, deployment} =
             Management.record_deployment(
               org.organization_id,
               mission.mission_id,
               dashboard,
               "portable dashboard artifact",
               "portable_json",
               created_by: user.user_id
             )

    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))

    assert has_element?(view, "#ops-context-rail")
    assert has_element?(view, "#ops-dashboard-settings-component.contents")
    refute has_element?(view, "#dashboard-settings-page")
    refute has_element?(view, "#dashboard-settings-form")

    vue = settings_vue(view)

    assert vue.component == "OpsDashboardSettings"
    assert vue.class == "contents"
    assert vue.ssr == false

    assert vue.handlers == %{
             "archive-dashboard" => JS.push("archive_dashboard"),
             "create-share" => JS.push("create_share"),
             "create-snapshot" => JS.push("create_snapshot"),
             "revoke-share" => JS.push("revoke_share"),
             "save-settings" => JS.push("save_settings"),
             "validate-settings" => JS.push("validate_settings")
           }

    assert vue.props == %{
             "page" => expected_page(mission, dashboard),
             "settings_form" => expected_settings_form(dashboard),
             "share_form" => expected_share_form(),
             "snapshot_form" => expected_snapshot_form()
           }

    share_row = expected_share_row(mission, share)
    snapshot_row = expected_snapshot_row(mission, snapshot)
    deployment_row = expected_deployment_row(deployment)

    assert stream_mutations(vue, "dashboard_shares") == [
             ["replace", "/dashboard_shares", []],
             ["upsert", "/dashboard_shares/-", share_row]
           ]

    assert stream_mutations(vue, "dashboard_snapshots") == [
             ["replace", "/dashboard_snapshots", []],
             ["upsert", "/dashboard_snapshots/-", snapshot_row]
           ]

    assert stream_mutations(vue, "dashboard_deployments") == [
             ["replace", "/dashboard_deployments", []],
             ["upsert", "/dashboard_deployments/-", deployment_row]
           ]

    assert_json_safe(vue)

    render_hook(view, "validate_settings", %{
      "settings" => %{
        "name" => "Power Settings Validated",
        "description" => "Validated description",
        "tags" => "flight, power",
        "defaults_json" => ~s({"time":{"mode":"archive"}})
      }
    })

    fields = settings_vue(view).props["settings_form"]["fields"]
    assert fields["name"]["value"] == "Power Settings Validated"
    assert fields["description"]["value"] == "Validated description"
    assert fields["tags"]["value"] == "flight, power"
    assert fields["defaults_json"]["value"] == ~s({"time":{"mode":"archive"}})
  end

  test "saves dashboard identity, tags, and runtime defaults as one settings version" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))

    render_hook(view, "save_settings", %{
      "settings" => %{
        "name" => "Power Flight",
        "description" => "Flight power posture",
        "tags" => "flight, power, flight",
        "defaults_json" => Jason.encode!(%{"time" => %{"mode" => "live"}})
      }
    })

    assert {:ok, %Document{} = persisted} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert persisted.name == "Power Flight"
    assert persisted.description == "Flight power posture"
    assert persisted.metadata["tags"] == ["flight", "power"]
    assert persisted.defaults == %{"time" => %{"mode" => "live"}}
    assert Document.version(persisted) == 2
  end

  test "emits exact management payloads and refreshes share and snapshot stream posture" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Managed Settings")

    {:ok, view, _html} =
      live(
        conn,
        settings_path(mission, dashboard) <>
          "?scope_kind=spacecraft&scope_id=sc-1&time_mode=archive&from=2026-08-01T00%3A00%3A00Z&to=2026-08-01T01%3A00%3A00Z&ignored_secret=never"
      )

    render_hook(view, "create_share", %{
      "share" => %{"data_visibility" => "definition_only", "expires_in_hours" => "4"}
    })

    assert [share] =
             Management.list_shares(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert share.created_by == user.user_id
    assert share.access_policy == "mission_member"
    assert share.data_visibility == "definition_only"
    assert share.runtime_context["scope_id"] == "sc-1"
    refute Map.has_key?(share.runtime_context, "ignored_secret")

    assert stream_upserts(settings_vue(view), "dashboard_shares") == [
             expected_share_row(mission, share)
           ]

    render_hook(view, "revoke_share", %{"share-id" => share.dashboard_share_id})

    assert [revoked_share] =
             Management.list_shares(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert revoked_share.dashboard_share_id == share.dashboard_share_id
    assert %DateTime{} = revoked_share.revoked_at

    revoked_row = expected_share_row(mission, revoked_share)
    assert revoked_row["status"] == "revoked"
    assert revoked_row["revoke"] == nil
    assert stream_upserts(settings_vue(view), "dashboard_shares") == [revoked_row]

    render_hook(view, "create_snapshot", %{
      "snapshot" => %{"data_visibility" => "authorized_runtime_data"}
    })

    assert [snapshot] =
             Management.list_snapshots(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert snapshot.dashboard_version == 1
    assert snapshot.data_semantics == "frozen_time_window"
    assert snapshot.data_visibility == "authorized_runtime_data"

    assert stream_upserts(settings_vue(view), "dashboard_snapshots") == [
             expected_snapshot_row(mission, snapshot)
           ]
  end

  test "archives from Settings with an explicit lifecycle outcome" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Archive Me")

    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))
    render_hook(view, "archive_dashboard", %{})

    assert_redirect(view, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert Cadence.Dashboards.list_dashboard_summaries(org.organization_id, mission.mission_id) ==
             []

    assert [%{dashboard_id: archived_id}] =
             Cadence.Dashboards.list_archived_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert archived_id == dashboard.dashboard_id
  end

  test "preserves the unavailable dashboard flash and directory redirect" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboards_path = ~p"/missions/#{mission.mission_id}/ops/dashboards"

    assert {:error,
            {:live_redirect,
             %{
               to: ^dashboards_path,
               flash: %{"error" => "Dashboard settings are unavailable: :dashboard_not_found"}
             }}} = live(conn, "/missions/#{mission.mission_id}/ops/dashboards/missing/settings")
  end

  defp settings_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/settings"
  end

  defp settings_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-dashboard-settings-component")
  end

  defp expected_page(mission, dashboard) do
    dashboard_path = "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    %{
      "id" => "dashboard-settings-page",
      "header" => %{
        "eyebrow" => "Dashboard / Settings",
        "heading" => dashboard.name,
        "copy" =>
          "Durable identity, runtime defaults, discovery metadata, and lifecycle posture.",
        "viewer" => %{
          "id" => "dashboard-settings-viewer",
          "label" => "Back to Viewer",
          "href" => dashboard_path
        }
      },
      "sharing" => %{
        "id" => "dashboard-sharing",
        "eyebrow" => "Permission-aware sharing",
        "heading" => "Share this runtime context",
        "copy" =>
          "Links require an authenticated member of this mission. Runtime selectors are captured; credentials and runtime samples are never embedded.",
        "list" => %{
          "id" => "dashboard-share-list",
          "empty" => %{
            "id" => "dashboard-share-empty",
            "copy" => "No active or revoked links yet."
          }
        }
      },
      "snapshots" => %{
        "id" => "dashboard-snapshots",
        "eyebrow" => "Read-only snapshots",
        "heading" => "Freeze definition and context",
        "list" => %{
          "id" => "dashboard-snapshot-list",
          "empty" => %{"id" => "dashboard-snapshot-empty", "copy" => "No snapshots yet."}
        }
      },
      "portability" => %{
        "eyebrow" => "Governed portability",
        "copy" =>
          "Export includes an integrity digest over binding semantics and records the artifact. Import replaces source identity with the target mission.",
        "export" => %{
          "id" => "dashboard-settings-export",
          "label" => "Export JSON",
          "icon" => "hero-arrow-up-tray",
          "href" => dashboard_path <> "/export"
        },
        "deployments" => %{
          "id" => "dashboard-deployment-list",
          "empty" => %{
            "id" => "dashboard-deployment-empty",
            "copy" => "No exports recorded."
          }
        }
      },
      "access" => %{
        "eyebrow" => "Access posture",
        "heading" => "Mission shared",
        "copy" =>
          "Mission operators can view this dashboard. Dashboard authors can change its shared document."
      },
      "lifecycle" => %{
        "eyebrow" => "Lifecycle",
        "copy" =>
          "Archiving removes this dashboard from normal discovery without deleting its version history.",
        "archive" => %{
          "id" => "dashboard-settings-archive",
          "label" => "Archive Dashboard",
          "icon" => "hero-archive-box",
          "confirm" => "Archive this dashboard for every operator on the mission?"
        }
      }
    }
  end

  defp expected_settings_form(dashboard) do
    %{
      "id" => "dashboard-settings-form",
      "fields" => %{
        "name" => %{
          "id" => "settings_name",
          "name" => "settings[name]",
          "type" => "text",
          "label" => "Name",
          "value" => dashboard.name,
          "required" => true
        },
        "description" => %{
          "id" => "settings_description",
          "name" => "settings[description]",
          "type" => "textarea",
          "label" => "Description",
          "value" => dashboard.description || "",
          "required" => false
        },
        "tags" => %{
          "id" => "settings_tags",
          "name" => "settings[tags]",
          "type" => "text",
          "label" => "Tags",
          "value" => dashboard.metadata["tags"] |> List.wrap() |> Enum.join(", "),
          "required" => false,
          "placeholder" => "power, flight, anomaly-response"
        },
        "defaults_json" => %{
          "id" => "settings_defaults_json",
          "name" => "settings[defaults_json]",
          "type" => "textarea",
          "label" => "Runtime defaults (JSON)",
          "value" => Jason.encode!(dashboard.defaults || %{}, pretty: true),
          "required" => false
        }
      },
      "submit" => %{"id" => "dashboard-settings-save", "label" => "Save Settings"}
    }
  end

  defp expected_share_form do
    %{
      "id" => "dashboard-share-form",
      "fields" => %{
        "data_visibility" => %{
          "id" => "share_data_visibility",
          "name" => "share[data_visibility]",
          "type" => "select",
          "label" => "Data visibility",
          "value" => "authorized_runtime_data",
          "required" => false,
          "options" => expected_visibility_options()
        },
        "expires_in_hours" => %{
          "id" => "share_expires_in_hours",
          "name" => "share[expires_in_hours]",
          "type" => "number",
          "label" => "Expires in hours",
          "value" => "24",
          "required" => false,
          "min" => 1,
          "placeholder" => "Never"
        }
      },
      "submit" => %{
        "id" => "dashboard-share-create",
        "label" => "Create authenticated link"
      }
    }
  end

  defp expected_snapshot_form do
    %{
      "id" => "dashboard-snapshot-form",
      "fields" => %{
        "data_visibility" => %{
          "id" => "snapshot_data_visibility",
          "name" => "snapshot[data_visibility]",
          "type" => "select",
          "label" => "Data visibility",
          "value" => "authorized_runtime_data",
          "required" => false,
          "options" => expected_visibility_options()
        }
      },
      "submit" => %{"id" => "dashboard-snapshot-create", "label" => "Create snapshot"}
    }
  end

  defp expected_visibility_options do
    [
      %{"label" => "Authorized runtime data", "value" => "authorized_runtime_data"},
      %{"label" => "Definition only", "value" => "definition_only"}
    ]
  end

  defp expected_share_row(mission, share) do
    share_id = share.dashboard_share_id
    revoked? = not is_nil(share.revoked_at)

    %{
      "__dom_id" => "dashboard-share-#{share_id}",
      "dashboard_share_id" => share_id,
      "access_policy" => share.access_policy,
      "data_visibility" => share.data_visibility,
      "status" => if(revoked?, do: "revoked", else: "active"),
      "open" => %{
        "id" => "dashboard-share-open-#{share_id}",
        "href" => "/missions/#{mission.mission_id}/ops/dashboard-shares/#{share_id}"
      },
      "revoke" =>
        if(revoked?,
          do: nil,
          else: %{
            "id" => "dashboard-share-revoke-#{share_id}",
            "payload" => %{"share-id" => share_id}
          }
        )
    }
  end

  defp expected_snapshot_row(mission, snapshot) do
    snapshot_id = snapshot.dashboard_snapshot_id

    %{
      "__dom_id" => "dashboard-snapshot-#{snapshot_id}",
      "dashboard_snapshot_id" => snapshot_id,
      "dashboard_version" => snapshot.dashboard_version,
      "data_semantics" => snapshot.data_semantics,
      "data_visibility" => snapshot.data_visibility,
      "open" => %{
        "id" => "dashboard-snapshot-open-#{snapshot_id}",
        "href" => "/missions/#{mission.mission_id}/ops/dashboard-snapshots/#{snapshot_id}"
      }
    }
  end

  defp expected_deployment_row(deployment) do
    %{
      "__dom_id" => "dashboard-deployment-#{deployment.dashboard_deployment_id}",
      "dashboard_deployment_id" => deployment.dashboard_deployment_id,
      "environment" => deployment.environment,
      "dashboard_version" => deployment.dashboard_version,
      "artifact_digest_prefix" => String.slice(deployment.artifact_digest, 0, 10)
    }
  end

  defp stream_mutations(vue, stream_name) do
    stream_path = "/#{stream_name}"

    Enum.filter(vue.streams_diff, fn
      ["replace", ^stream_path, _items] -> true
      ["upsert", path, _item] -> String.starts_with?(path, stream_path <> "/")
      ["remove", path] -> String.starts_with?(path, stream_path <> "/")
      _operation -> false
    end)
  end

  defp stream_upserts(vue, stream_name) do
    vue
    |> stream_mutations(stream_name)
    |> Enum.flat_map(fn
      ["upsert", _path, item] -> [item]
      _operation -> []
    end)
  end

  defp assert_json_safe(vue) do
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.streams_diff == Jason.decode!(Jason.encode!(vue.streams_diff))
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-settings")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
