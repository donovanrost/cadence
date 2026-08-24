defmodule CadenceWeb.ProviderAccountLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import CadenceWeb.AsyncLiveViewTestSupport,
    only: [render_async: 1, track_async_view: 1]

  import Phoenix.LiveViewTest, except: [render_async: 1, render_async: 2]

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

    assert has_element?(view, "#provider-account-new-component")
    refute has_element?(view, "#provider-account-form")

    vue = provider_account_new_vue(view)

    assert vue.component == "ProviderAccountNew"
    assert vue.class == "max-w-3xl space-y-6"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.handlers == %{
             "save" => Phoenix.LiveView.JS.push("save"),
             "validate" => Phoenix.LiveView.JS.push("validate")
           }

    assert vue.props["page"] == %{
             "id" => "provider-account-new-page",
             "heading" => "Register Provider Account",
             "subtitle" =>
               "Create one organization-owned control-plane identity. Mission access is granted separately.",
             "breadcrumbs" => [
               %{"label" => "Provider Accounts", "href" => "/provider-accounts"},
               %{"label" => "New", "href" => nil}
             ]
           }

    form_dto = vue.props["form"]
    assert form_dto["id"] == "provider-account-form"
    assert form_dto["hidden_field_keys"] == ["provider_account_id", "credential_ref"]
    assert form_dto["connector"]["boundary"]["id"] == "provider-account-boundary-note"

    assert form_dto["connector"]["options"] == [
             %{
               "label" => "Ground Network Simulator",
               "value" => "simulator",
               "disabled" => false
             }
           ]

    assert form_dto["connector"]["selected"] == %{
             "id" => "provider-connector-summary",
             "form_value" => "simulator",
             "provider_type" => "simulator",
             "client_key" => "simulator_http",
             "label" => "Ground Network Simulator",
             "description" =>
               "Cadence simulator control plane for local scheduling, profile sync, and provider events."
           }

    configuration = form_dto["connector"]["configuration"]
    assert configuration["id"] == "provider-connector-configuration"
    assert configuration["kind"] == "provider_connector"

    assert [control_plane] = configuration["sections"]
    assert control_plane["id"] == "provider-account-control-plane-section"
    assert control_plane["fields_id"] == "provider-account-control-plane-section-fields"

    assert Enum.map(control_plane["fields"], & &1["key"]) == [
             "base_url",
             "region_ref",
             "environment_ref",
             "event_ingestion_mode"
           ]

    assert Enum.find(control_plane["fields"], &(&1["key"] == "base_url")) == %{
             "key" => "base_url",
             "wrapper_id" => "provider-connector-configuration-field-base-url",
             "id" => "provider-connector-configuration-input-base-url",
             "name" => "provider_account[base_url]",
             "type" => "url",
             "label" => "Provider API Base URL",
             "required" => true,
             "placeholder" => "http://127.0.0.1:4101",
             "help" => nil,
             "step" => nil,
             "min" => nil,
             "max" => nil,
             "default" => "http://127.0.0.1:4101",
             "value" => "http://127.0.0.1:4101",
             "options" => [],
             "reference" => nil,
             "visible_when" => nil
           }

    fields = provider_account_fields(vue)
    backend_type = Enum.find(fields, &(&1["key"] == "backend_type"))
    backend_key = Enum.find(fields, &(&1["key"] == "backend_key"))

    assert backend_type["type"] == "select"
    assert backend_type["name"] == "provider_account[backend_type]"
    assert backend_key["type"] == "text"
    assert backend_key["name"] == "provider_account[backend_key]"
    refute Enum.any?(fields, &(&1["name"] == "provider_account[secret_material]"))
    refute Enum.any?(fields, &(&1["type"] == "password"))

    render_hook(view, "validate", %{
      "provider_account" =>
        provider_account_params(vue, %{
          "display_name" => "Local Ground Network Simulator",
          "provider_type" => "unsupported-provider",
          "base_url" => "http://127.0.0.1:4201",
          "environment_ref" => "demo-alpha",
          "event_ingestion_mode" => "hybrid",
          "backend_type" => "env",
          "backend_key" => "CADENCE_LOCAL_SIMULATOR_TOKEN"
        })
    })

    validated_vue = provider_account_new_vue(view)
    validated_fields = provider_account_fields(validated_vue)

    assert validated_vue.props["form"]["connector"]["selected"]["form_value"] == "simulator"
    assert Enum.find(validated_fields, &(&1["key"] == "provider_type"))["value"] == "simulator"

    validated_backend_key = Enum.find(validated_fields, &(&1["key"] == "backend_key"))
    assert validated_backend_key["label"] == "Environment Variable"
    assert validated_backend_key["placeholder"] == "CADENCE_SIMULATOR_TOKEN"
    assert validated_backend_key["value"] == "CADENCE_LOCAL_SIMULATOR_TOKEN"

    validated_base_url = Enum.find(validated_fields, &(&1["key"] == "base_url"))
    assert validated_base_url["value"] == "http://127.0.0.1:4201"

    invalid_provider_params =
      provider_account_params(validated_vue, %{"provider_type" => "unsupported-provider"})

    render_hook(view, "save", %{"provider_account" => invalid_provider_params})
    assert has_element?(view, "#flash-error[role='alert']", "Could not register provider account")
    assert ProviderAccounts.list_for_system(organization.organization_id) == []

    invalid_backend_params =
      provider_account_params(provider_account_new_vue(view), %{
        "provider_type" => "simulator",
        "backend_type" => "inline"
      })

    render_hook(view, "save", %{"provider_account" => invalid_backend_params})
    assert has_element?(view, "#flash-error[role='alert']", "Select a supported secret backend")
    assert ProviderAccounts.list_for_system(organization.organization_id) == []

    valid_params =
      provider_account_params(provider_account_new_vue(view), %{
        "display_name" => "Local Ground Network Simulator",
        "provider_type" => "simulator",
        "base_url" => "http://127.0.0.1:4101",
        "region_ref" => "local",
        "environment_ref" => "demo-alpha",
        "event_ingestion_mode" => "polling",
        "backend_type" => "external",
        "backend_key" => "providers/local-simulator",
        "allowed_services" => "telemetry, tracking",
        "allowed_directions" => "downlink",
        "allowed_stations" => "station-alpha",
        "max_quota" => "50"
      })

    render_hook(view, "save", %{"provider_account" => valid_params})
    {target, _flash} = assert_redirect(view)

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

    track_async_view(view)

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

  defp provider_account_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "provider-account-new-component")
  end

  defp provider_account_fields(vue) do
    form = vue.props["form"]

    Map.values(form["fields"]) ++
      Enum.flat_map(form["connector"]["configuration"]["sections"], & &1["fields"])
  end

  defp provider_account_params(vue, overrides) do
    vue
    |> provider_account_fields()
    |> Map.new(&{&1["key"], &1["value"]})
    |> Map.merge(overrides)
  end
end
