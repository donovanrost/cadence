defmodule CadenceWeb.AdminLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Accounts.{Password, User, UserLocalCredentialRow, UserRow}
  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @environment_admin_email "environment-admin@example.com"
  @environment_admin_password "environment-admin-password-123"

  setup do
    previous_environment_admin = Application.get_env(:cadence, :environment_admin, [])

    Application.put_env(:cadence, :environment_admin,
      enabled: true,
      email: @environment_admin_email,
      display_name: "Environment Admin",
      password: @environment_admin_password
    )

    reset_control_plane_state!()
    assert {:ok, _user} = Cadence.Auth.reconcile_environment_admin()
    flush_mailbox()

    on_exit(fn ->
      Application.put_env(:cadence, :environment_admin, previous_environment_admin)
      flush_mailbox()
    end)

    :ok
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

    test "platform admin can access the dashboard" do
      {:ok, _view, html} = live(admin_conn(), ~p"/admin")
      assert html =~ "Platform Administration"
    end
  end

  describe "organization management" do
    test "admin dashboard shows organization and user counts" do
      {:ok, _view, html} = live(admin_conn(), ~p"/admin")
      assert html =~ "Organizations"
      assert html =~ "Users"
      assert html =~ "Runtime"
    end

    test "organization list shows empty state when no orgs exist" do
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations")
      assert html =~ "No organizations yet"
    end

    test "admin can create an organization" do
      {:ok, view, _html} = live(admin_conn(), ~p"/admin/organizations/new")

      view
      |> form("#org-form", organization: %{display_name: "Test Org", slug: "test-org"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/organizations")

      # Verify the org appears in the list
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations")
      assert html =~ "Test Org"
      assert html =~ "test-org"
    end

    test "admin can view organization detail with no members" do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      {:ok, view, html} = live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}")
      assert html =~ "Cadence Ops"
      assert html =~ "No members yet"
      assert has_element?(view, "#admin-service-identities")
      assert has_element?(view, "#service-identity-form")
      assert has_element?(view, ~s(form[action="/session/organization"]))
    end

    test "admin can issue the first product API service credential" do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      {:ok, view, _html} = live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}")

      view
      |> form("#service-identity-form",
        service_identity: %{
          display_name: "Operations Automation",
          service_identity_id: "svc-operations"
        }
      )
      |> render_submit()

      assert has_element?(view, "#issued-service-token code")
      assert has_element?(view, "#service-identities-table", "Operations Automation")

      assert {:ok, identity} =
               Cadence.Auth.fetch_service_identity(org.organization_id, "svc-operations")

      assert identity.capabilities == [:organization_admin]
    end
  end

  describe "invitation" do
    test "admin can invite a new user and invitation email is delivered" do
      org = create_test_org!("Cadence Ops", "cadence-ops")

      {:ok, view, _html} =
        live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}/invite")

      view
      |> form("#invite-form",
        invite: %{
          email: "new-user@example.com",
          display_name: "New User",
          membership_role: "organization_admin"
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/organizations/#{org.organization_id}")

      # Verify invitation email was delivered
      assert_received {:email, email}
      assert email.to == [{"", "new-user@example.com"}]
    end

    test "admin can grant an existing durable user directly" do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      persist_durable_user!(email: "existing@example.com", password: "password-123456")

      {:ok, view, _html} =
        live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}/invite")

      view
      |> form("#invite-form",
        invite: %{
          email: "existing@example.com",
          membership_role: "member"
        }
      )
      |> render_submit()

      # Should redirect back to org detail
      assert_redirect(view, ~p"/admin/organizations/#{org.organization_id}")

      # Verify the member appears on the org detail page
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}")
      assert html =~ "existing@example.com"
    end
  end

  describe "runtime diagnostics" do
    test "admin can inspect dashboard runtime invalidation decisions" do
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

      {:ok, view, _html} = live(admin_conn(), ~p"/admin/runtime")

      assert has_element?(
               view,
               ~s(#admin-runtime-page[data-runtime-decision-count="1"][data-runtime-decision-status-summary="filtered:1"][data-runtime-decision-refresh-summary="stale_for_context:1"])
             )

      assert has_element?(view, "#runtime-decision-count", "1")
      assert has_element?(view, "#runtime-refresh-suppressed", "1")
      assert has_element?(view, "#runtime-filtered", "1")

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="dashboard"]),
               "dashboard-admin-runtime"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="context"]),
               "replay_run_mismatch"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="refresh"]),
               "stale_for_context"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="source"]),
               "runtime_health"
             )
    end

    test "admin can filter durable runtime invalidation decisions by impact metadata" do
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
            replay_run_id: "replay-admin-run-1"
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
          admin_conn(),
          ~p"/admin/runtime?#{%{dashboard_id: dashboard.dashboard_id, boundary: "source_watermark_changed", context_reason: "replay_run_mismatch", replay_run_id: "replay-admin-run-1", affected_placement_id: "placement-admin-counter", decision: matching_decision_event.dashboard_runtime_invalidation_decision_event_id}}"
        )

      assert has_element?(
               view,
               ~s(#admin-runtime-page[data-runtime-decision-count="1"][data-runtime-decision-source-summary="durable_projection:1"][data-runtime-decision-filter-dashboard="#{dashboard.dashboard_id}"][data-runtime-decision-filter-replay-run="replay-admin-run-1"][data-runtime-decision-filter-affected-placement="placement-admin-counter"][data-runtime-selected-decision-state="visible"])
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="source"]),
               "durable_projection"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="affected-placements"]),
               "placement-admin-counter"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="affected-impact"]),
               "primary_source"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="replay-run"]),
               "replay-admin-run-1"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail-evidence[data-runtime-decision-detail-key="#{matching_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-runtime-decision-detail-source="durable_projection"])
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail [data-runtime-decision-detail-field="Decision-ID"]),
               matching_decision_event.dashboard_runtime_invalidation_decision_event_id
             )

      assert has_element?(
               view,
               "#admin-runtime-decision-detail-filters",
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail [data-runtime-decision-detail-field="Replay-Run"]),
               "replay-admin-run-1"
             )

      assert has_element?(
               view,
               "#admin-runtime-decision-detail-measurements",
               "source_results"
             )

      assert has_element?(
               view,
               "#admin-runtime-decision-detail-decision",
               "dashboard_matches?"
             )

      refute has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="affected-placements"]),
               "placement-admin-voltage"
             )

      refute has_element?(
               view,
               ~s(#admin-runtime-decisions-table [data-runtime-decision-field="replay-run"]),
               "replay-admin-run-2"
             )
    end

    test "admin deep links render selected decision detail outside filtered results" do
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
          admin_conn(),
          ~p"/admin/runtime?#{%{dashboard_id: "dashboard-filter-miss", decision: decision_event.dashboard_runtime_invalidation_decision_event_id}}"
        )

      assert has_element?(
               view,
               ~s(#admin-runtime-page[data-runtime-decision-count="0"][data-runtime-decision-filter-dashboard="dashboard-filter-miss"][data-runtime-selected-decision-state="outside_results"])
             )

      assert has_element?(view, "#admin-runtime-decisions-empty")
      refute has_element?(view, "#admin-runtime-decision-detail-missing")

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail-outside-results[data-runtime-selected-decision-key="#{decision_event.dashboard_runtime_invalidation_decision_event_id}"]),
               "outside the current filtered result set"
             )

      assert has_element?(
               view,
               "#admin-runtime-show-selected-context",
               "Show in table context"
             )

      context_link =
        view
        |> element("#admin-runtime-decision-detail-outside-results")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#admin-runtime-decision-detail-outside-results")
        |> LazyHTML.attribute("data-runtime-selected-decision-context-link")
        |> List.first()

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

      assert [^context_link] =
               view
               |> element("#admin-runtime-decision-detail-outside-results")
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#admin-runtime-show-selected-context")
               |> LazyHTML.attribute("href")

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail-evidence[data-runtime-decision-detail-key="#{decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-runtime-decision-detail-source="durable_projection"])
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail [data-runtime-decision-detail-field="Decision-ID"]),
               decision_event.dashboard_runtime_invalidation_decision_event_id
             )

      assert has_element?(
               view,
               ~s(#admin-runtime-decision-detail [data-runtime-decision-detail-field="Replay-Run"]),
               "replay-admin-deep-link"
             )
    end

    test "admin runtime diagnostics show an empty decision state" do
      reset_runtime_health!()

      {:ok, view, _html} = live(admin_conn(), ~p"/admin/runtime")

      assert has_element?(view, "#admin-runtime-page[data-runtime-decision-count=\"0\"]")
      assert has_element?(view, "#admin-runtime-decisions-empty")
    end
  end

  ## Helpers

  defp admin_conn do
    issued_session = environment_admin_session()

    build_conn()
    |> init_test_session(%{
      user_session_token: issued_session.session_token,
      admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
    })
  end

  defp reset_runtime_health! do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)
  end

  defp environment_admin_session do
    assert {:ok, issued_session} =
             Cadence.Auth.login_environment_admin(
               @environment_admin_email,
               @environment_admin_password
             )

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
