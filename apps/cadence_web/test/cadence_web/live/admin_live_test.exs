defmodule CadenceWeb.AdminLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Accounts.{Authentication, Password, User, UserLocalCredentialRow, UserRow}
  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  setup %{conn: conn} do
    issued_session = issue_platform_admin_session!()
    flush_mailbox()

    on_exit(fn ->
      flush_mailbox()
    end)

    admin_conn =
      init_test_session(conn, %{
        user_session_token: issued_session.session_token,
        admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
      })

    {:ok, admin_conn: admin_conn}
  end

  describe "authorization" do
    test "non-admin user is redirected to /" do
      durable_password = "durable-password-123"

      persist_durable_user!(
        email: "regular@example.com",
        password: durable_password,
        capabilities: []
      )

      {:ok, session} = Cadence.Auth.sign_in("regular@example.com", durable_password)
      conn = build_conn() |> init_test_session(%{user_session_token: session.session_token})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/runtime")
    end

    test "admin-eligible durable user without admin mode is redirected to reauthenticate" do
      password = "durable-admin-password-123"

      persist_durable_user!(
        email: "eligible-admin@example.com",
        password: password,
        capabilities: [:platform_admin]
      )

      {:ok, session} = Cadence.Auth.sign_in("eligible-admin@example.com", password)
      conn = build_conn() |> init_test_session(%{user_session_token: session.session_token})

      assert {:error, {:redirect, %{to: "/admin-mode"}}} = live(conn, ~p"/admin")
    end

    test "platform admin can access the dashboard", %{admin_conn: admin_conn} do
      organization_count = Cadence.Organizations.count_organizations()
      user_count = Cadence.Accounts.count_users()

      {:ok, view, _html} = live(admin_conn, ~p"/admin")

      assert has_element?(view, "#admin-home-page")
      assert has_element?(view, "#admin-home-component")

      vue = LiveVue.Test.get_vue(view, id: "admin-home-component")

      assert vue.component == "AdminHome"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "organization_count" => organization_count,
               "user_count" => user_count,
               "presentation" => %{
                 "title" => "Platform Administration",
                 "subtitle" => "Manage organizations, users, and system settings",
                 "organizations" => %{
                   "title" => "Organizations",
                   "action_label" => "Manage Organizations"
                 },
                 "users" => %{
                   "title" => "Users",
                   "action_label" => "Manage Users",
                   "coming_soon" => "(Coming Soon)"
                 },
                 "runtime" => %{
                   "title" => "Runtime",
                   "description" =>
                     "Inspect process-local runtime diagnostics and dashboard invalidation decisions.",
                   "action_label" => "View Runtime"
                 },
                 "quick_actions" => %{
                   "title" => "Quick Actions",
                   "create_organization_title" => "Create New Organization",
                   "create_organization_description" => "Add a new organization to the system"
                 }
               },
               "navigation" => %{
                 "organizations_href" => "/admin/organizations",
                 "runtime_href" => "/admin/runtime",
                 "create_organization_href" => "/admin/organizations/new"
               }
             }
    end
  end

  describe "organization management" do
    test "admin dashboard shows organization and user counts", %{admin_conn: admin_conn} do
      create_test_org!("Cadence Ops", "cadence-ops")
      persist_durable_user!(email: "dashboard-user@example.com", password: "password-123456")
      organization_count = Cadence.Organizations.count_organizations()
      user_count = Cadence.Accounts.count_users()

      {:ok, view, _html} = live(admin_conn, ~p"/admin")

      vue = LiveVue.Test.get_vue(view, id: "admin-home-component")

      assert vue.component == "AdminHome"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "organization_count" => organization_count,
               "user_count" => user_count,
               "presentation" => %{
                 "title" => "Platform Administration",
                 "subtitle" => "Manage organizations, users, and system settings",
                 "organizations" => %{
                   "title" => "Organizations",
                   "action_label" => "Manage Organizations"
                 },
                 "users" => %{
                   "title" => "Users",
                   "action_label" => "Manage Users",
                   "coming_soon" => "(Coming Soon)"
                 },
                 "runtime" => %{
                   "title" => "Runtime",
                   "description" =>
                     "Inspect process-local runtime diagnostics and dashboard invalidation decisions.",
                   "action_label" => "View Runtime"
                 },
                 "quick_actions" => %{
                   "title" => "Quick Actions",
                   "create_organization_title" => "Create New Organization",
                   "create_organization_description" => "Add a new organization to the system"
                 }
               },
               "navigation" => %{
                 "organizations_href" => "/admin/organizations",
                 "runtime_href" => "/admin/runtime",
                 "create_organization_href" => "/admin/organizations/new"
               }
             }
    end

    test "organization list shows empty state when no orgs exist", %{admin_conn: admin_conn} do
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations")

      assert has_element?(view, "#admin-organization-list-page-component")
      refute has_element?(view, "#admin-organization-list-component")

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-list-page-component")

      assert vue.component == "AdminOrganizationListPage"
      assert vue.ssr == false
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))
      assert vue.props["presentation"]["root"]["attrs"]["id"] == "admin-organizations-page"

      assert vue.props["presentation"]["empty_state"]["title"]["text"] ==
               "No organizations yet"

      assert vue.props["presentation"]["card"] == nil

      refute Jason.encode!(vue.props["presentation"]) =~ "admin-organization-list-component"
    end

    test "admin can create an organization", %{admin_conn: admin_conn} do
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations/new")

      assert has_element?(view, "#admin-organization-new-component")

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-new-component")

      assert vue.component == "AdminOrganizationNew"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "form" => %{"display_name" => "", "slug" => ""},
               "page" => %{
                 "title" => "Create Organization",
                 "breadcrumbs" => [
                   %{"label" => "Platform Admin", "href" => "/admin"},
                   %{"label" => "Organizations", "href" => "/admin/organizations"},
                   %{"label" => "Create Organization", "href" => nil}
                 ],
                 "submit_label" => "Create organization",
                 "cancel_label" => "Cancel",
                 "cancel_href" => "/admin/organizations"
               }
             }

      assert vue.handlers == %{
               "save" => JS.push("save"),
               "validate" => JS.push("validate")
             }

      render_hook(view, "save", %{
        "organization" => %{"display_name" => "  Test Org  ", "slug" => "  test-org  "}
      })

      {redirect_path, flash} = assert_redirect(view)
      assert redirect_path == ~p"/admin/organizations"
      assert flash["info"] == "Organization created successfully."

      # Verify the org appears in the list
      {:ok, list_view, _html} = live(admin_conn, ~p"/admin/organizations")

      assert has_element?(list_view, "#admin-organization-list-page-component")

      vue = LiveVue.Test.get_vue(list_view, id: "admin-organization-list-page-component")
      assert [organization] = Cadence.Organizations.list_organizations()

      assert vue.component == "AdminOrganizationListPage"
      assert vue.ssr == false

      assert vue.props["presentation"]["card"]["child"]["attrs"]["id"] ==
               "admin-organization-list-component"

      assert vue.props["presentation"]["card"]["rows"] == [
               %{
                 "id" => "admin-organization-#{organization.organization_id}",
                 "display_name" => "Test Org",
                 "slug" => "test-org",
                 "href" => "/admin/organizations/#{organization.organization_id}"
               }
             ]
    end

    test "organization validation preserves the Vue-owned form values", %{
      admin_conn: admin_conn
    } do
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations/new")

      render_hook(view, "validate", %{
        "organization" => %{"display_name" => "Mission Support", "slug" => "mission-support"}
      })

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-new-component")

      assert vue.props["form"] == %{
               "display_name" => "Mission Support",
               "slug" => "mission-support"
             }

      assert is_binary(Jason.encode!(vue.props))
    end

    test "organization creation rejects required whitespace and preserves submitted values", %{
      admin_conn: admin_conn
    } do
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations/new")

      render_hook(view, "save", %{
        "organization" => %{"display_name" => "   ", "slug" => "\t"}
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Display name and slug are required."
             )

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-new-component")
      assert vue.props["form"] == %{"display_name" => "   ", "slug" => "\t"}
      assert Cadence.Organizations.list_organizations() == []
    end

    test "organization creation formats persistence changeset errors", %{
      admin_conn: admin_conn
    } do
      existing = create_test_org!("Existing Org", "existing-org")
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations/new")

      render_hook(view, "save", %{
        "organization" => %{"display_name" => "Another Org", "slug" => existing.slug}
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Slug has already been taken"
             )

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-new-component")

      assert vue.props["form"] == %{
               "display_name" => "Another Org",
               "slug" => "existing-org"
             }

      assert Cadence.Organizations.list_organizations() == [existing]
    end

    test "admin can view organization detail with no members", %{admin_conn: admin_conn} do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations/#{org.organization_id}")

      assert has_element?(view, "#admin-organization-show-page")
      assert has_element?(view, "#admin-organization-show-component")

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-show-component")

      assert vue.component == "AdminOrganizationShow"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "invitations" => [],
               "issued_service_token" => nil,
               "members" => [],
               "navigation" => %{
                 "invite_href" => "/admin/organizations/#{org.organization_id}/invite",
                 "open_organization_action" => "/session/organization",
                 "organizations_href" => "/admin/organizations",
                 "platform_admin_href" => "/admin"
               },
               "organization" => %{
                 "display_name" => "Cadence Ops",
                 "organization_id" => org.organization_id,
                 "slug" => "cadence-ops"
               },
               "service_identities" => [],
               "service_identity_form" => %{
                 "display_name" => "",
                 "service_identity_id" => ""
               }
             }

      assert vue.handlers == %{
               "dismiss-service-token" => JS.push("dismiss-service-token"),
               "issue-service-identity" => JS.push("issue-service-identity")
             }
    end

    test "admin can issue the first product API service credential", %{admin_conn: admin_conn} do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      {:ok, view, _html} = live(admin_conn, ~p"/admin/organizations/#{org.organization_id}")

      render_click(view, "issue-service-identity", %{
        "service_identity" => %{
          "display_name" => "Operations Automation",
          "service_identity_id" => "svc-operations"
        }
      })

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-show-component")

      assert %{
               "api_token" => api_token,
               "display_name" => "Operations Automation",
               "service_identity_id" => "svc-operations"
             } = vue.props["issued_service_token"]

      assert is_binary(api_token)

      assert {:ok, identity} =
               Cadence.Auth.fetch_service_identity(org.organization_id, "svc-operations")

      assert [identity_prop] = vue.props["service_identities"]

      assert identity_prop == %{
               "display_name" => "Operations Automation",
               "id" => "service-identity-svc-operations",
               "lifecycle_state" => "active",
               "lifecycle_state_label" => "Active",
               "service_identity_id" => "svc-operations",
               "token_hint" => identity.token_hint
             }

      assert is_binary(Jason.encode!(vue.props))

      assert identity.capabilities == [:organization_admin]

      render_click(view, "dismiss-service-token", %{})

      dismissed_vue = LiveVue.Test.get_vue(view, id: "admin-organization-show-component")
      assert dismissed_vue.props["issued_service_token"] == nil
    end
  end

  describe "invitation" do
    test "admin can invite a new user and invitation email is delivered", %{
      admin_conn: admin_conn
    } do
      org = create_test_org!("Cadence Ops", "cadence-ops")

      {:ok, view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}/invite")

      assert has_element?(view, "#admin-organization-invite-component")

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-invite-component")

      assert vue.component == "AdminOrganizationInvite"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "form" => %{
                 "display_name" => "",
                 "email" => "",
                 "grant_platform_admin" => false,
                 "membership_role" => "member"
               },
               "page" => %{
                 "breadcrumbs" => [
                   %{"href" => "/admin", "label" => "Platform Admin"},
                   %{"href" => "/admin/organizations", "label" => "Organizations"},
                   %{
                     "href" => "/admin/organizations/#{org.organization_id}",
                     "label" => "Cadence Ops"
                   },
                   %{"href" => nil, "label" => "Invite User"}
                 ],
                 "cancel_href" => "/admin/organizations/#{org.organization_id}",
                 "cancel_label" => "Cancel",
                 "role_options" => [
                   %{"label" => "Organization Admin", "value" => "organization_admin"},
                   %{"label" => "Member", "value" => "member"}
                 ],
                 "submit_label" => "Send invitation",
                 "subtitle" =>
                   "Invite a user to Cadence Ops. The invited user will see a notification and must accept the invitation to gain access.",
                 "title" => "Invite User"
               }
             }

      assert vue.handlers == %{
               "save" => JS.push("save"),
               "validate" => JS.push("validate")
             }

      render_hook(view, "save", %{
        "invite" => %{
          "email" => "new-user@example.com",
          "display_name" => "New User",
          "membership_role" => "organization_admin",
          "grant_platform_admin" => "false"
        }
      })

      {redirect_path, flash} = assert_redirect(view)
      assert redirect_path == ~p"/admin/organizations/#{org.organization_id}"
      assert flash["info"] == "Invitation sent to new-user@example.com."

      # Verify invitation email was delivered
      assert_received {:email, email}
      assert email.to == [{"", "new-user@example.com"}]

      assert [invitation] = Cadence.Accounts.list_pending_invitations(org.organization_id)

      {:ok, detail_view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}")

      vue = LiveVue.Test.get_vue(detail_view, id: "admin-organization-show-component")

      assert vue.props["invitations"] == [
               %{
                 "email" => "new-user@example.com",
                 "expires_on" => Calendar.strftime(invitation.expires_at, "%Y-%m-%d"),
                 "grant_platform_admin" => false,
                 "id" => "organization-invitation-#{invitation.organization_invitation_id}",
                 "invitation_id" => invitation.organization_invitation_id,
                 "role" => "organization_admin",
                 "role_label" => "Organization admin"
               }
             ]
    end

    test "admin can grant an existing durable user directly", %{admin_conn: admin_conn} do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      persist_durable_user!(email: "existing@example.com", password: "password-123456")

      {:ok, view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}/invite")

      render_hook(view, "save", %{
        "invite" => %{
          "email" => "existing@example.com",
          "display_name" => "",
          "membership_role" => "member",
          "grant_platform_admin" => "false"
        }
      })

      # Should redirect back to org detail
      {redirect_path, flash} = assert_redirect(view)
      assert redirect_path == ~p"/admin/organizations/#{org.organization_id}"
      assert flash["info"] == "Invitation sent to existing@example.com."

      assert [invitation] = Cadence.Accounts.list_pending_invitations(org.organization_id)

      # Verify the pending invitation appears on the org detail page
      {:ok, detail_view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}")

      vue = LiveVue.Test.get_vue(detail_view, id: "admin-organization-show-component")

      assert vue.props["members"] == []

      assert vue.props["invitations"] == [
               %{
                 "email" => "existing@example.com",
                 "expires_on" => Calendar.strftime(invitation.expires_at, "%Y-%m-%d"),
                 "grant_platform_admin" => false,
                 "id" => "organization-invitation-#{invitation.organization_invitation_id}",
                 "invitation_id" => invitation.organization_invitation_id,
                 "role" => "member",
                 "role_label" => "Member"
               }
             ]
    end

    test "invite validation preserves all Vue-owned form values", %{admin_conn: admin_conn} do
      org = create_test_org!("Cadence Ops", "cadence-ops")

      {:ok, view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}/invite")

      render_hook(view, "validate", %{
        "invite" => %{
          "email" => "operator@example.com",
          "display_name" => "Flight Operator",
          "membership_role" => "organization_admin",
          "grant_platform_admin" => "true"
        }
      })

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-invite-component")

      assert vue.props["form"] == %{
               "email" => "operator@example.com",
               "display_name" => "Flight Operator",
               "membership_role" => "organization_admin",
               "grant_platform_admin" => true
             }

      assert is_binary(Jason.encode!(vue.props))
    end

    test "invite errors preserve submitted values and exact messages", %{admin_conn: admin_conn} do
      org = create_test_org!("Cadence Ops", "cadence-ops")

      {:ok, view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}/invite")

      render_hook(view, "save", %{
        "invite" => %{
          "email" => "",
          "display_name" => "Pending Operator",
          "membership_role" => "organization_admin",
          "grant_platform_admin" => "true"
        }
      })

      assert has_element?(view, "#flash-error[role='alert']", "Email is required.")

      vue = LiveVue.Test.get_vue(view, id: "admin-organization-invite-component")

      assert vue.props["form"] == %{
               "email" => "",
               "display_name" => "Pending Operator",
               "membership_role" => "organization_admin",
               "grant_platform_admin" => true
             }

      assert Cadence.Accounts.list_pending_invitations(org.organization_id) == []
    end

    test "unknown invitation roles preserve the existing member fallback", %{
      admin_conn: admin_conn
    } do
      org = create_test_org!("Cadence Ops", "cadence-ops")

      {:ok, view, _html} =
        live(admin_conn, ~p"/admin/organizations/#{org.organization_id}/invite")

      render_hook(view, "save", %{
        "invite" => %{
          "email" => "operator@example.com",
          "display_name" => "Pending Operator",
          "membership_role" => "invalid-role",
          "grant_platform_admin" => "false"
        }
      })

      {redirect_path, flash} = assert_redirect(view)
      assert redirect_path == ~p"/admin/organizations/#{org.organization_id}"
      assert flash["info"] == "Invitation sent to operator@example.com."

      assert_received {:email, email}
      assert email.to == [{"", "operator@example.com"}]

      assert [invitation] = Cadence.Accounts.list_pending_invitations(org.organization_id)
      assert invitation.membership_role == :member
      assert invitation.grant_platform_admin == false
    end

    test "missing organization flashes and redirects to the organization list", %{
      admin_conn: admin_conn
    } do
      assert {:error, {:live_redirect, %{to: to, flash: %{"error" => "Organization not found."}}}} =
               live(admin_conn, ~p"/admin/organizations/missing/invite")

      assert to == ~p"/admin/organizations"
    end
  end

  describe "runtime diagnostics" do
    test "admin can inspect dashboard runtime invalidation decisions", %{
      admin_conn: admin_conn
    } do
      reset_runtime_health!()

      invalidation =
        Event.new(
          :source_watermark_changed,
          [:source_result, :frame],
          %{
            organization_id: "org-admin-runtime",
            mission_id: "mission-admin-runtime",
            logical_source: :telemetry,
            observable: "HK.counter"
          },
          %{},
          %{source_results: 1, frames: 1, total: 2},
          occurred_at: ~U[2026-06-24 12:00:00Z]
        )

      RuntimeInvalidation.emit_decision(
        invalidation,
        %{
          dashboard_id: "dashboard-admin-runtime",
          organization_id: "org-admin-runtime",
          mission_id: "mission-admin-runtime",
          matches?: false,
          dashboard_matches?: true,
          context_matches?: false,
          context_reason: :replay_run_mismatch,
          refresh_allowed?: false,
          refresh_reason: :stale_for_context,
          decision_status: :filtered
        },
        invalidation_event_id: Event.id(invalidation)
      )

      Cadence.runtime_health_snapshot()

      {:ok, view, _html} = live(admin_conn, ~p"/admin/runtime")

      vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert vue.component == "AdminRuntime"
      assert vue.class == "contents"
      assert vue.ssr == false
      assert vue.slots == %{}

      assert vue.handlers == %{
               "filter_decisions" => JS.push("filter_decisions"),
               "refresh" => JS.push("refresh")
             }

      assert %{
               "decision_count" => 1,
               "refresh_summary" => "stale_for_context:1",
               "selected_decision_state" => "none",
               "source_summary" => "runtime_health:1",
               "status_summary" => "filtered:1",
               "stats" => stats
             } = vue.props["summary"]

      assert Map.new(stats, &{&1["id"], &1["value"]}) == %{
               "runtime-decision-count" => 1,
               "runtime-filtered" => 1,
               "runtime-refresh-allowed" => 0,
               "runtime-refresh-suppressed" => 1
             }

      assert vue.props["filters"]["values"] == %{
               "affected_placement_id" => "",
               "boundary" => "",
               "context_reason" => "",
               "dashboard_id" => "",
               "mission_id" => "",
               "replay_run_id" => ""
             }

      assert [decision] =
               vue.streams_diff
               |> Enum.filter(fn
                 ["upsert", "/decisions/" <> _index, _row] -> true
                 _operation -> false
               end)
               |> Enum.map(fn ["upsert", _path, row] -> row end)

      assert Map.take(decision, ["dashboard", "context", "refresh", "source"]) == %{
               "context" => "replay_run_mismatch",
               "dashboard" => "dashboard-admin-runtime",
               "refresh" => "stale_for_context",
               "source" => "runtime_health"
             }

      contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
      assert contract == Jason.decode!(Jason.encode!(contract))
    end

    test "admin can filter durable runtime invalidation decisions by impact metadata", %{
      admin_conn: admin_conn
    } do
      reset_runtime_health!()

      org = TestFixtures.persist_org!(display_name: "Runtime Diagnostics Org")
      mission = TestFixtures.persist_mission!(org, display_name: "Runtime Diagnostics Mission")

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          dashboard_id: "dashboard-admin-runtime-durable",
          name: "Runtime Diagnostics Dashboard"
        )

      matching_invalidation =
        Event.new(
          :source_watermark_changed,
          [:source_result, :frame],
          %{
            organization_id: org.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.counter",
            replay_run_id: "replay-admin-run-1",
            access_token: "runtime-token-sentinel"
          },
          %{},
          %{source_results: 2, frames: 1, total: 3},
          occurred_at: ~U[2026-06-24 12:10:00Z]
        )

      assert {:ok, matching_decision_event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 matching_invalidation,
                 %{
                   dashboard_id: dashboard.dashboard_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   matches?: false,
                   dashboard_matches?: true,
                   context_matches?: false,
                   context_reason: :replay_run_mismatch,
                   refresh_allowed?: false,
                   refresh_reason: :stale_for_context,
                   affected_placement_count: 1,
                   affected_placement_ids: ["placement-admin-counter"],
                   affected_widget_type_ids: ["cadence.value_tile"],
                   affected_impact_reasons: [:primary_source],
                   api_secret: "runtime-secret-sentinel",
                   decision_status: :filtered
                 },
                 invalidation_event_id: Event.id(matching_invalidation),
                 decision_observed_at: ~U[2026-06-24 12:10:05Z]
               )

      other_invalidation =
        Event.new(
          :source_watermark_changed,
          [:source_result],
          %{
            organization_id: org.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.voltage",
            replay_run_id: "replay-admin-run-2"
          },
          %{},
          %{source_results: 1, total: 1},
          occurred_at: ~U[2026-06-24 12:11:00Z]
        )

      assert {:ok, _event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 other_invalidation,
                 %{
                   dashboard_id: dashboard.dashboard_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   matches?: true,
                   dashboard_matches?: true,
                   context_matches?: true,
                   context_reason: :active_context,
                   refresh_allowed?: true,
                   refresh_reason: :source_changed,
                   affected_placement_count: 1,
                   affected_placement_ids: ["placement-admin-voltage"],
                   affected_widget_type_ids: ["cadence.trend_chart"],
                   affected_impact_reasons: [:secondary_source],
                   decision_status: :refresh_allowed
                 },
                 invalidation_event_id: Event.id(other_invalidation),
                 decision_observed_at: ~U[2026-06-24 12:11:05Z]
               )

      {:ok, view, _html} =
        live(
          admin_conn,
          ~p"/admin/runtime?#{%{dashboard_id: dashboard.dashboard_id, boundary: "source_watermark_changed", context_reason: "replay_run_mismatch", replay_run_id: "replay-admin-run-1", affected_placement_id: "placement-admin-counter", decision: matching_decision_event.dashboard_runtime_invalidation_decision_event_id}}"
        )

      vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert Map.take(vue.props["summary"], [
               "decision_count",
               "selected_decision_state",
               "source_summary"
             ]) == %{
               "decision_count" => 1,
               "selected_decision_state" => "visible",
               "source_summary" => "durable_projection:1"
             }

      assert Map.take(vue.props["filters"]["values"], [
               "affected_placement_id",
               "dashboard_id",
               "replay_run_id"
             ]) == %{
               "affected_placement_id" => "placement-admin-counter",
               "dashboard_id" => dashboard.dashboard_id,
               "replay_run_id" => "replay-admin-run-1"
             }

      assert [decision] =
               vue.streams_diff
               |> Enum.filter(fn
                 ["upsert", "/decisions/" <> _index, _row] -> true
                 _operation -> false
               end)
               |> Enum.map(fn ["upsert", _path, row] -> row end)

      assert Map.take(decision, [
               "affected_impact",
               "affected_placements",
               "replay_run",
               "source"
             ]) == %{
               "affected_impact" => "primary_source",
               "affected_placements" => "placement-admin-counter",
               "replay_run" => "replay-admin-run-1",
               "source" => "durable_projection"
             }

      refute decision["affected_placements"] =~ "placement-admin-voltage"
      refute decision["replay_run"] =~ "replay-admin-run-2"
      assert decision["inspect_action"]["selected"] == true

      assert URI.decode_query(URI.parse(decision["inspect_action"]["href"]).query) == %{
               "affected_placement_id" => "placement-admin-counter",
               "boundary" => "source_watermark_changed",
               "context_reason" => "replay_run_mismatch",
               "dashboard_id" => dashboard.dashboard_id,
               "decision" =>
                 matching_decision_event.dashboard_runtime_invalidation_decision_event_id,
               "replay_run_id" => "replay-admin-run-1"
             }

      selection = vue.props["selection"]
      assert selection["state"] == "visible"
      assert selection["missing"] == false
      assert selection["outside_results"] == false
      assert selection["context_href"] == nil

      detail = selection["detail"]

      assert Map.take(detail["evidence"], ["decision_key", "source"]) == %{
               "decision_key" =>
                 matching_decision_event.dashboard_runtime_invalidation_decision_event_id,
               "source" => "durable_projection"
             }

      facts =
        detail["evidence"]["groups"]
        |> Enum.flat_map(& &1["facts"])
        |> Map.new(&{&1["label"], &1["value"]})

      assert facts["Decision ID"] ==
               matching_decision_event.dashboard_runtime_invalidation_decision_event_id

      assert facts["Replay Run"] == "replay-admin-run-1"

      sections = Map.new(detail["sections"], &{&1["label"], &1})
      filter_pairs = Map.new(sections["Filters"]["pairs"], &{&1["label"], &1["value"]})

      measurement_pairs =
        Map.new(sections["Measurements"]["pairs"], &{&1["label"], &1["value"]})

      decision_pairs =
        Map.new(sections["Decision Payload"]["pairs"], &{&1["label"], &1["value"]})

      assert filter_pairs["observable"] == "HK.counter"
      assert measurement_pairs["source_results"] == "2"
      assert decision_pairs["dashboard_matches?"] == "true"

      assert URI.decode_query(URI.parse(detail["close_action"]["href"]).query) == %{
               "affected_placement_id" => "placement-admin-counter",
               "boundary" => "source_watermark_changed",
               "context_reason" => "replay_run_mismatch",
               "dashboard_id" => dashboard.dashboard_id,
               "replay_run_id" => "replay-admin-run-1"
             }

      encoded_contract =
        Jason.encode!(%{"props" => vue.props, "streams_diff" => vue.streams_diff})

      refute encoded_contract =~ "runtime-token-sentinel"
      refute encoded_contract =~ "runtime-secret-sentinel"
      refute encoded_contract =~ "access_token"
      refute encoded_contract =~ "api_secret"

      render_hook(view, "refresh", %{})
      refreshed_vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert refreshed_vue.props == vue.props

      assert refreshed_vue.streams_diff
             |> Enum.filter(fn
               ["upsert", "/decisions/" <> _index, _row] -> true
               _operation -> false
             end)
             |> Enum.map(fn ["upsert", _path, row] -> row end) == [decision]

      refreshed_contract = %{
        "props" => refreshed_vue.props,
        "streams_diff" => refreshed_vue.streams_diff
      }

      assert refreshed_contract == Jason.decode!(Jason.encode!(refreshed_contract))
    end

    test "admin deep links render selected decision detail outside filtered results", %{
      admin_conn: admin_conn
    } do
      reset_runtime_health!()

      org = TestFixtures.persist_org!(display_name: "Runtime Deep Link Org")
      mission = TestFixtures.persist_mission!(org, display_name: "Runtime Deep Link Mission")

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          dashboard_id: "dashboard-admin-runtime-deep-link",
          name: "Runtime Deep Link Dashboard"
        )

      invalidation =
        Event.new(
          :historical_data_changed,
          [:source_result, :frame],
          %{
            organization_id: org.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.counter",
            replay_run_id: "replay-admin-deep-link"
          },
          %{},
          %{source_results: 1, frames: 1, total: 2},
          occurred_at: ~U[2026-06-24 12:20:00Z]
        )

      assert {:ok, decision_event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 invalidation,
                 %{
                   dashboard_id: dashboard.dashboard_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   matches?: false,
                   dashboard_matches?: true,
                   context_matches?: false,
                   context_reason: :replay_run_mismatch,
                   refresh_allowed?: false,
                   refresh_reason: :stale_for_context,
                   affected_placement_count: 1,
                   affected_placement_ids: ["placement-admin-deep-link"],
                   affected_widget_type_ids: ["cadence.value_tile"],
                   affected_impact_reasons: [:primary_source],
                   decision_status: :filtered
                 },
                 invalidation_event_id: Event.id(invalidation),
                 decision_observed_at: ~U[2026-06-24 12:20:05Z]
               )

      {:ok, view, _html} =
        live(
          admin_conn,
          ~p"/admin/runtime?#{%{dashboard_id: "dashboard-filter-miss", decision: decision_event.dashboard_runtime_invalidation_decision_event_id}}"
        )

      vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert Map.take(vue.props["summary"], ["decision_count", "selected_decision_state"]) == %{
               "decision_count" => 0,
               "selected_decision_state" => "outside_results"
             }

      assert vue.props["filters"]["values"]["dashboard_id"] == "dashboard-filter-miss"

      assert vue.streams_diff
             |> Enum.filter(fn
               ["upsert", "/decisions/" <> _index, _row] -> true
               _operation -> false
             end) == []

      selection = vue.props["selection"]

      assert Map.take(selection, [
               "decision_key",
               "missing",
               "outside_results",
               "state"
             ]) == %{
               "decision_key" => decision_event.dashboard_runtime_invalidation_decision_event_id,
               "missing" => false,
               "outside_results" => true,
               "state" => "outside_results"
             }

      context_link = selection["context_href"]

      assert URI.parse(context_link).path == "/admin/runtime"

      assert URI.decode_query(URI.parse(context_link).query) == %{
               "affected_placement_id" => "placement-admin-deep-link",
               "boundary" => "historical_data_changed",
               "context_reason" => "replay_run_mismatch",
               "dashboard_id" => dashboard.dashboard_id,
               "decision" => decision_event.dashboard_runtime_invalidation_decision_event_id,
               "mission_id" => mission.mission_id,
               "replay_run_id" => "replay-admin-deep-link"
             }

      detail = selection["detail"]

      assert Map.take(detail["evidence"], ["decision_key", "source"]) == %{
               "decision_key" => decision_event.dashboard_runtime_invalidation_decision_event_id,
               "source" => "durable_projection"
             }

      facts =
        detail["evidence"]["groups"]
        |> Enum.flat_map(& &1["facts"])
        |> Map.new(&{&1["label"], &1["value"]})

      assert facts["Decision ID"] ==
               decision_event.dashboard_runtime_invalidation_decision_event_id

      assert facts["Replay Run"] == "replay-admin-deep-link"

      render_patch(view, context_link)
      context_vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert Map.take(context_vue.props["summary"], [
               "decision_count",
               "selected_decision_state"
             ]) == %{
               "decision_count" => 1,
               "selected_decision_state" => "visible"
             }

      assert [context_row] =
               context_vue.streams_diff
               |> Enum.filter(fn
                 ["upsert", "/decisions/" <> _index, _row] -> true
                 _operation -> false
               end)
               |> Enum.map(fn ["upsert", _path, row] -> row end)

      assert context_row["key"] ==
               decision_event.dashboard_runtime_invalidation_decision_event_id
    end

    test "admin runtime diagnostics show an empty decision state", %{admin_conn: admin_conn} do
      reset_runtime_health!()

      {:ok, view, _html} = live(admin_conn, ~p"/admin/runtime")

      vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert vue.props["summary"]["decision_count"] == 0

      assert vue.props["summary"]["empty_state"] == %{
               "copy" => "No dashboard runtime invalidation decisions have been recorded.",
               "id" => "admin-runtime-decisions-empty"
             }

      assert vue.streams_diff
             |> Enum.filter(fn
               ["upsert", "/decisions/" <> _index, _row] -> true
               _operation -> false
             end) == []
    end

    test "runtime filter events normalize string values and keep the URL canonical", %{
      admin_conn: admin_conn
    } do
      reset_runtime_health!()

      {:ok, view, _html} = live(admin_conn, ~p"/admin/runtime")

      render_hook(view, "filter_decisions", %{
        "runtime_decision_filters" => %{
          "affected_placement_id" => "",
          "boundary" => " source_watermark_changed ",
          "context_reason" => "",
          "dashboard_id" => " dashboard-canonical ",
          "ignored" => "not-projected",
          "mission_id" => "",
          "replay_run_id" => " replay-canonical "
        }
      })

      patched_path = assert_patch(view)
      assert URI.parse(patched_path).path == "/admin/runtime"

      assert URI.decode_query(URI.parse(patched_path).query) == %{
               "boundary" => "source_watermark_changed",
               "dashboard_id" => "dashboard-canonical",
               "replay_run_id" => "replay-canonical"
             }

      render_patch(view, patched_path)
      vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert vue.props["filters"]["values"] == %{
               "affected_placement_id" => "",
               "boundary" => "source_watermark_changed",
               "context_reason" => "",
               "dashboard_id" => "dashboard-canonical",
               "mission_id" => "",
               "replay_run_id" => "replay-canonical"
             }

      assert vue.props["filters"]["clear_href"] == "/admin/runtime"

      assert Enum.map(vue.props["filters"]["fields"], & &1["key"]) == [
               "dashboard_id",
               "mission_id",
               "boundary",
               "context_reason",
               "replay_run_id",
               "affected_placement_id"
             ]
    end

    test "missing selected decisions remain an explicit server-owned state", %{
      admin_conn: admin_conn
    } do
      reset_runtime_health!()

      {:ok, view, _html} =
        live(admin_conn, ~p"/admin/runtime?decision=missing-runtime-decision")

      vue = LiveVue.Test.get_vue(view, id: "admin-runtime-component")

      assert vue.props["summary"]["selected_decision_state"] == "missing"

      assert vue.props["selection"] == %{
               "context_href" => nil,
               "decision_key" => "missing-runtime-decision",
               "detail" => nil,
               "missing" => true,
               "outside_results" => false,
               "state" => "missing"
             }
    end
  end

  ## Helpers

  defp reset_runtime_health! do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)
  end

  defp issue_platform_admin_session! do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: "platform-admin-#{System.unique_integer([:positive])}@example.test",
        display_name: "Platform Administrator",
        capabilities: [:platform_admin],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))
    assert {:ok, issued_session} = Authentication.issue_browser_session(user, nil)
    issued_session
  end

  defp persist_durable_user!(opts) when is_list(opts) do
    password = Keyword.fetch!(opts, :password)
    email = Keyword.fetch!(opts, :email)

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: Keyword.get(opts, :display_name, "Durable User"),
        capabilities: Keyword.get(opts, :capabilities, []),
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  defp create_test_org!(display_name, slug) do
    org = Organization.new(%{display_name: display_name, slug: slug})
    assert {:ok, persisted} = Cadence.Organizations.persist_organization(org)
    persisted
  end

  defp flush_mailbox do
    receive do
      {:email, _email} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
