defmodule CadenceWeb.CommsProviderLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config
  @async_timeout 1_000

  import CadenceWeb.AsyncLiveViewTestSupport,
    only: [render_async: 2, track_async_view: 1]

  import Phoenix.LiveViewTest, except: [render_async: 1, render_async: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias CadenceWeb.TestFixtures

  test "lists mission providers and exposes the mission-scoped setup path" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

    assert has_element?(view, "#comms-providers-page")
    assert has_element?(view, "#new-provider-link")
    assert has_element?(view, "#comms-providers-page", "No ground network providers")
  end

  test "creates a simulator provider using references rather than transport or secret fields" do
    {conn, organization, mission} = signed_in_org_and_mission()

    {:ok, empty_view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    empty_vue = comms_provider_new_vue(empty_view)

    assert empty_vue.component == "CommsProviderNew"
    assert empty_vue.class == "max-w-3xl space-y-6"
    assert empty_vue.ssr == false
    assert empty_vue.props == Jason.decode!(Jason.encode!(empty_vue.props))

    assert empty_vue.handlers == %{
             "save" => Phoenix.LiveView.JS.push("save"),
             "validate" => Phoenix.LiveView.JS.push("validate")
           }

    assert empty_vue.props["accounts"] == %{
             "empty" => true,
             "options" => [],
             "selected" => nil,
             "empty_state" => %{
               "id" => "mission-provider-no-grants",
               "heading" => "This mission has no Provider Account grants.",
               "message" =>
                 "An organization administrator must grant an account before mission setup can continue.",
               "action" => %{
                 "id" => "open-provider-accounts-link",
                 "label" => "Open Provider Accounts",
                 "href" => "/provider-accounts"
               }
             }
           }

    assert empty_vue.props["form"]["fields"]["provider_account_grant_id"]["value"] == ""

    {account, version, grant} =
      persist_provider_account_and_grant!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    assert has_element?(view, "#comms-provider-new-component")

    vue = comms_provider_new_vue(view)

    assert vue.component == "CommsProviderNew"
    assert vue.class == "max-w-3xl space-y-6"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.handlers == %{
             "save" => Phoenix.LiveView.JS.push("save"),
             "validate" => Phoenix.LiveView.JS.push("validate")
           }

    assert Map.keys(vue.props) |> Enum.sort() == ["accounts", "form", "notes", "page"]

    assert vue.props["page"] == %{
             "id" => "comms-provider-new-page",
             "title" => "New Mission Provider",
             "subtitle" =>
               "Bind an organization-approved ground network account and define this mission's delivery tolerances.",
             "breadcrumbs" => [
               %{
                 "label" => mission.display_name,
                 "href" => "/missions/#{mission.mission_id}"
               },
               %{
                 "label" => "Comms",
                 "href" => "/missions/#{mission.mission_id}/comms"
               },
               %{
                 "label" => "Providers",
                 "href" => "/missions/#{mission.mission_id}/comms/providers"
               },
               %{"label" => "New", "href" => nil}
             ]
           }

    option = %{
      "label" => "Ground Network Simulator · account v#{version.version} · grant v#{grant.version}",
      "value" => grant.provider_account_grant_id
    }

    assert vue.props["accounts"] == %{
             "empty" => false,
             "options" => [option],
             "selected" => %{
               "id" => "mission-provider-account-summary",
               "ownership_label" => "Organization-owned configuration",
               "display_name" => "Ground Network Simulator",
               "version_label" => "account v#{version.version} · grant v#{grant.version}",
               "badge" => %{"status" => "ready", "label" => "Granted"},
               "restrictions" => [
                 %{
                   "label" => "Account Guardrails",
                   "summary" =>
                     "Allowed services: telemetry, tracking · Allowed stations: station-alpha, station-beta"
                 },
                 %{
                   "label" => "Mission Restrictions",
                   "summary" => "Allowed stations: station-alpha"
                 }
               ]
             },
             "empty_state" => %{
               "id" => "mission-provider-no-grants",
               "heading" => "This mission has no Provider Account grants.",
               "message" =>
                 "An organization administrator must grant an account before mission setup can continue.",
               "action" => %{
                 "id" => "open-provider-accounts-link",
                 "label" => "Open Provider Accounts",
                 "href" => "/provider-accounts"
               }
             }
           }

    assert vue.props["notes"] == %{
             "secret_boundary" => %{
               "id" => "mission-provider-secret-boundary-note",
               "text" =>
                 "Provider endpoint, credential, and environment values remain organization-owned and are never exposed to this mission form."
             },
             "resource_boundary" => %{
               "id" => "mission-provider-resource-guardrail-note",
               "text" =>
                 "Leave blank to inherit the grant. Any listed resources must be inside both the account guardrails and the mission grant."
             }
           }

    form_dto = vue.props["form"]

    assert form_dto["id"] == "mission-provider-form"

    assert form_dto["sections"] == %{
             "binding" => %{
               "id" => "mission-provider-binding-section",
               "number" => "01",
               "title" => "Mission Binding",
               "field_keys" => ["display_name", "provider_account_grant_id"]
             },
             "resource_scope" => %{
               "id" => "mission-provider-resource-scope-section",
               "number" => "02",
               "title" => "Mission Resource Scope",
               "field_keys" => ["permitted_resource_refs"]
             },
             "delivery_policy" => %{
               "id" => "mission-provider-delivery-policy-section",
               "number" => "03",
               "title" => "Delivery Change Policy",
               "field_keys" => ["policy_mode", "deadline_behavior"]
             }
           }

    assert form_dto["conditional"] == %{
             "approval_guidance" => %{
               "id" => "mission-provider-approval-policy-guidance",
               "active" => true,
               "visible_when" => %{
                 "field" => "policy_mode",
                 "equals" => "approval_required"
               },
               "text" =>
                 "Provider facts are still recorded immediately, but actionable schedule or resource changes wait for an authorized operator decision."
             },
             "bounded_policy" => %{
               "id" => "mission-provider-bounded-policy-fields",
               "active" => false,
               "visible_when" => %{
                 "field" => "policy_mode",
                 "equals" => "bounded_automatic"
               },
               "field_keys" => [
                 "maximum_earlier_start_shift_seconds",
                 "maximum_later_start_shift_seconds",
                 "maximum_earlier_end_shift_seconds",
                 "maximum_later_end_shift_seconds",
                 "minimum_retained_duration_seconds",
                 "approved_station_substitutions"
               ]
             }
           }

    assert form_dto["actions"] == %{
             "submit" => %{
               "id" => "create-mission-provider-button",
               "label" => "Create Mission Provider"
             },
             "cancel" => %{
               "id" => "cancel-mission-provider-link",
               "label" => "Cancel",
               "href" => "/missions/#{mission.mission_id}/comms/providers"
             }
           }

    fields = form_dto["fields"]

    assert Map.keys(fields) |> Enum.sort() ==
             Enum.sort([
               "display_name",
               "provider_account_grant_id",
               "permitted_resource_refs",
               "policy_mode",
               "maximum_earlier_start_shift_seconds",
               "maximum_later_start_shift_seconds",
               "maximum_earlier_end_shift_seconds",
               "maximum_later_end_shift_seconds",
               "minimum_retained_duration_seconds",
               "approved_station_substitutions",
               "deadline_behavior"
             ])

    assert_provider_field(fields, "display_name", %{
      "type" => "text",
      "label" => "Display Name",
      "required" => true,
      "value" => "Ground Network Simulator"
    })

    assert_provider_field(fields, "provider_account_grant_id", %{
      "type" => "select",
      "label" => "Granted Provider Account",
      "required" => true,
      "options" => [option],
      "value" => grant.provider_account_grant_id
    })

    assert_provider_field(fields, "permitted_resource_refs", %{
      "type" => "text",
      "label" => "Permitted Stations or Service Pools",
      "placeholder" => "station-alpha, station-beta"
    })

    assert_provider_field(fields, "policy_mode", %{
      "type" => "select",
      "label" => "Material Change Handling",
      "required" => true,
      "options" => [
        %{
          "label" => "Require approval for every material change",
          "value" => "approval_required"
        },
        %{
          "label" => "Automatically accept changes within limits",
          "value" => "bounded_automatic"
        }
      ],
      "value" => "approval_required"
    })

    assert_provider_field(fields, "maximum_earlier_start_shift_seconds", %{
      "type" => "number",
      "label" => "Max Earlier Start Shift (seconds)",
      "min" => 0,
      "value" => "0"
    })

    assert_provider_field(fields, "maximum_later_start_shift_seconds", %{
      "type" => "number",
      "label" => "Max Later Start Shift (seconds)",
      "min" => 0,
      "value" => "0"
    })

    assert_provider_field(fields, "maximum_earlier_end_shift_seconds", %{
      "type" => "number",
      "label" => "Max Earlier End Shift (seconds)",
      "min" => 0,
      "value" => "0"
    })

    assert_provider_field(fields, "maximum_later_end_shift_seconds", %{
      "type" => "number",
      "label" => "Max Later End Shift (seconds)",
      "min" => 0,
      "value" => "0"
    })

    assert_provider_field(fields, "minimum_retained_duration_seconds", %{
      "type" => "number",
      "label" => "Minimum Retained Duration (seconds)",
      "min" => 1
    })

    assert_provider_field(fields, "approved_station_substitutions", %{
      "type" => "text",
      "label" => "Approved Station Substitutions",
      "placeholder" => "station-alpha, station-beta"
    })

    assert_provider_field(fields, "deadline_behavior", %{
      "type" => "select",
      "label" => "No-response Deadline Behavior",
      "required" => true,
      "options" => [
        %{
          "label" => "Retain last accepted schedule",
          "value" => "retain_last_accepted"
        },
        %{"label" => "Cancel if still actionable", "value" => "cancel_if_actionable"}
      ],
      "value" => "retain_last_accepted"
    })

    encoded_props = Jason.encode!(vue.props)
    refute encoded_props =~ account.provider_account_id
    refute encoded_props =~ version.base_url
    refute encoded_props =~ version.credential_ref
    refute encoded_props =~ version.environment_ref

    render_hook(view, "save", %{
      "provider" =>
        provider_params(vue, %{
          "display_name" => "Local Ground Network",
          "permitted_resource_refs" => "station-alpha"
        })
    })

    {target, _flash} = assert_redirect(view)

    [provider] =
      GroundNetworks.list_providers(organization.organization_id, mission.mission_id)

    assert provider.display_name == "Local Ground Network"
    assert provider.provider_type == :simulator
    assert provider.client_key == :simulator_http
    assert provider.provider_account_id == account.provider_account_id
    assert provider.provider_account_version == version.version
    assert provider.provider_account_grant_id == grant.provider_account_grant_id
    assert provider.provider_account_grant_version == grant.version
    assert provider.base_url == version.base_url
    assert provider.credential_ref == version.credential_ref
    assert provider.environment_ref == version.environment_ref
    assert provider.permitted_resource_refs == ["station-alpha"]

    assert provider.delivery_policy_document == %{
             "mode" => "approval_required",
             "changes_always_requiring_approval" => [
               "schedule",
               "resource",
               "capacity",
               "cost"
             ],
             "deadline_behavior" => "retain_last_accepted"
           }

    assert target == ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
  end

  test "validates and synchronizes provider profiles without materializing Cadence spacecraft" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)

    assert Cadence.SpacecraftStore.list_spacecraft(
             organization.organization_id,
             mission.mission_id
           ) == []

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
      )

    track_async_view(view)

    assert has_element?(view, "#comms-provider-show-page")
    assert has_element?(view, "#simulated-provider-badge")
    assert has_element?(view, "#provider-control-plane-health", "Not validated")
    assert has_element?(view, "#validate-provider-button")
    assert has_element?(view, "#sync-provider-button")
    assert has_element?(view, "#provider-admin-diagnostics")
    assert has_element?(view, "#provider-admin-diagnostics-json")

    view |> element("#validate-provider-button") |> render_click()
    render_async(view, @async_timeout)

    assert has_element?(view, "#provider-control-plane-health", "Healthy")
    assert has_element?(view, "#provider-capabilities")

    view |> element("#sync-provider-button") |> render_click()
    render_async(view, @async_timeout)

    assert has_element?(view, "#service-profile-service-realtime-ttc-downlink")
    assert has_element?(view, "#delivery-profile-delivery-cadence-primary")
    assert has_element?(view, "#provider-service-profile-count", "1")
    assert has_element?(view, "#provider-delivery-profile-count", "1")

    assert Cadence.SpacecraftStore.list_spacecraft(
             organization.organization_id,
             mission.mission_id
           ) == []
  end

  test "progressively renders delivery limits and rejects mission resource widening" do
    {conn, organization, mission} = signed_in_org_and_mission()

    {_account, _version, grant} =
      persist_provider_account_and_grant!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    vue = comms_provider_new_vue(view)
    conditional = vue.props["form"]["conditional"]

    assert conditional["approval_guidance"]["active"] == true
    assert conditional["bounded_policy"]["active"] == false

    bounded_params =
      provider_params(vue, %{
        "display_name" => "Bounded Simulator",
        "provider_account_grant_id" => grant.provider_account_grant_id,
        "permitted_resource_refs" => "station-alpha",
        "policy_mode" => "bounded_automatic",
        "maximum_earlier_start_shift_seconds" => "0",
        "maximum_later_start_shift_seconds" => "60",
        "maximum_earlier_end_shift_seconds" => "0",
        "maximum_later_end_shift_seconds" => "60",
        "minimum_retained_duration_seconds" => "300",
        "approved_station_substitutions" => "station-alpha",
        "deadline_behavior" => "retain_last_accepted"
      })

    render_hook(view, "validate", %{"provider" => bounded_params})

    validated_vue = comms_provider_new_vue(view)
    validated_form = validated_vue.props["form"]

    assert validated_form["conditional"]["approval_guidance"]["active"] == false
    assert validated_form["conditional"]["bounded_policy"]["active"] == true
    assert provider_values(validated_vue) == bounded_params

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "provider_account_grant_id", "ungranted")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Select a Provider Account granted to this mission."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "display_name", "   ")
    })

    assert has_element?(view, "#flash-error[role='alert']", "Display name is required.")
    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "policy_mode", "unrecognized")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Select a delivery change policy."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    render_hook(view, "save", %{
      "provider" =>
        Map.put(bounded_params, "maximum_later_start_shift_seconds", "not-a-number")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Delivery policy limits must be non-negative whole numbers."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "permitted_resource_refs", "station-beta")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Permitted resources must stay within the Provider Account grant."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    render_hook(view, "save", %{"provider" => bounded_params})

    {target, _flash} = assert_redirect(view)

    [provider] =
      GroundNetworks.list_providers(organization.organization_id, mission.mission_id)

    assert target == ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
    assert provider.permitted_resource_refs == ["station-alpha"]

    assert provider.delivery_policy_document == %{
             "mode" => "bounded_automatic",
             "maximum_earlier_start_shift_seconds" => 0,
             "maximum_later_start_shift_seconds" => 60,
             "maximum_earlier_end_shift_seconds" => 0,
             "maximum_later_end_shift_seconds" => 60,
             "minimum_retained_duration_seconds" => 300,
             "approved_station_substitutions" => ["station-alpha"],
             "deadline_behavior" => "retain_last_accepted"
           }
  end

  test "archives a provider from its show page" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
      )

    assert {:error, {:live_redirect, %{to: target}}} =
             view |> element("#archive-provider-button") |> render_click()

    assert target == ~p"/missions/#{mission.mission_id}/comms/providers"

    assert GroundNetworks.list_providers(
             organization.organization_id,
             mission.mission_id
           ) == []
  end

  defp comms_provider_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "comms-provider-new-component")
  end

  defp provider_params(vue, overrides) do
    vue
    |> provider_values()
    |> Map.merge(overrides)
  end

  defp provider_values(vue) do
    Map.new(vue.props["form"]["fields"], fn {key, field} -> {key, field["value"]} end)
  end

  defp assert_provider_field(fields, key, expected) do
    defaults = %{
      "key" => key,
      "id" => "provider_#{key}",
      "name" => "provider[#{key}]",
      "required" => false,
      "placeholder" => nil,
      "min" => nil,
      "options" => [],
      "value" => ""
    }

    assert Map.fetch!(fields, key) == Map.merge(defaults, expected)
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()

    _membership =
      TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "provider-mission",
        display_name: "Provider Mission"
      )

    {TestFixtures.member_conn(user), organization, mission}
  end

  defp persist_provider!(organization_id, mission_id) do
    {account, account_version, grant} =
      persist_provider_account_and_grant!(organization_id, mission_id)

    provider =
      MissionProvider.new(%{
        mission_id: mission_id,
        display_name: "Ground Network Simulator",
        provider_account_id: account.provider_account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        provider_type: account_version.provider_type,
        client_key: account_version.client_key,
        base_url: account_version.base_url,
        credential_ref: account_version.credential_ref,
        environment_ref: account_version.environment_ref
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp persist_provider_account_and_grant!(organization_id, mission_id) do
    suffix = System.unique_integer([:positive])
    account_id = "provider-account-comms-#{suffix}"
    credential_ref = "provider-credential-comms-#{suffix}"
    now = ~U[2026-07-15 21:00:00.000000Z]

    {:ok, _credential} =
      ProviderCredentials.create(
        organization_id,
        account_id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "providers/comms/#{suffix}",
          registered_at: now
        },
        manage_backend?: false,
        now: now
      )

    {:ok, account, version} =
      ProviderAccounts.create_for_system(
        organization_id,
        %{
          provider_account_id: account_id,
          display_name: "Ground Network Simulator",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          region_ref: "local",
          environment_ref: "local-demo",
          credential_ref: credential_ref,
          guardrails: %{
            "allowed_services" => ["telemetry", "tracking"],
            "allowed_stations" => ["station-alpha", "station-beta"]
          }
        },
        %{"kind" => "system", "id" => "comms-provider-live-test"},
        validate_credential?: false,
        now: now
      )

    {:ok, grant} =
      ProviderAccountGrants.grant_for_system(
        organization_id,
        mission_id,
        account_id,
        %{restrictions: %{"allowed_stations" => ["station-alpha"]}},
        %{"kind" => "system", "id" => "comms-provider-live-test"},
        now: now
      )

    {account, version, grant}
  end
end
