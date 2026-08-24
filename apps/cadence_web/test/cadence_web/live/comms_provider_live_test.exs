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

  alias CadenceWeb.{CommsProviderListLive, TestFixtures}
  alias Phoenix.LiveView.JS

  test "lists mission providers and exposes the mission-scoped setup path" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

    presentation = comms_provider_list_presentation(view)

    assert presentation["root"]["attrs"]["id"] == "comms-providers-page"

    assert presentation["header"]["actions"]["new_provider"]["attrs"]["id"] ==
             "new-provider-link"

    assert presentation["empty_state"]["title"]["text"] == "No ground network providers"
  end

  describe "provider list presentation" do
    test "projects the complete empty page through one JSON-safe non-SSR parent" do
      {conn, _organization, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

      vue = LiveVue.Test.get_vue(view, id: "comms-provider-list-component")
      assert vue.component == "CommsProviderList"
      assert vue.class == "contents"
      refute vue.ssr
      assert Map.keys(vue.props) == ["presentation"]

      presentation = vue.props["presentation"]
      assert presentation == Jason.decode!(Jason.encode!(presentation))

      assert presentation["root"] == %{
               "attrs" => %{"class" => "space-y-6", "id" => "comms-providers-page"}
             }

      header = presentation["header"]

      assert header["attrs"] == %{"class" => "border-b border-primary/20 pb-4"}

      assert header["body"] == %{
               "attrs" => %{"class" => "flex items-end justify-between gap-4"}
             }

      assert header["content"] == %{"attrs" => %{}}

      assert header["title"] == %{
               "attrs" => %{
                 "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
               },
               "text" => "Ground Network Providers",
               "suffix" => %{
                 "attrs" => %{
                   "class" => "ml-3 font-mono text-base text-base-content/60"
                 },
                 "text" => "0 configured"
               }
             }

      assert header["subtitle"] == %{
               "attrs" => %{
                 "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
               },
               "text" =>
                 "Provider control planes for scheduling, inventory discovery, and delivery profile negotiation."
             }

      assert header["breadcrumbs"]["attrs"] == %{
               "aria-label" => "Breadcrumb",
               "class" =>
                 "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
             }

      assert Enum.map(header["breadcrumbs"]["items"], fn item ->
               (item["link"] && item["link"]["text"]) || item["current"]["text"]
             end) == [mission.display_name, "Comms", "Providers"]

      assert Enum.map(header["breadcrumbs"]["items"], fn item ->
               item["link"] && item["link"]["attrs"]["href"]
             end) == [
               "/missions/#{mission.mission_id}",
               "/missions/#{mission.mission_id}/comms",
               nil
             ]

      assert header["actions"] == %{
               "attrs" => %{"class" => "flex items-center gap-2"},
               "new_provider" => %{
                 "attrs" => %{
                   "class" => "btn btn-primary btn-sm gap-1",
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/missions/#{mission.mission_id}/comms/providers/new",
                   "id" => "new-provider-link"
                 },
                 "icon" => %{"attrs" => %{"class" => "hero-plus h-4 w-4"}},
                 "text" => "New Provider"
               }
             }

      assert presentation["empty_state"] == %{
               "attrs" => %{
                 "class" =>
                   "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
               },
               "title" => %{
                 "attrs" => %{"class" => "hud-label"},
                 "text" => "No ground network providers"
               },
               "description" => %{
                 "attrs" => %{
                   "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
                 },
                 "text" =>
                   "Connect this mission to a simulator or commercial ground network control plane."
               },
               "action_container" => %{"attrs" => %{"class" => "mt-5"}},
               "action" => %{
                 "attrs" => %{
                   "class" => "btn btn-primary btn-sm",
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/missions/#{mission.mission_id}/comms/providers/new"
                 },
                 "icon" => %{
                   "attrs" => %{"class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"}
                 },
                 "text" => "Configure the first provider"
               }
             }

      assert presentation["card"] == nil
    end

    test "keeps the existing child row props and derived provider decisions server-owned" do
      {conn, organization, mission} = signed_in_org_and_mission()
      provider = persist_provider!(organization.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")
      presentation = comms_provider_list_presentation(view)

      assert presentation["header"]["title"]["suffix"]["text"] == "1 configured"
      assert presentation["empty_state"] == nil

      assert presentation["card"] == %{
               "attrs" => %{
                 "class" => "card bg-base-200 border border-base-300"
               },
               "body" => %{"attrs" => %{"class" => "card-body p-0"}},
               "table_component" => %{
                 "attrs" => %{"id" => "mission-providers-table-component"}
               },
               "rows" => [
                 %{
                   "id" => "mission-provider-#{provider.provider_id}",
                   "display_name" => provider.display_name,
                   "provider_type" => "Simulated",
                   "server_url" => provider.base_url,
                   "status" => "blocked",
                   "status_label" => "Not validated",
                   "account_binding" =>
                     "#{provider.provider_account_id} · v#{provider.provider_account_version}",
                   "grant_binding" =>
                     "#{provider.provider_account_grant_id} · v#{provider.provider_account_grant_version}",
                   "last_synced_at" => "Never",
                   "version" => "v#{provider.version}",
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
                 }
               ]
             }
    end

    test "raw attrs preserve HEEx nil, false, true, string, and number semantics" do
      attrs =
        CommsProviderListLive.presentation_attrs(%{
          "nil" => nil,
          "false" => false,
          "true" => true,
          "string" => "retained",
          "number" => 7
        })

      assert attrs == %{
               "true" => "",
               "string" => "retained",
               "number" => "7"
             }
    end
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
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
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
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
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
      "label" =>
        "Ground Network Simulator · account v#{version.version} · grant v#{grant.version}",
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
    test_process = self()

    previous_provider_opts =
      Application.get_env(:cadence_web, :ground_network_provider_live_opts, [])

    Application.put_env(
      :cadence_web,
      :ground_network_provider_live_opts,
      previous_provider_opts
      |> Keyword.put(:validate_response, fn ->
        send(test_process, {:validate_provider_started, self()})

        receive do
          :finish_validate_provider -> {:ok, %{"state" => "running"}}
        after
          @async_timeout * 2 -> {:ok, %{"state" => "running"}}
        end
      end)
      |> Keyword.put(:spacecraft_response, fn ->
        send(test_process, {:sync_provider_started, self()})

        receive do
          :finish_sync_provider -> {:ok, []}
        after
          @async_timeout * 2 -> {:ok, []}
        end
      end)
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :ground_network_provider_live_opts,
        previous_provider_opts
      )
    end)

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

    assert has_element?(view, "#comms-provider-show-component.contents")
    refute has_element?(view, "#comms-provider-show-page")

    initial_vue = comms_provider_show_vue(view)

    assert initial_vue.component == "CommsProviderShow"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "archive-provider" => JS.push("archive-provider"),
             "sync-provider" => JS.push("sync-provider"),
             "validate-provider" => JS.push("validate-provider")
           }

    assert initial_vue.props ==
             comms_provider_show_props(mission, provider,
               service_profiles_empty?: true,
               delivery_profiles_empty?: true
             )

    assert initial_vue.props["provider"]["page_id"] == "comms-provider-show-page"

    assert initial_vue.props["provider"]["simulated_badge"]["id"] ==
             "simulated-provider-badge"

    assert provider_summary_value(initial_vue, "provider-control-plane-health") ==
             "Not validated"

    assert initial_vue.props["actions"]["validate"]["id"] == "validate-provider-button"
    assert initial_vue.props["actions"]["sync"]["id"] == "sync-provider-button"
    assert initial_vue.props["diagnostics"]["id"] == "provider-admin-diagnostics"

    assert initial_vue.props["diagnostics"]["json_id"] ==
             "provider-admin-diagnostics-json"

    assert provider_stream_mutations(initial_vue) == [
             ["replace", "/service_profiles", []],
             ["replace", "/delivery_profiles", []],
             ["replace", "/provider_versions", []],
             ["upsert", "/provider_versions/-", provider_version_row(provider)]
           ]

    assert_json_safe_show(initial_vue)
    refute_show_secrets(initial_vue, provider)

    render_hook(view, "validate-provider", %{})
    assert_receive {:validate_provider_started, validate_provider_pid}, @async_timeout

    validating_vue = comms_provider_show_vue(view)
    assert validating_vue.props["actions"] == provider_actions_props(:validate)
    assert provider_stream_mutations(validating_vue) == []
    assert_json_safe_show(validating_vue)

    send(validate_provider_pid, :finish_validate_provider)
    render_async(view, @async_timeout)

    assert has_element?(view, "#flash-info", "Provider control plane validated.")

    {:ok, validated_provider} =
      GroundNetworks.fetch_provider(
        organization.organization_id,
        mission.mission_id,
        provider.provider_id
      )

    validated_vue = comms_provider_show_vue(view)

    assert validated_vue.props ==
             comms_provider_show_props(mission, validated_provider,
               service_profiles_empty?: true,
               delivery_profiles_empty?: true
             )

    assert provider_summary_value(validated_vue, "provider-control-plane-health") == "Healthy"
    assert validated_vue.props["details"]["capabilities"]["id"] == "provider-capabilities"
    assert validated_vue.props["actions"] == provider_actions_props()

    assert provider_stream_mutations(validated_vue) == [
             ["replace", "/service_profiles", []],
             ["replace", "/delivery_profiles", []],
             ["replace", "/provider_versions", []],
             ["upsert", "/provider_versions/-", provider_version_row(validated_provider)]
           ]

    assert_json_safe_show(validated_vue)
    refute_show_secrets(validated_vue, validated_provider)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
      )

    track_async_view(view)

    render_hook(view, "sync-provider", %{})
    assert_receive {:sync_provider_started, sync_provider_pid}, @async_timeout

    syncing_vue = comms_provider_show_vue(view)
    assert syncing_vue.props["actions"] == provider_actions_props(:sync)
    assert provider_stream_mutations(syncing_vue) == []
    assert_json_safe_show(syncing_vue)

    send(sync_provider_pid, :finish_sync_provider)
    render_async(view, @async_timeout)

    assert has_element?(
             view,
             "#flash-info",
             "Provider inventory and profiles synchronized."
           )

    {:ok, synced_provider} =
      GroundNetworks.fetch_provider(
        organization.organization_id,
        mission.mission_id,
        provider.provider_id
      )

    synced_vue = comms_provider_show_vue(view)
    service_profile = service_profile_row()
    delivery_profile = delivery_profile_row()

    assert synced_vue.props ==
             comms_provider_show_props(mission, synced_provider,
               service_profiles_empty?: false,
               delivery_profiles_empty?: false
             )

    assert provider_stream_mutations(synced_vue) == [
             ["replace", "/service_profiles", []],
             ["upsert", "/service_profiles/-", service_profile],
             ["replace", "/delivery_profiles", []],
             ["upsert", "/delivery_profiles/-", delivery_profile],
             ["replace", "/provider_versions", []],
             ["upsert", "/provider_versions/-", provider_version_row(synced_provider)]
           ]

    assert service_profile["__dom_id"] ==
             "service-profile-service-realtime-ttc-downlink"

    assert delivery_profile["__dom_id"] ==
             "delivery-profile-delivery-cadence-primary"

    assert provider_summary_value(synced_vue, "provider-service-profile-count") == 1
    assert provider_summary_value(synced_vue, "provider-delivery-profile-count") == 1
    assert synced_vue.props["actions"] == provider_actions_props()
    assert_json_safe_show(synced_vue)
    refute_show_secrets(synced_vue, synced_provider)

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

    view = provider_new_view!(conn, mission)

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "display_name", "   ")
    })

    assert has_element?(view, "#flash-error[role='alert']", "Display name is required.")
    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    view = provider_new_view!(conn, mission)

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "policy_mode", "unrecognized")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Select a delivery change policy."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    view = provider_new_view!(conn, mission)

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "maximum_later_start_shift_seconds", "not-a-number")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Delivery policy limits must be non-negative whole numbers."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    view = provider_new_view!(conn, mission)

    render_hook(view, "save", %{
      "provider" => Map.put(bounded_params, "permitted_resource_refs", "station-beta")
    })

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Permitted resources must stay within the Provider Account grant."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []

    view = provider_new_view!(conn, mission)
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

    vue = comms_provider_show_vue(view)

    assert vue.component == "CommsProviderShow"
    assert vue.class == "contents"
    assert vue.ssr == false

    assert vue.handlers == %{
             "archive-provider" => JS.push("archive-provider"),
             "sync-provider" => JS.push("sync-provider"),
             "validate-provider" => JS.push("validate-provider")
           }

    assert vue.props ==
             comms_provider_show_props(mission, provider,
               service_profiles_empty?: true,
               delivery_profiles_empty?: true
             )

    assert vue.props["actions"]["archive"] == %{
             "id" => "archive-provider-button",
             "label" => "Archive",
             "confirm" => "Archive this ground network provider?",
             "disabled" => false
           }

    assert_json_safe_show(vue)

    assert {:error, {:live_redirect, %{to: target}}} =
             render_hook(view, "archive-provider", %{})

    assert target == ~p"/missions/#{mission.mission_id}/comms/providers"

    {^target, flash} = assert_redirect(view)
    assert flash["info"] == "Ground network provider archived."

    assert GroundNetworks.list_providers(
             organization.organization_id,
             mission.mission_id
           ) == []
  end

  defp comms_provider_show_vue(view) do
    LiveVue.Test.get_vue(view, id: "comms-provider-show-component")
  end

  defp comms_provider_show_props(mission, provider, opts) do
    service_profiles_empty? = Keyword.fetch!(opts, :service_profiles_empty?)
    delivery_profiles_empty? = Keyword.fetch!(opts, :delivery_profiles_empty?)

    %{
      "navigation" => provider_navigation_props(mission, provider),
      "provider" =>
        provider_show_props(
          provider,
          if(service_profiles_empty?, do: 0, else: 1),
          if(delivery_profiles_empty?, do: 0, else: 1)
        ),
      "actions" => provider_actions_props(),
      "profiles" => provider_profiles_props(service_profiles_empty?, delivery_profiles_empty?),
      "details" => provider_details_props(provider),
      "diagnostics" => provider_diagnostics_props(provider)
    }
  end

  defp provider_navigation_props(mission, provider) do
    %{
      "breadcrumbs" => [
        %{"label" => mission.display_name, "href" => "/missions/#{mission.mission_id}"},
        %{"label" => "Comms", "href" => "/missions/#{mission.mission_id}/comms"},
        %{
          "label" => "Providers",
          "href" => "/missions/#{mission.mission_id}/comms/providers"
        },
        %{"label" => provider.display_name, "href" => nil}
      ]
    }
  end

  defp provider_show_props(provider, service_profile_count, delivery_profile_count) do
    %{
      "page_id" => "comms-provider-show-page",
      "display_name" => provider.display_name,
      "provider_id" => provider.provider_id,
      "simulated_badge" => %{"id" => "simulated-provider-badge", "label" => "Simulated"},
      "version" => "v#{provider.version}",
      "summary_tiles" => [
        %{
          "id" => "provider-control-plane-health",
          "label" => "Control Plane",
          "value" => provider_control_plane_label(provider)
        },
        %{
          "id" => "provider-last-sync",
          "label" => "Last Sync",
          "value" => provider_timestamp_label(provider.last_synced_at)
        },
        %{
          "id" => "provider-service-profile-count",
          "label" => "Service Profiles",
          "value" => service_profile_count
        },
        %{
          "id" => "provider-delivery-profile-count",
          "label" => "Delivery Profiles",
          "value" => delivery_profile_count
        }
      ]
    }
  end

  defp provider_actions_props(action \\ nil) do
    disabled? = not is_nil(action)

    %{
      "validate" => %{
        "id" => "validate-provider-button",
        "label" => if(action == :validate, do: "Validating…", else: "Validate"),
        "disabled" => disabled?
      },
      "sync" => %{
        "id" => "sync-provider-button",
        "label" => if(action == :sync, do: "Syncing…", else: "Sync Inventory"),
        "disabled" => disabled?
      },
      "archive" => %{
        "id" => "archive-provider-button",
        "label" => "Archive",
        "confirm" => "Archive this ground network provider?",
        "disabled" => disabled?
      }
    }
  end

  defp provider_profiles_props(service_profiles_empty?, delivery_profiles_empty?) do
    %{
      "service" => %{
        "id" => "provider-service-profiles",
        "heading" => "Service Profiles",
        "subtitle" => "Provider-owned service definitions available to contact scheduling.",
        "empty" => service_profiles_empty?,
        "empty_copy" => "Sync provider inventory to discover service profiles.",
        "table_id" => "service-profiles-table",
        "table_body_id" => "service-profiles-table-body",
        "columns" => ["Service", "Kind", "Direction", "Data Families", "State"]
      },
      "delivery" => %{
        "id" => "provider-delivery-profiles",
        "heading" => "Delivery Profiles",
        "subtitle" =>
          "Provider delivery options; Cadence transports are resolved from these profiles later.",
        "empty" => delivery_profiles_empty?,
        "empty_copy" => "Sync provider inventory to discover delivery profiles.",
        "table_id" => "delivery-profiles-table",
        "table_body_id" => "delivery-profiles-table-body",
        "columns" => ["Delivery", "Kind", "Direction", "Provider State"]
      }
    }
  end

  defp provider_details_props(provider) do
    %{
      "configuration" => %{
        "id" => "provider-configuration",
        "title" => "Configuration",
        "rows" => [
          provider_detail("Provider type", "Simulator"),
          provider_detail(
            "Provider Account",
            "#{provider.provider_account_id} · v#{provider.provider_account_version}",
            true
          ),
          provider_detail(
            "Mission Grant",
            "#{provider.provider_account_grant_id} · v#{provider.provider_account_grant_version}",
            true
          ),
          provider_detail("Validated", provider_timestamp_label(provider.last_validated_at))
        ]
      },
      "delivery_policy" => %{
        "id" => "provider-delivery-policy",
        "title" => "Delivery Change Policy",
        "rows" => [
          provider_detail("Mode", "Approval Required"),
          provider_detail("Deadline behavior", "Retain Last Accepted"),
          provider_detail("Permitted resources", "Inherited from grant")
        ]
      },
      "capabilities" => provider_capabilities_props(provider),
      "version_history" => %{
        "id" => "provider-version-history",
        "title" => "Version History",
        "stream_id" => "provider-versions"
      }
    }
  end

  defp provider_capabilities_props(provider) do
    items =
      provider.capabilities_document
      |> Map.get("operations", %{})
      |> Enum.sort_by(fn {name, _supported?} -> name end)
      |> Enum.map(fn {name, supported?} ->
        %{
          "label" => provider_humanize(name),
          "status" => %{
            "tone" => if(supported?, do: "ready", else: "blocked"),
            "label" => if(supported?, do: "Supported", else: "Unavailable")
          }
        }
      end)

    %{
      "id" => "provider-capabilities",
      "title" => "Capabilities",
      "empty" => items == [],
      "empty_copy" => "Validate the provider to load its declared capabilities.",
      "items" => items
    }
  end

  defp provider_diagnostics_props(provider) do
    %{
      "id" => "provider-admin-diagnostics",
      "label" => "Admin Diagnostics",
      "json_id" => "provider-admin-diagnostics-json",
      "rows" => [
        provider_detail("Account ID", provider.provider_account_id, true),
        provider_detail("Account version", "v#{provider.provider_account_version}", true),
        provider_detail("Grant ID", provider.provider_account_grant_id, true),
        provider_detail("Grant version", "v#{provider.provider_account_grant_version}", true)
      ],
      "json" =>
        Jason.encode!(
          %{
            "control_plane" => provider.metadata["control_plane"],
            "sync" => provider.metadata["sync"],
            "capabilities" => provider.capabilities_document,
            "inventory_summary" => provider_inventory_counts(provider.inventory_sync_document),
            "service_profiles" => provider_inventory_items(provider, "service_profiles"),
            "delivery_profiles" => provider_inventory_items(provider, "delivery_profiles")
          },
          pretty: true
        )
    }
  end

  defp provider_inventory_counts(document) do
    for key <- ["spacecraft", "ground_stations", "service_profiles", "delivery_profiles"],
        into: %{} do
      {key, Map.take(Map.get(document, key, %{}), ["total_count", "cached_count", "truncated"])}
    end
  end

  defp provider_inventory_items(provider, key) do
    case get_in(provider.inventory_sync_document, [key, "items"]) do
      items when is_list(items) -> items
      _other -> []
    end
  end

  defp provider_detail(label, value, mono? \\ false) do
    %{"label" => label, "value" => value, "mono" => mono?}
  end

  defp provider_control_plane_label(provider) do
    case get_in(provider.metadata, ["control_plane", "status"]) do
      "healthy" -> "Healthy"
      "failed" -> "Failed"
      _other -> "Not validated"
    end
  end

  defp provider_timestamp_label(nil), do: "Never"

  defp provider_timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")

  defp provider_humanize(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp provider_summary_value(vue, id) do
    vue.props["provider"]["summary_tiles"]
    |> Enum.find(&(&1["id"] == id))
    |> Map.fetch!("value")
  end

  defp provider_version_row(provider) do
    %{
      "__dom_id" => "provider-version-#{provider.version}",
      "version" => provider.version,
      "lifecycle_state" => provider.lifecycle_state |> Atom.to_string() |> String.upcase()
    }
  end

  defp service_profile_row do
    %{
      "__dom_id" => "service-profile-service-realtime-ttc-downlink",
      "id" => "service-realtime-ttc-downlink",
      "display_name" => "Realtime TT&C downlink",
      "service_kind" => "realtime_telemetry",
      "direction" => "downlink",
      "data_families" => "ccsds_tm",
      "status" => %{"tone" => "ready", "label" => "Active"}
    }
  end

  defp delivery_profile_row do
    %{
      "__dom_id" => "delivery-profile-delivery-cadence-primary",
      "id" => "delivery-cadence-primary",
      "display_name" => "Cadence primary telemetry ingress",
      "operator_summary" => "Streaming to Cadence",
      "delivery_kind" => "realtime_stream",
      "direction" => "downlink",
      "status" => %{"tone" => "ready", "label" => "Ready"}
    }
  end

  defp provider_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_show(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp refute_show_secrets(vue, provider) do
    encoded_contract = Jason.encode!(%{"props" => vue.props, "streams_diff" => vue.streams_diff})

    refute encoded_contract =~ provider.base_url
    refute encoded_contract =~ provider.credential_ref
    refute encoded_contract =~ provider.environment_ref
  end

  defp comms_provider_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "comms-provider-new-component")
  end

  defp comms_provider_list_presentation(view) do
    vue = LiveVue.Test.get_vue(view, id: "comms-provider-list-component")

    assert vue.component == "CommsProviderList"
    assert vue.class == "contents"
    refute vue.ssr
    assert Map.keys(vue.props) == ["presentation"]

    vue.props["presentation"]
  end

  defp provider_new_view!(conn, mission) do
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")
    view
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
