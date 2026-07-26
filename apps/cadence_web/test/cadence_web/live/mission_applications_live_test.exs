defmodule CadenceWeb.MissionApplicationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Limits.{Event, Store}
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "declarative-applications",
        display_name: "Declarative Applications"
      )

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission
    }
  end

  test "installs a registered mission application from the host inventory", context do
    {:ok, view, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    assert has_element?(view, "#mission-applications-page")
    assert has_element?(view, "#mission-application-derived_telemetry")

    assert has_element?(
             view,
             "#install-mission-application-derived_telemetry",
             "Install"
           )

    view
    |> element("#install-mission-application-derived_telemetry")
    |> render_click()

    assert has_element?(
             view,
             "#mission-application-derived_telemetry a[href='/missions/#{context.mission.mission_id}/applications/derived_telemetry']",
             "Manage"
           )

    assert has_element?(
             view,
             "#disable-mission-application-derived_telemetry[data-application-lifecycle-action='disable'][data-confirmation-required='true'][data-confirmation-tone='attention']",
             "Disable workspace"
           )

    assert has_element?(
             view,
             "#disable-mission-application-derived_telemetry[data-confirm*='active runtime state is unchanged']"
           )

    assert has_element?(
             view,
             "#uninstall-mission-application-derived_telemetry[data-application-lifecycle-action='uninstall'][data-confirmation-required='true'][data-confirmation-tone='danger']",
             "Uninstall"
           )
  end

  test "renders and submits a generated form through the declarative host", context do
    {:ok, inventory, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    inventory
    |> element("#install-mission-application-derived_telemetry")
    |> render_click()

    application_path =
      ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"

    {:ok, view, _html} = live(context.conn, application_path)

    assert has_element?(
             view,
             "#mission-application-host[data-application-key='derived_telemetry'][data-application-version='1'][data-surface-id='manage'][data-renderer='declarative']"
           )

    assert has_element?(view, "#declarative-application-surface")
    assert has_element?(view, "#derived-telemetry-definition-form-fields")

    assert has_element?(
             view,
             "#derived-telemetry-definition-form-submit[data-application-domain-action='save_definition'][data-action-version='1'][data-action-intent='configuration'][data-action-scope='mission'][data-action-effect='durable'][data-action-execution='immediate'][data-confirmation-required='false']",
             "Save definition"
           )

    assert has_element?(
             view,
             "#derived-telemetry-definition-form-field-point_id[data-field-type='text'] input[type='text'][name='application_action[point_id]']"
           )

    refute has_element?(
             view,
             "#derived-telemetry-definition-form-fields select[name='application_action[point_id]']"
           )

    assert has_element?(view, "#derived-telemetry-definitions-rows")

    view
    |> form("#derived-telemetry-definition-form-fields", %{
      "application_action" => %{
        "point_id" => "DERIVED.bus_power",
        "point_name" => "Bus power",
        "expression" => "HK.voltage * HK.current"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#application-action-feedback[data-kind='success'][data-code='action_completed']",
             "Derived telemetry definition saved."
           )

    assert has_element?(
             view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']"
           )

    assert has_element?(
             view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.bus_power"
           )

    {:ok, remounted_view, _html} = live(context.conn, application_path)

    assert has_element?(
             remounted_view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.bus_power"
           )
  end

  test "paginates declarative application tables through shareable host state", context do
    {:ok, inventory, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    inventory
    |> element("#install-mission-application-derived_telemetry")
    |> render_click()

    for number <- 1..21 do
      suffix = number |> Integer.to_string() |> String.pad_leading(3, "0")

      definition =
        DerivedDefinition.new(%{
          mission_id: context.mission.mission_id,
          derived_definition_id: "live-paged-definition-#{suffix}",
          point_id: "DERIVED.live_paged_#{suffix}",
          point_name: "Live paged #{suffix}",
          expression: "HK.source_#{suffix} * 2"
        })

      assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)
    end

    application_path =
      ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"

    {:ok, view, _html} = live(context.conn, application_path)

    assert has_element?(
             view,
             "#derived-telemetry-definitions-pagination",
             "1–20 of 21"
           )

    assert has_element?(
             view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.live_paged_001"
           )

    refute has_element?(
             view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.live_paged_021"
           )

    view
    |> element(
      "#derived-telemetry-definitions-pagination button[phx-value-page='2']",
      "Next"
    )
    |> render_click()

    page_two_path =
      "/missions/#{context.mission.mission_id}/applications/derived_telemetry/manage?page=2"

    assert_patch(view, page_two_path)

    assert has_element?(
             view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.live_paged_021"
           )

    refute has_element?(
             view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.live_paged_001"
           )

    assert has_element?(
             view,
             "#derived-telemetry-definitions-pagination button[phx-value-page='1']",
             "Prev"
           )

    {:ok, deep_linked_view, _html} = live(context.conn, page_two_path)

    assert has_element?(
             deep_linked_view,
             "#derived-telemetry-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.live_paged_021"
           )
  end

  test "disables, uninstalls, and reinstalls a mission application", context do
    inventory_path = ~p"/missions/#{context.mission.mission_id}/applications"
    {:ok, view, _html} = live(context.conn, inventory_path)

    view
    |> element("#install-mission-application-derived_telemetry")
    |> render_click()

    assert has_element?(view, "#disable-mission-application-derived_telemetry")
    assert has_element?(view, "#uninstall-mission-application-derived_telemetry")

    view
    |> element("#disable-mission-application-derived_telemetry")
    |> render_click()

    assert has_element?(view, "#install-mission-application-derived_telemetry", "Enable")
    assert has_element?(view, "#uninstall-mission-application-derived_telemetry")

    view
    |> element("#install-mission-application-derived_telemetry")
    |> render_click()

    view
    |> element("#uninstall-mission-application-derived_telemetry")
    |> render_click()

    assert has_element?(view, "#install-mission-application-derived_telemetry", "Reinstall")
    refute has_element?(view, "#uninstall-mission-application-derived_telemetry")

    assert {:error,
            {:live_redirect,
             %{
               to: ^inventory_path,
               flash: %{"error" => "Reinstall the application before opening it."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"
             )

    view
    |> element("#install-mission-application-derived_telemetry")
    |> render_click()

    assert has_element?(view, "#disable-mission-application-derived_telemetry")
  end

  test "installs limits and versions a governed threshold definition through the host", context do
    derived_definition =
      DerivedDefinition.new(%{
        mission_id: context.mission.mission_id,
        derived_definition_id: "derived-definition-live-host",
        point_id: "DERIVED.bus_power",
        point_name: "Bus power",
        expression: "HK.voltage * HK.current"
      })

    assert {:ok, ^derived_definition} =
             Cadence.Governance.persist_derived_definition(derived_definition)

    {:ok, inventory, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    assert has_element?(inventory, "#mission-application-limits")
    assert has_element?(inventory, "#install-mission-application-limits", "Install")

    inventory
    |> element("#install-mission-application-limits")
    |> render_click()

    application_path = ~p"/missions/#{context.mission.mission_id}/applications/limits"
    {:ok, view, _html} = live(context.conn, application_path)

    assert has_element?(
             view,
             "#mission-application-host[data-application-key='limits'][data-application-version='1'][data-surface-id='manage'][data-renderer='declarative']"
           )

    assert has_element?(view, "#limit-definition-form-fields")

    assert has_element?(
             view,
             "#limit-definition-form-submit[data-application-domain-action='save_limit_definition'][data-action-version='1'][data-action-intent='configuration'][data-action-scope='mission'][data-action-effect='durable'][data-action-execution='immediate'][data-confirmation-required='false']",
             "Save limit definition"
           )

    assert has_element?(
             view,
             "#limit-definition-form-field-point_id[data-field-type='reference'][data-reference-provider='cadence.telemetry.canonical_points'][data-reference-version='1'][data-reference-mode='search'][data-reference-query='']"
           )

    assert has_element?(
             view,
             "#limit-definition-form-fields input[name='application_action[point_id]'][list='limit-definition-form-reference-point_id-options'][phx-debounce='250']"
           )

    assert has_element?(
             view,
             "#limit-definition-form-reference-point_id-options option[value='DERIVED.bus_power'][label='DERIVED.bus_power']"
           )

    assert has_element?(
             view,
             "#limit-definition-form-reference-point_id-status[data-match-count='1'][data-more-matches='false']",
             "1 mission reference"
           )

    view
    |> element("#limit-definition-form-fields")
    |> render_change(%{
      "_target" => ["application_action", "point_id"],
      "application_action" => %{"point_id" => "power"}
    })

    assert has_element?(
             view,
             "#limit-definition-form-field-point_id[data-reference-query='power']"
           )

    assert has_element?(
             view,
             "#limit-definition-form-reference-point_id-options option[value='DERIVED.bus_power']"
           )

    view
    |> element("#limit-definition-form-fields")
    |> render_change(%{
      "_target" => ["application_action", "point_id"],
      "application_action" => %{"point_id" => "missing"}
    })

    assert has_element?(
             view,
             "#limit-definition-form-reference-point_id-status[data-match-count='0'][data-more-matches='false']",
             "No matching mission references"
           )

    refute has_element?(
             view,
             "#limit-definition-form-reference-point_id-options option[value='DERIVED.bus_power']"
           )

    assert has_element?(view, "#limit-definition-form-fields input[type='number'][step='any']")
    assert has_element?(view, "#limit-definitions-rows")
    refute has_element?(view, "#limit-current-posture-items")

    assert has_element?(
             view,
             "#application-surface-nav-manage[aria-current='page']",
             "Definitions"
           )

    activity_path =
      ~p"/missions/#{context.mission.mission_id}/applications/limits/activity"

    assert has_element?(
             view,
             "#application-surface-nav-activity[href='#{activity_path}']",
             "Current posture"
           )

    view
    |> form("#limit-definition-form-fields", %{
      "application_action" => %{
        "point_id" => "DERIVED.bus_power",
        "limit_set_name" => "FLIGHT",
        "red_high" => "hot"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#application-action-feedback[data-kind='error'][data-code='invalid_number']",
             "Red high must be a number."
           )

    assert has_element?(
             view,
             "#limit-definition-form-fields input[name='application_action[red_high]'][value='hot'].input-error"
           )

    refute has_element?(
             view,
             "#limit-definitions-rows tr[id^='application-surface-row-']"
           )

    view
    |> form("#limit-definition-form-fields", %{
      "application_action" => %{
        "point_id" => "DERIVED.bus_power",
        "limit_set_name" => "FLIGHT",
        "yellow_low" => "25.5",
        "yellow_high" => "31.0",
        "red_low" => "24.0",
        "red_high" => "32.5"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#application-action-feedback[data-kind='success'][data-code='action_completed']",
             "Limit definition saved."
           )

    assert has_element?(
             view,
             "#limit-definitions-rows tr[id^='application-surface-row-']",
             "DERIVED.bus_power"
           )

    assert has_element?(
             view,
             "#limit-definitions-rows tr[id^='application-surface-row-']",
             "RL 24.0 · YL 25.5 · YH 31.0 · RH 32.5"
           )

    now = DateTime.utc_now()

    event = %Event{
      limit_event_id: "limit-event-live-host",
      mission_id: context.mission.mission_id,
      spacecraft_id: nil,
      point_id: "HK.bus_voltage",
      point_name: "Bus voltage",
      source_sample_type: :telemetry_sample,
      sample_id: "sample-live-host",
      limit_definition_id: "limit-definition-live-host",
      limit_definition_version: 1,
      limit_set_name: "FLIGHT",
      evaluated_value: 33.2,
      limit_state: :red_high,
      normalized_state: :red,
      violation: true,
      generation_time: now,
      receipt_time: now,
      provenance: %{}
    }

    assert {:ok, [_row]} = Store.persist_latest_states(Repo, [event])

    {:ok, remounted_view, _html} = live(context.conn, application_path)

    assert has_element?(
             remounted_view,
             "#limit-definitions-rows tr[id^='application-surface-row-']",
             "v1"
           )

    refute has_element?(remounted_view, "#limit-current-posture-items")

    {:ok, activity_view, _html} = live(context.conn, activity_path)

    assert has_element?(
             activity_view,
             "#mission-application-host[data-application-key='limits'][data-surface-id='activity']"
           )

    assert has_element?(
             activity_view,
             "#application-surface-nav-activity[aria-current='page']",
             "Current posture"
           )

    refute has_element?(activity_view, "#limit-definition-form-fields")
    refute has_element?(activity_view, "#limit-definitions-rows")

    assert has_element?(
             activity_view,
             "#limit-current-diagnostics[data-diagnostic-severity='error'][data-diagnostic-count='1'][data-diagnostic-total='1']"
           )

    assert has_element?(
             activity_view,
             "#limit-current-diagnostics-item-red-departures[data-diagnostic-code='limits.current.red'][data-diagnostic-severity='error']",
             "Red limit departures"
           )

    assert has_element?(
             activity_view,
             "#limit-current-posture-items article[id^='application-surface-activity-']",
             "Bus voltage"
           )

    assert has_element?(
             activity_view,
             "#limit-current-posture-items article[id^='application-surface-activity-']",
             "33.2"
           )
  end

  test "known but uninstalled mission application redirects to the inventory", context do
    assert {:error,
            {:live_redirect,
             %{
               to: path,
               flash: %{"error" => "Install the application before opening it."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"
             )

    assert path == ~p"/missions/#{context.mission.mission_id}/applications"
  end
end
