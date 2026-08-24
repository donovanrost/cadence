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
    ProviderAudit,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox
  }

  alias CadenceWeb.ProviderAccountListLive
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test
  alias Phoenix.LiveView.JS

  test "organization administrators can navigate to the account registry" do
    {conn, _user, _organization} = signed_in_organization_admin()

    {:ok, home, _html} = live(conn, ~p"/")

    sidebar = Test.get_vue(home, id: "global-sidebar-navigation")

    provider_accounts =
      Enum.find(
        sidebar.props["presentation"]["navigation"]["items"],
        &(&1["key"] == "provider-accounts")
      )

    assert provider_accounts["attrs"]["id"] == "provider-accounts-nav-link"

    {:ok, view, _html} = live(conn, ~p"/provider-accounts")

    assert has_element?(view, "#provider-account-list-page-component.contents")
    refute has_element?(view, "#provider-accounts-page")
    refute has_element?(view, "#new-provider-account-link")

    vue = Test.get_vue(view, id: "provider-account-list-page-component")

    assert vue.component == "ProviderAccountListPage"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]

    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
    assert vue.streams_diff == [["replace", "/provider_accounts", []]]

    presentation = vue.props["presentation"]

    assert presentation["root"]["attrs"] == %{
             "id" => "provider-accounts-page",
             "class" => "space-y-6"
           }

    assert presentation["header"]["title"]["text"] == "Provider Accounts"
    assert presentation["header"]["title"]["suffix"]["text"] == "0 registered"

    assert presentation["header"]["actions"]["new_account"] == %{
             "attrs" => %{
               "id" => "new-provider-account-link",
               "class" => "btn btn-primary btn-sm gap-1",
               "href" => "/provider-accounts/new",
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push"
             },
             "icon" => %{"attrs" => %{"class" => "hero-plus h-4 w-4"}},
             "text" => "New Account"
           }

    assert presentation["empty_state"]["title"]["text"] == "No provider accounts"

    assert presentation["empty_state"]["action"]["attrs"] == %{
             "class" => "btn btn-primary btn-sm",
             "href" => "/provider-accounts/new",
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push"
           }

    assert presentation["stream"] == %{
             "attrs" => %{
               "id" => "provider-accounts",
               "phx-update" => "stream",
               "class" => "grid gap-4 xl:grid-cols-2"
             },
             "empty_marker" => %{
               "attrs" => %{
                 "id" => "provider-accounts-empty",
                 "class" => "hidden only:block"
               }
             }
           }
  end

  test "streams safe Provider Account card presentation with historical identities" do
    {conn, _user, organization} = signed_in_organization_admin()
    {account, _version, credential} = persist_account!(organization)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts")
    vue = Test.get_vue(view, id: "provider-account-list-page-component")

    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props["presentation"]["header"]["title"]["suffix"]["text"] == "1 registered"
    assert vue.props["presentation"]["empty_state"] == nil

    dom_id = "provider-account-provider-account-#{account.provider_account_id}"

    card = %{
      "__dom_id" => dom_id,
      "id" => "provider-account-#{account.provider_account_id}",
      "display_name" => "Ground Network Simulator",
      "provider_account_id" => account.provider_account_id,
      "status" => "info",
      "status_label" => "Not validated",
      "provider" => "Ground Network Simulator",
      "config" => "v1",
      "credential" => "Active · v1",
      "events" => "Polling",
      "endpoint" => "127.0.0.1 · local",
      "href" => "/provider-accounts/#{account.provider_account_id}"
    }

    assert vue.streams_diff == [
             ["replace", "/provider_accounts", []],
             ["upsert", "/provider_accounts/-", card]
           ]

    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))

    encoded = Jason.encode!(contract)
    refute encoded =~ credential.provider_credential_ref
    refute encoded =~ credential.backend_key
    refute encoded =~ "ephemeral-provider-account-test-secret"
    assert_provider_account_value_has_no_secret_fields(contract)
  end

  test "Provider Account list raw attrs preserve HEEx coercion semantics" do
    assert ProviderAccountListLive.presentation_attrs(%{
             "nil" => nil,
             "false" => false,
             "true" => true,
             "empty" => "",
             "string" => "value",
             "number" => 7
           }) == %{
             "true" => "",
             "empty" => "",
             "string" => "value",
             "number" => "7"
           }
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
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
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

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/new")

    invalid_backend_params =
      provider_account_params(provider_account_new_vue(view), %{
        "provider_type" => "simulator",
        "backend_type" => "inline"
      })

    render_hook(view, "save", %{"provider_account" => invalid_backend_params})
    assert has_element?(view, "#flash-error[role='alert']", "Select a supported secret backend")
    assert ProviderAccounts.list_for_system(organization.organization_id) == []

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/new")

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
    {account, version, credential} = persist_account!(organization)

    previous_opts = Application.get_env(:cadence_web, :provider_account_live_opts)

    Application.put_env(:cadence_web, :provider_account_live_opts,
      manage_backend?: true,
      secret_backend: __MODULE__,
      test_pid: self()
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :provider_account_live_opts, previous_opts)
    end)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")

    track_async_view(view)

    assert has_element?(view, "#provider-account-show-component.contents")
    refute has_element?(view, "#provider-account-show-page")
    refute has_element?(view, "input[type='password']")

    initial_vue = provider_account_show_vue(view)

    assert initial_vue.component == "ProviderAccountShow"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "grant-mission" => JS.push("grant-mission"),
             "revoke-credential" => JS.push("revoke-credential"),
             "revoke-grant" => JS.push("revoke-grant"),
             "rotate-credential" => JS.push("rotate-credential"),
             "validate-account" => JS.push("validate-account")
           }

    assert initial_vue.props == provider_account_show_props(account, version, credential)
    assert_reset_provider_account_stream(initial_vue, "account_grants", [])

    assert_reset_provider_account_stream(
      initial_vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert_provider_account_json_safe(initial_vue, credential)

    render_hook(view, "validate-account", %{})
    assert_receive {:provider_account_secret_backend, :resolve, validate_task}

    validating_vue = provider_account_show_vue(view)

    assert validating_vue.props ==
             provider_account_show_props(account, version, credential, account_action: :validate)

    assert_no_provider_account_stream_mutations(validating_vue)
    send(validate_task, {:continue_provider_account_secret_backend, :resolve})
    render_async(view)

    assert has_element?(view, "#flash-info[role='alert']", "Provider Account validated.")

    assert {:ok, validated_account, ^version} =
             ProviderAccounts.fetch_for_system(
               organization.organization_id,
               account.provider_account_id
             )

    assert {:ok, resolved_credential} =
             ProviderCredentials.fetch(
               organization.organization_id,
               account.provider_account_id,
               credential.provider_credential_ref
             )

    validated_vue = provider_account_show_vue(view)

    assert validated_vue.props ==
             provider_account_show_props(validated_account, version, resolved_credential)

    assert_reset_provider_account_stream(validated_vue, "account_grants", [])

    assert_reset_provider_account_stream(
      validated_vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert_provider_account_json_safe(validated_vue, resolved_credential)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")
    track_async_view(view)

    remounted_validated_vue = provider_account_show_vue(view)

    assert remounted_validated_vue.props ==
             provider_account_show_props(validated_account, version, resolved_credential)

    assert_reset_provider_account_stream(remounted_validated_vue, "account_grants", [])

    render_hook(view, "rotate-credential", %{})
    assert_receive {:provider_account_secret_backend, :rotate, rotate_task}

    rotating_vue = provider_account_show_vue(view)

    assert rotating_vue.props ==
             provider_account_show_props(validated_account, version, resolved_credential,
               account_action: :rotate
             )

    assert_no_provider_account_stream_mutations(rotating_vue)
    send(rotate_task, {:continue_provider_account_secret_backend, :rotate})
    render_async(view)

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Credential rotated without changing its reference."
           )

    assert {:ok, rotated_credential} =
             ProviderCredentials.fetch(
               organization.organization_id,
               account.provider_account_id,
               credential.provider_credential_ref
             )

    assert rotated_credential.provider_credential_ref == credential.provider_credential_ref

    rotated_vue = provider_account_show_vue(view)

    assert rotated_vue.props ==
             provider_account_show_props(validated_account, version, rotated_credential)

    assert_reset_provider_account_stream(rotated_vue, "account_grants", [])

    assert_reset_provider_account_stream(
      rotated_vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert_provider_account_json_safe(rotated_vue, rotated_credential)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")
    track_async_view(view)

    remounted_rotated_vue = provider_account_show_vue(view)

    assert remounted_rotated_vue.props ==
             provider_account_show_props(validated_account, version, rotated_credential)

    assert_reset_provider_account_stream(remounted_rotated_vue, "account_grants", [])

    render_hook(view, "revoke-credential", %{})
    assert_receive {:provider_account_secret_backend, :revoke, revoke_task}

    revoking_vue = provider_account_show_vue(view)

    assert revoking_vue.props ==
             provider_account_show_props(validated_account, version, rotated_credential,
               account_action: :revoke
             )

    assert_no_provider_account_stream_mutations(revoking_vue)
    send(revoke_task, {:continue_provider_account_secret_backend, :revoke})
    render_async(view)

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Credential revoked. New provider operations are blocked."
           )

    assert {:ok, revoked_credential} =
             ProviderCredentials.fetch(
               organization.organization_id,
               account.provider_account_id,
               credential.provider_credential_ref
             )

    revoked_vue = provider_account_show_vue(view)

    assert revoked_vue.props ==
             provider_account_show_props(validated_account, version, revoked_credential)

    assert revoked_vue.props["actions"]["revoke"] == nil
    assert revoked_vue.props["actions"]["validate"]["disabled"] == true
    assert revoked_vue.props["actions"]["rotate"]["disabled"] == true
    assert_reset_provider_account_stream(revoked_vue, "account_grants", [])

    assert_reset_provider_account_stream(
      revoked_vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert_provider_account_json_safe(revoked_vue, revoked_credential)
  end

  test "grants and revokes mission access from the account page" do
    {conn, _user, organization} = signed_in_organization_admin()
    mission = TestFixtures.persist_mission!(organization, display_name: "Aurora")
    {account, version, credential} = persist_account!(organization)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")

    initial_vue = provider_account_show_vue(view)

    assert initial_vue.props ==
             provider_account_show_props(account, version, credential,
               mission_options: [{"Aurora", mission.mission_id}]
             )

    assert initial_vue.props["grant_form"] ==
             provider_account_grant_form_props([{"Aurora", mission.mission_id}])

    assert initial_vue.props["grant_form"]["fields"]["mission_id"]["name"] ==
             "grant[mission_id]"

    assert initial_vue.props["grant_form"]["fields"]["allowed_services"]["name"] ==
             "grant[allowed_services]"

    assert initial_vue.props["grant_form"]["fields"]["allowed_stations"]["name"] ==
             "grant[allowed_stations]"

    assert initial_vue.props["grant_form"]["fields"]["max_quota"]["name"] ==
             "grant[max_quota]"

    assert initial_vue.props["grant_form"]["fields"]["grant_reason"]["name"] ==
             "grant[grant_reason]"

    assert initial_vue.props["actions"]["revoke"]["confirm"] ==
             "Revoke this Provider Account credential? New provider operations will stop."

    assert_reset_provider_account_stream(initial_vue, "account_grants", [])
    assert_provider_account_json_safe(initial_vue, credential)

    grant_payload = %{
      "grant" => %{
        "mission_id" => mission.mission_id,
        "allowed_services" => "telemetry",
        "allowed_stations" => "station-alpha",
        "max_quota" => "20",
        "grant_reason" => "Aurora flight operations"
      }
    }

    assert Enum.sort(Map.keys(grant_payload["grant"])) ==
             ~w(allowed_services allowed_stations grant_reason max_quota mission_id)

    assert Enum.all?(grant_payload["grant"], fn {_field, value} -> is_binary(value) end)
    assert grant_payload["grant"]["max_quota"] == "20"

    render_hook(view, "grant-mission", grant_payload)

    assert has_element?(view, "#flash-info[role='alert']", "Mission grant created.")

    [grant] =
      ProviderAccountGrants.list_for_mission(organization.organization_id, mission.mission_id)

    granted_vue = provider_account_show_vue(view)
    grant_row = provider_account_grant_row(grant, "Aurora")

    assert provider_account_stream_upserts(granted_vue, "account_grants") == [grant_row]

    assert_reset_provider_account_stream(granted_vue, "account_grants", [grant_row])

    assert_reset_provider_account_stream(
      granted_vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert granted_vue.props ==
             provider_account_show_props(account, version, credential, active_grant_count: 1)

    assert grant_row["__dom_id"] == "account-grant-#{grant.provider_account_grant_id}"
    assert grant_row["mission_name"] == "Aurora"
    assert grant_row["version_label"] == "grant v1 · account v1"

    assert grant_row["restriction_summary"] ==
             "Allowed Services: telemetry · Allowed Stations: station-alpha · Max Quota: 20"

    assert grant_row["lifecycle"] == %{"status" => "ready", "label" => "Active"}

    assert grant_row["revoke"] == %{
             "id" => "revoke-grant-#{grant.provider_account_grant_id}",
             "label" => "Revoke",
             "confirm" => "Revoke this mission grant? New operations will stop.",
             "payload" => %{"grant-id" => grant.provider_account_grant_id}
           }

    assert_provider_account_json_safe(granted_vue, credential)

    {:ok, view, _html} = live(conn, ~p"/provider-accounts/#{account.provider_account_id}")
    remounted_granted_vue = provider_account_show_vue(view)

    assert remounted_granted_vue.props ==
             provider_account_show_props(account, version, credential, active_grant_count: 1)

    assert_reset_provider_account_stream(remounted_granted_vue, "account_grants", [grant_row])

    render_hook(view, "revoke-grant", %{"grant-id" => grant.provider_account_grant_id})

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Mission grant revoked. Existing contacts were retained for review."
           )

    assert {:error, :provider_account_grant_revoked} =
             ProviderAccountGrants.fetch_active_for_system(
               organization.organization_id,
               grant.provider_account_grant_id
             )

    [revoked_grant] =
      ProviderAccountGrants.list_for_mission(organization.organization_id, mission.mission_id,
        active_only?: false
      )

    revoked_vue = provider_account_show_vue(view)
    revoked_row = provider_account_grant_row(revoked_grant, "Aurora")

    assert revoked_row["version_label"] == "grant v2 · account v1"
    assert revoked_row["lifecycle"] == %{"status" => "blocked", "label" => "Revoked"}
    assert revoked_row["revoke"] == nil

    assert_reset_provider_account_stream(revoked_vue, "account_grants", [revoked_row])

    assert_reset_provider_account_stream(
      revoked_vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert revoked_vue.props == provider_account_show_props(account, version, credential)

    assert_provider_account_json_safe(revoked_vue, credential)
  end

  test "shows durable cursor health, inbox backlog, and quarantine counts" do
    {conn, _user, organization} = signed_in_organization_admin()
    {account, version, credential} = persist_account!(organization)
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

    vue = provider_account_show_vue(view)

    ingestion = %{
      "id" => "provider-account-ingestion",
      "title" => "Event Ingestion",
      "rows" => [
        detail_props("Mode", "Polling"),
        detail_props("Cursor health", "Healthy", false, "provider-account-ingestion-health"),
        detail_props("Inbox backlog", "1", true, "provider-account-ingestion-backlog"),
        detail_props("Quarantined", "1", true, "provider-account-ingestion-quarantined"),
        detail_props(
          "Last provider event",
          "2026-07-15 20:29Z",
          false,
          "provider-account-ingestion-last-event"
        )
      ],
      "description" => "default/events · last fetched 2026-07-15 20:30Z"
    }

    assert vue.props["ingestion"] == ingestion

    assert vue.props ==
             provider_account_show_props(account, version, credential, ingestion: ingestion)

    assert_reset_provider_account_stream(vue, "account_grants", [])

    assert_reset_provider_account_stream(
      vue,
      "account_audit",
      provider_account_audit_rows(organization, account)
    )

    assert_provider_account_json_safe(vue, credential)
  end

  def capabilities(_opts), do: [:resolve, :rotate, :revoke]

  def resolve(_descriptor, opts), do: await_provider_account_secret_backend(:resolve, opts)
  def rotate(_descriptor, opts), do: await_provider_account_secret_backend(:rotate, opts)
  def revoke(_descriptor, opts), do: await_provider_account_secret_backend(:revoke, opts)

  defp await_provider_account_secret_backend(operation, opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    send(test_pid, {:provider_account_secret_backend, operation, self()})

    receive do
      {:continue_provider_account_secret_backend, ^operation} ->
        case operation do
          :resolve ->
            {:ok,
             %{
               material: %{value: "ephemeral-provider-account-test-secret"},
               backend_version: "test-v1"
             }}

          mutation when mutation in [:rotate, :revoke] ->
            {:ok, %{backend_version: "test-v2"}}
        end
    after
      5_000 -> {:error, :provider_account_secret_backend_timeout}
    end
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

  defp provider_account_show_vue(view) do
    Test.get_vue(view, id: "provider-account-show-component")
  end

  defp provider_account_show_props(account, version, credential, opts \\ []) do
    mission_options = Keyword.get(opts, :mission_options, [])
    account_action = Keyword.get(opts, :account_action)

    %{
      "page" => %{
        "id" => "provider-account-show-page",
        "header" => %{
          "title" => account.display_name,
          "subtitle" => account.provider_account_id,
          "config_label" => "config v#{version.version}",
          "breadcrumbs" => [
            %{"label" => "Provider Accounts", "href" => "/provider-accounts"},
            %{"label" => account.display_name, "href" => nil}
          ]
        },
        "grants" => %{
          "card_id" => "provider-account-grants-card",
          "heading" => "Mission Grants",
          "subtitle" =>
            "Explicit, versioned authorization. Mission restrictions may narrow but never widen organization guardrails.",
          "stream_id" => "provider-account-grants",
          "empty" => %{
            "id" => "provider-account-grants-empty",
            "text" => "No missions have access to this account."
          }
        },
        "grant_form_card" => %{
          "id" => "provider-account-grant-form-card",
          "heading" => "Grant Mission Access",
          "subtitle" =>
            "Start from organization guardrails and optionally narrow the mission scope."
        },
        "audit" => %{
          "card_id" => "provider-account-audit-card",
          "heading" => "Recent Account Activity",
          "subtitle" => "Bounded, append-only account and credential evidence.",
          "stream_id" => "provider-account-audit",
          "empty" => %{
            "id" => "provider-account-audit-empty",
            "text" => "No account activity recorded."
          }
        }
      },
      "actions" => provider_account_action_props(account_action, credential.status),
      "stats" => [
        %{
          "id" => "provider-account-health",
          "label" => "Account Health",
          "value" => provider_account_health(account)
        },
        %{
          "id" => "provider-account-credential-status",
          "label" => "Credential",
          "value" =>
            "#{provider_account_humanize(credential.status)} · v#{credential.registry_version}"
        },
        %{
          "id" => "provider-account-event-mode",
          "label" => "Event Mode",
          "value" => provider_account_humanize(version.event_ingestion_mode)
        },
        %{
          "id" => "provider-account-grant-count",
          "label" => "Mission Grants",
          "value" => Keyword.get(opts, :active_grant_count, 0)
        }
      ],
      "grant_form" => provider_account_grant_form_props(mission_options),
      "configuration" => %{
        "id" => "provider-account-configuration",
        "title" => "Effective Configuration",
        "rows" => [
          detail_props("Provider", provider_account_humanize(version.provider_type)),
          detail_props("Region", version.region_ref || "Not specified", true),
          detail_props("Environment", version.environment_ref, true),
          detail_props("Validated", provider_account_timestamp(account.last_validated_at))
        ]
      },
      "ingestion" => Keyword.get(opts, :ingestion, provider_account_default_ingestion_props()),
      "guardrails" => %{
        "id" => "provider-account-guardrails",
        "title" => "Organization Guardrails",
        "json" => Jason.encode!(version.guardrails, pretty: true)
      },
      "diagnostics" => %{
        "id" => "provider-account-admin-diagnostics",
        "title" => "Admin Diagnostics",
        "columns" => [
          [
            detail_props("API base URL", version.base_url, true),
            detail_props("Client adapter", Atom.to_string(version.client_key), true),
            detail_props(
              "Credential registry version",
              "v#{credential.registry_version}",
              true
            ),
            detail_props("Credential backend", provider_account_humanize(credential.backend_type))
          ],
          [
            detail_props("Account version", "v#{version.version}", true),
            detail_props("Credential status", provider_account_humanize(credential.status)),
            detail_props(
              "Last resolved",
              provider_account_timestamp(credential.last_resolved_at)
            ),
            detail_props("Last rotated", provider_account_timestamp(credential.last_rotated_at))
          ]
        ]
      }
    }
  end

  defp provider_account_action_props(account_action, credential_status) do
    busy? = not is_nil(account_action)
    revoked? = credential_status == :revoked

    %{
      "validate" => %{
        "id" => "validate-provider-account-button",
        "icon" => "hero-shield-check",
        "label" => if(account_action == :validate, do: "Validating…", else: "Validate"),
        "disabled" => busy? or revoked?,
        "payload" => %{}
      },
      "rotate" => %{
        "id" => "rotate-provider-credential-button",
        "icon" => "hero-arrow-path",
        "label" => if(account_action == :rotate, do: "Rotating…", else: "Rotate"),
        "disabled" => busy? or revoked?,
        "payload" => %{}
      },
      "revoke" =>
        if(revoked?,
          do: nil,
          else: %{
            "id" => "revoke-provider-credential-button",
            "label" => "Revoke Credential",
            "confirm" =>
              "Revoke this Provider Account credential? New provider operations will stop.",
            "disabled" => busy?,
            "payload" => %{}
          }
        )
    }
  end

  defp provider_account_grant_form_props(mission_options) do
    values = %{
      "mission_id" => "",
      "allowed_services" => "",
      "allowed_stations" => "",
      "max_quota" => "",
      "grant_reason" => ""
    }

    %{
      "id" => "provider-account-grant-form",
      "values" => values,
      "fields" => %{
        "mission_id" =>
          grant_field_props("mission_id", "select", "Mission", values,
            required: true,
            options:
              Enum.map(mission_options, fn {label, value} ->
                %{"label" => label, "value" => value, "disabled" => false}
              end)
          ),
        "allowed_services" =>
          grant_field_props("allowed_services", "text", "Allowed Services", values,
            placeholder: "telemetry, tracking"
          ),
        "allowed_stations" =>
          grant_field_props("allowed_stations", "text", "Allowed Stations", values,
            placeholder: "station-alpha"
          ),
        "max_quota" => grant_field_props("max_quota", "number", "Maximum Quota", values, min: 0),
        "grant_reason" =>
          grant_field_props("grant_reason", "text", "Grant Reason", values,
            placeholder: "Flight operations authorization"
          )
      },
      "action" => %{"id" => "grant-provider-account-button", "label" => "Grant Access"}
    }
  end

  defp grant_field_props(key, type, label, values, opts) do
    %{
      "key" => key,
      "id" => "grant_#{key}",
      "name" => "grant[#{key}]",
      "type" => type,
      "label" => label,
      "value" => Map.fetch!(values, key),
      "required" => Keyword.get(opts, :required, false),
      "min" => Keyword.get(opts, :min),
      "placeholder" => Keyword.get(opts, :placeholder),
      "options" => Keyword.get(opts, :options, [])
    }
  end

  defp provider_account_default_ingestion_props do
    %{
      "id" => "provider-account-ingestion",
      "title" => "Event Ingestion",
      "rows" => [
        detail_props("Mode", "Polling"),
        detail_props(
          "Cursor health",
          "Not initialized",
          false,
          "provider-account-ingestion-health"
        ),
        detail_props("Inbox backlog", "0", true, "provider-account-ingestion-backlog"),
        detail_props("Quarantined", "0", true, "provider-account-ingestion-quarantined"),
        detail_props(
          "Last provider event",
          "Never",
          false,
          "provider-account-ingestion-last-event"
        )
      ],
      "description" => "The durable cursor will initialize on the first polling cycle."
    }
  end

  defp detail_props(label, value, mono \\ false, wrapper_id \\ nil) do
    %{"label" => label, "value" => value || "—", "mono" => mono, "wrapper_id" => wrapper_id}
  end

  defp provider_account_grant_row(grant, mission_name) do
    %{
      "__dom_id" => "account-grant-#{grant.provider_account_grant_id}",
      "id" => grant.provider_account_grant_id,
      "provider_account_grant_id" => grant.provider_account_grant_id,
      "mission_name" => mission_name,
      "version_label" => "grant v#{grant.version} · account v#{grant.provider_account_version}",
      "restriction_summary" => provider_account_restriction_summary(grant.restrictions),
      "lifecycle" => %{
        "status" => if(grant.lifecycle_state == :active, do: "ready", else: "blocked"),
        "label" => provider_account_humanize(grant.lifecycle_state)
      },
      "revoke" =>
        if(grant.lifecycle_state == :active,
          do: %{
            "id" => "revoke-grant-#{grant.provider_account_grant_id}",
            "label" => "Revoke",
            "confirm" => "Revoke this mission grant? New operations will stop.",
            "payload" => %{"grant-id" => grant.provider_account_grant_id}
          },
          else: nil
        )
    }
  end

  defp provider_account_restriction_summary(restrictions) when map_size(restrictions) == 0,
    do: nil

  defp provider_account_restriction_summary(restrictions) do
    Enum.map_join(restrictions, " · ", fn {key, value} ->
      display = if is_list(value), do: Enum.join(value, ", "), else: to_string(value)
      "#{provider_account_humanize(key)}: #{display}"
    end)
  end

  defp provider_account_audit_rows(organization, account) do
    organization.organization_id
    |> ProviderAudit.list_entries(
      provider_account_id: account.provider_account_id,
      limit: 20
    )
    |> Enum.map(fn entry ->
      %{
        "__dom_id" => "account-audit-#{entry.provider_audit_entry_id}",
        "id" => entry.provider_audit_entry_id,
        "provider_audit_entry_id" => entry.provider_audit_entry_id,
        "recorded_at" => provider_account_timestamp(entry.recorded_at),
        "action" =>
          entry.action |> String.replace("provider_", "") |> provider_account_humanize(),
        "outcome" => %{
          "status" =>
            if(entry.outcome in ["failed", "rejected", "blocked"],
              do: "blocked",
              else: "ready"
            ),
          "label" => entry.outcome
        }
      }
    end)
  end

  defp provider_account_stream_upserts(vue, stream) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", path, _row] -> String.starts_with?(path, "/#{stream}/")
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end

  defp provider_account_stream_mutations(vue, stream) do
    Enum.filter(vue.streams_diff, fn
      [_operation, path | _rest] ->
        path == "/#{stream}" or String.starts_with?(path, "/#{stream}/")

      _operation ->
        false
    end)
  end

  defp assert_reset_provider_account_stream(vue, stream, rows) do
    assert provider_account_stream_mutations(vue, stream) ==
             [["replace", "/#{stream}", []]] ++
               Enum.map(rows, &["upsert", "/#{stream}/-", &1])
  end

  defp assert_no_provider_account_stream_mutations(vue) do
    assert provider_account_stream_mutations(vue, "account_grants") == []
    assert provider_account_stream_mutations(vue, "account_audit") == []
  end

  defp assert_provider_account_json_safe(vue, credential) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))

    encoded = Jason.encode!(contract)
    refute encoded =~ credential.provider_credential_ref
    refute encoded =~ credential.backend_key
    refute encoded =~ "ephemeral-provider-account-test-secret"
    assert_provider_account_value_has_no_secret_fields(contract)
  end

  defp assert_provider_account_value_has_no_secret_fields(value) when is_map(value) do
    Enum.each(value, fn {key, nested} ->
      key = to_string(key)

      refute key in [
               "secret",
               "secret_material",
               "password",
               "password_confirmation",
               "backend_key",
               "credential_ref",
               "provider_credential_ref",
               "material"
             ]

      if key == "type", do: refute(nested == "password")

      if key == "name" and is_binary(nested) do
        refute String.contains?(nested, ["secret", "password"])
      end

      assert_provider_account_value_has_no_secret_fields(nested)
    end)
  end

  defp assert_provider_account_value_has_no_secret_fields(value) when is_list(value),
    do: Enum.each(value, &assert_provider_account_value_has_no_secret_fields/1)

  defp assert_provider_account_value_has_no_secret_fields(_value), do: :ok

  defp provider_account_health(%{credential_status: :revoked}), do: "Blocked"
  defp provider_account_health(%{last_validated_at: %DateTime{}}), do: "Validated"
  defp provider_account_health(_account), do: "Not validated"

  defp provider_account_humanize(value) when is_atom(value),
    do: value |> Atom.to_string() |> provider_account_humanize()

  defp provider_account_humanize(value) when is_binary(value) do
    value
    |> String.replace(["_", "."], " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp provider_account_timestamp(nil), do: "Never"

  defp provider_account_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")

  defp provider_account_new_vue(view) do
    Test.get_vue(view, id: "provider-account-new-component")
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
