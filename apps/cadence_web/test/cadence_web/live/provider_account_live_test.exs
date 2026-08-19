defmodule CadenceWeb.ProviderAccountLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.GroundNetworks.{
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox
  }

  alias CadenceWeb.TestFixtures

  setup do
    previous_opts = Application.get_env(:cadence_web, :provider_account_live_opts)

    Application.put_env(
      :cadence_web,
      :provider_account_live_opts,
      manage_backend?: false,
      secret_backend: &secret_backend/2
    )

    on_exit(fn ->
      case previous_opts do
        nil -> Application.delete_env(:cadence_web, :provider_account_live_opts)
        value -> Application.put_env(:cadence_web, :provider_account_live_opts, value)
      end
    end)

    :ok
  end

  test "organization administrators can navigate to the account registry" do
    {conn, _user, _organization} = signed_in_organization_admin()

    {:ok, home, _html} = live(conn, ~p"/")
    assert has_element?(home, "#provider-accounts-nav-link")

    {:ok, view, _html} = live(conn, ~p"/provider-accounts")
    assert has_element?(view, "#provider-accounts-page")
    assert has_element?(view, "#new-provider-account-link")
  end

  test "ordinary members are redirected away from Provider Account administration" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization, role: :member)
    conn = TestFixtures.member_conn(user)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/provider-accounts")
  end

  test "registers an account without rendering secret material fields" do
    {conn, _user, organization} = signed_in_organization_admin()

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/new")

    assert has_element?(view, "#provider-account-form")
    assert has_element?(view, "#provider-account-boundary-note")

    assert has_element?(
             view,
             "#provider-connector-summary[data-provider-type='simulator'][data-provider-client='simulator_http']"
           )

    assert has_element?(
             view,
             "#provider-connector-configuration[data-extension-presentation='provider_connector']"
           )

    assert has_element?(view, "#provider-account-control-plane-section-fields")
    assert has_element?(view, "#provider-connector-configuration-input-base-url")
    assert has_element?(view, "select[name='provider_account[backend_type]']")
    assert has_element?(view, "input[name='provider_account[backend_key]']")
    refute has_element?(view, "input[name='provider_account[secret_material]']")
    refute has_element?(view, "input[type='password']")

    assert {:error, {:live_redirect, %{to: target}}} =
             view
             |> form("#provider-account-form",
               provider_account: %{
                 display_name: "Local Ground Network Simulator",
                 provider_type: "simulator",
                 base_url: "http://127.0.0.1:4101",
                 region_ref: "local",
                 environment_ref: "demo-alpha",
                 event_ingestion_mode: "polling",
                 backend_type: "external",
                 backend_key: "providers/local-simulator",
                 allowed_services: "telemetry, tracking",
                 allowed_directions: "downlink",
                 allowed_stations: "station-alpha",
                 max_quota: "50"
               }
             )
             |> render_submit()

    assert target =~ "/provider-accounts/"
    assert [{account, version}] = ProviderAccounts.list_for_system(organization.organization_id)
    assert account.display_name == "Local Ground Network Simulator"
    assert version.provider_type == :simulator
    assert version.client_key == :simulator_http
    assert version.guardrails["allowed_stations"] == ["station-alpha"]
  end

  test "validates, rotates, and revokes a stable credential reference" do
    {conn, _user, organization} = signed_in_organization_admin()
    {account, _version, credential} = persist_account!(organization)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")

    assert has_element?(view, "#provider-account-show-page")
    assert has_element?(view, "#provider-account-credential-status", "Active · v1")
    assert has_element?(view, "#validate-provider-account-button")
    assert has_element?(view, "#rotate-provider-credential-button")
    assert has_element?(view, "#revoke-provider-credential-button")
    refute has_element?(view, "input[type='password']")

    view |> element("#validate-provider-account-button") |> render_click()
    render_async(view)
    assert has_element?(view, "#provider-account-health", "Validated")

    view |> element("#rotate-provider-credential-button") |> render_click()
    render_async(view)
    assert has_element?(view, "#provider-account-credential-status", "Active · v2")

    assert {:ok, rotated} =
             ProviderCredentials.fetch(
               organization.organization_id,
               account.provider_account_id,
               credential.provider_credential_ref
             )

    assert rotated.provider_credential_ref == credential.provider_credential_ref

    view |> element("#revoke-provider-credential-button") |> render_click()
    render_async(view)
    assert has_element?(view, "#provider-account-credential-status", "Revoked · v3")
    refute has_element?(view, "#revoke-provider-credential-button")
  end

  test "grants and revokes mission access from the account page" do
    {conn, _user, organization} = signed_in_organization_admin()
    mission = TestFixtures.persist_mission!(organization, display_name: "Aurora")
    {account, _version, _credential} = persist_account!(organization)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")

    view
    |> form("#provider-account-grant-form",
      grant: %{
        mission_id: mission.mission_id,
        allowed_services: "telemetry",
        allowed_stations: "station-alpha",
        max_quota: "20",
        grant_reason: "Aurora flight operations"
      }
    )
    |> render_submit()

    [grant] =
      ProviderAccountGrants.list_for_mission(organization.organization_id, mission.mission_id)

    assert has_element?(view, "#account-grant-#{grant.provider_account_grant_id}")
    assert has_element?(view, "#revoke-grant-#{grant.provider_account_grant_id}")

    view
    |> element("#revoke-grant-#{grant.provider_account_grant_id}")
    |> render_click()

    assert {:error, :provider_account_grant_revoked} =
             ProviderAccountGrants.fetch_active_for_system(
               organization.organization_id,
               grant.provider_account_grant_id
             )
  end

  test "shows durable cursor health, inbox backlog, and quarantine counts" do
    {conn, _user, organization} = signed_in_organization_admin()
    {account, version, _credential} = persist_account!(organization)
    now = ~U[2026-07-15 20:30:00.000000Z]

    {:ok, cursor} = ProviderEventCursors.ensure(version)

    {:ok, cursor} =
      ProviderEventCursors.claim(cursor.provider_event_cursor_id, "web-test", now: now)

    assert {:ok, %{inserted: 2, quarantined: 1}} =
             ProviderEventInbox.ingest_page(
               cursor,
               [
                 provider_event("event-known", "contact.status_changed"),
                 provider_event("event-unknown", "vendor.future_event")
               ],
               "cursor-web-one",
               "web-test",
               now: now
             )

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")

    assert has_element?(view, "#provider-account-ingestion-health", "Healthy")
    assert has_element?(view, "#provider-account-ingestion-backlog", "1")
    assert has_element?(view, "#provider-account-ingestion-quarantined", "1")
    assert has_element?(view, "#provider-account-ingestion-last-event", "2026-07-15 20:29Z")
  end

  defp signed_in_organization_admin do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()

    _membership =
      TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    {TestFixtures.member_conn(user), user, organization}
  end

  defp persist_account!(organization) do
    suffix = System.unique_integer([:positive])
    account_id = "provider-account-web-#{suffix}"
    credential_ref = "provider-credential-web-#{suffix}"
    now = ~U[2026-07-15 20:00:00.000000Z]

    {:ok, credential} =
      ProviderCredentials.create(
        organization.organization_id,
        account_id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "providers/web/#{suffix}",
          registered_at: now
        },
        manage_backend?: false,
        now: now
      )

    {:ok, account, version} =
      ProviderAccounts.create_for_system(
        organization.organization_id,
        %{
          provider_account_id: account_id,
          display_name: "Ground Network Simulator",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          region_ref: "local",
          environment_ref: "demo",
          credential_ref: credential_ref,
          guardrails: %{
            "allowed_services" => ["telemetry", "tracking"],
            "allowed_stations" => ["station-alpha", "station-beta"],
            "max_quota" => 100
          }
        },
        %{"kind" => "system", "id" => "provider-account-live-test"},
        validate_credential?: false,
        now: now
      )

    {account, version, credential}
  end

  defp secret_backend(_descriptor, _opts),
    do: {:ok, %{material: %{value: "ephemeral-test-secret"}, backend_version: "test-v1"}}

  defp provider_event(id, type) do
    %{
      "id" => id,
      "schema_version" => "1.0",
      "sequence" => 1,
      "occurred_at" => "2026-07-15T20:29:00.000000Z",
      "type" => type,
      "resource_type" => "contact",
      "resource_id" => "provider-contact-web",
      "resource_revision" => 1,
      "client_reference" => "cadence-contact-web",
      "data" => %{}
    }
  end
end
