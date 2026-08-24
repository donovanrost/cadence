defmodule CadenceWeb.OpsDashboardShowLive.TelemetryExploreLiveTest do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Runtime.Persistence, as: RuntimePersistence
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.Document
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Management.DataSources
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.TestSupport.TelemetryPersistencePolicies
  alias CadenceWeb.OpsTelemetryExploreComponents
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    {persistence_policy, persistence_opts} = Keyword.pop(opts, :persistence_policy)

    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    with {:ok, result} <-
           Cadence.process_telemetry_ingress(
             evidence,
             binding_set.binding_set_id,
             binding_set.version
           ) do
      case persistence_policy do
        nil -> RuntimePersistence.persist_processing_result(result, persistence_opts)
        policy -> RuntimePersistence.persist_processing_result(policy, result, persistence_opts)
      end
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp persist_dashboard_realm_source!(mission, realm, data_source_id, binding_id) do
    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id, binding_id: binding_id}
  end

  test "telemetry explore route renders point context and matching samples" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    source_context =
      persist_dashboard_realm_source!(
        mission,
        :rehearsal,
        "explore-rehearsal-tsdb",
        "explore-rehearsal-binding"
      )

    persistence_policies =
      TelemetryPersistencePolicies.postgres(
        organization_id: org.organization_id,
        realm: :rehearsal,
        data_source_id: source_context.data_source_id,
        binding_id: source_context.binding_id
      )

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090,
      persistence_policy: persistence_policies.persistence
    )

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      persistence_policy: persistence_policies.persistence
    )

    assert [older_sample, _latest_sample] =
             TelemetryReads.sample_history(
               org.organization_id,
               mission.mission_id,
               "HK.counter",
               spacecraft_id: spacecraft.spacecraft_id,
               order: :asc,
               realm: :rehearsal,
               data_source_id: source_context.data_source_id,
               binding_id: source_context.binding_id,
               history_store_policy: persistence_policies.history_store
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Power",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?#{%{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id, sample_id: older_sample.sample_id, selected_time: DateTime.to_iso8601(older_sample.receipt_time), realm: "rehearsal", data_source_id: source_context.data_source_id, source_binding_id: source_context.binding_id, source_dashboard_id: dashboard.dashboard_id}}"
      )

    assert has_element?(view, "#ops-telemetry-explore-component.contents")
    refute has_element?(view, "#ops-telemetry-explore-page")

    vue = telemetry_explore_vue(view)
    sample = sample_props(vue, older_sample.sample_id)
    selected_sample = vue.props["selected_sample"]
    source = vue.props["source_context"]
    clipboard = vue.props["clipboard"]
    investigation = vue.props["investigation"]

    assert vue.component == "OpsTelemetryExplore"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.slots == %{}

    assert vue.handlers == %{
             "add_to_dashboard" => Phoenix.LiveView.JS.push("add_to_dashboard"),
             "apply_filters" => Phoenix.LiveView.JS.push("apply_filters"),
             "apply_question" => Phoenix.LiveView.JS.push("apply_question"),
             "clear_selected_sample" => Phoenix.LiveView.JS.push("clear_selected_sample")
           }

    assert vue.props["page"]["source_state"] == "matched"
    assert vue.props["page"]["selected_sample_state"] == "matched"
    assert vue.props["page"]["data_source_id"] == source_context.data_source_id
    assert vue.props["page"]["source_binding_id"] == source_context.binding_id
    assert row_value(vue.props["point"]["rows"], "Point") == "HK.counter"
    assert row_value(vue.props["context_rows"], "Spacecraft") == spacecraft.spacecraft_id
    assert sample["selected"]
    assert sample["id"] == "telemetry-explore-sample-#{older_sample.sample_id}"
    assert selected_sample["id"] == "telemetry-explore-selected-sample-card"
    assert selected_sample["sample_id"] == older_sample.sample_id
    assert row_value(selected_sample["rows"], "Evidence") == older_sample.evidence_id
    assert row_value(selected_sample["rows"], "Packet") == older_sample.packet_id

    assert row_value(selected_sample["rows"], "Definition") ==
             "#{older_sample.packet_definition_id}@#{older_sample.packet_definition_version}"

    assert row_value(selected_sample["rows"], "Validity") == "canonical"
    assert sample["evidence_id"] == older_sample.evidence_id
    assert sample["dashboard_href"] =~ "selected_id=#{older_sample.sample_id}"
    assert row_value(vue.props["diagnostics"]["rows"], "Requested") == "100"
    assert row_value(vue.props["diagnostics"]["rows"], "Returned") == "2"
    assert row_value(vue.props["diagnostics"]["rows"], "Physical exists") == "true"
    assert row_value(source["rows"], "State") == "matched"
    assert row_value(source["rows"], "Logical source") == "telemetry"
    assert source["state"] == "matched"
    assert source["matched_data_source_id"] == source_context.data_source_id
    assert source["matched_source_binding_id"] == source_context.binding_id

    assert clipboard["button_id"] == "telemetry-explore-copy-link"
    assert clipboard["text"] =~ "/ops/explore"
    assert clipboard["text"] =~ "point_id=HK.counter"
    assert clipboard["text"] =~ "sample_id=#{older_sample.sample_id}"
    assert clipboard["text"] =~ "data_source_id=#{source_context.data_source_id}"
    assert clipboard["text"] =~ "source_binding_id=#{source_context.binding_id}"
    assert clipboard["class"] == "btn btn-ghost btn-sm"
    assert clipboard["icon"] == "hero-link"
    assert clipboard["icon_class"] == "h-4 w-4"
    assert clipboard["label"] == "Copy link"
    assert clipboard["copied_message"] == "Copied to clipboard"
    assert clipboard["failed_message"] == "Copy failed"

    assert investigation["path"] =~ "point_id=HK.counter"
    assert investigation["fingerprint"] =~ ~r/^[a-f0-9]{12}$/

    assert vue.props["navigation"]["back_to_dashboard"]["id"] ==
             "telemetry-explore-back-to-dashboard"

    assert_filter_form_contract(vue.props["filter_form"])
    assert_json_safe_vue(vue)
    encoded_props = Jason.encode!(vue.props)
    refute encoded_props =~ user.email
    refute encoded_props =~ "range_scan?"
    refute encoded_props =~ "latest?"
    refute_sensitive_keys(vue.props)

    render_hook(view, "clear_selected_sample", %{})
    cleared_path = assert_patch(view)
    assert cleared_path =~ "point_id=HK.counter"
    assert cleared_path =~ "spacecraft_id=#{URI.encode_www_form(spacecraft.spacecraft_id)}"
    refute cleared_path =~ "sample_id="
    refute cleared_path =~ "selected_time="
    refute cleared_path =~ "source_dashboard_id="
    assert telemetry_explore_vue(view).props["selected_sample"] == nil

    from = "2023-11-14T22:14:45Z"
    to = "2023-11-14T22:15:00Z"

    archive_filters =
      telemetry_explore_vue(view).props["filter_form"]["values"]
      |> Map.merge(%{
        "point_id" => "HK.counter",
        "spacecraft_id" => spacecraft.spacecraft_id,
        "time_mode" => "archive",
        "from" => from,
        "to" => to,
        "order" => "asc",
        "limit" => "1",
        "realm" => "rehearsal",
        "logical_source" => "telemetry",
        "data_source_id" => source_context.data_source_id,
        "source_binding_id" => source_context.binding_id,
        "source_dashboard_id" => dashboard.dashboard_id,
        "sample_id" => older_sample.sample_id,
        "selected_time" => DateTime.to_iso8601(older_sample.receipt_time)
      })

    assert Enum.all?(archive_filters, fn {key, value} ->
             is_binary(key) and is_binary(value)
           end)

    render_hook(view, "apply_filters", %{"explore" => archive_filters})

    patched_path = assert_patch(view)
    assert patched_path =~ "point_id=HK.counter"
    assert patched_path =~ "time_mode=archive"
    assert patched_path =~ "from=#{URI.encode_www_form(from)}"
    assert patched_path =~ "to=#{URI.encode_www_form(to)}"
    assert patched_path =~ "order=asc"
    assert patched_path =~ "limit=1"
    assert patched_path =~ "realm=rehearsal"
    assert patched_path =~ "data_source_id=#{source_context.data_source_id}"
    assert patched_path =~ "source_binding_id=#{source_context.binding_id}"
    refute patched_path =~ "logical_source=telemetry"

    archive_vue = telemetry_explore_vue(view)

    assert row_value(archive_vue.props["source_context"]["rows"], "Requested realm") ==
             "rehearsal"

    assert row_value(archive_vue.props["source_context"]["rows"], "Requested source") ==
             source_context.data_source_id

    assert row_value(archive_vue.props["source_context"]["rows"], "Requested binding") ==
             source_context.binding_id

    selection_filters =
      archive_vue.props["filter_form"]["values"]
      |> Map.merge(%{
        "point_id" => "HK.counter",
        "spacecraft_id" => spacecraft.spacecraft_id,
        "time_mode" => "latest",
        "order" => "desc",
        "limit" => "100",
        "selection_view" => "all_revisions",
        "validity_state" => "conflict",
        "realm" => "rehearsal",
        "data_source_id" => source_context.data_source_id,
        "source_binding_id" => source_context.binding_id,
        "source_dashboard_id" => dashboard.dashboard_id,
        "sample_id" => older_sample.sample_id,
        "selected_time" => DateTime.to_iso8601(older_sample.receipt_time)
      })

    render_hook(view, "apply_filters", %{"explore" => selection_filters})

    filtered_path = assert_patch(view)
    assert filtered_path =~ "selection_view=all_revisions"
    assert filtered_path =~ "validity_state=conflict"
    assert filtered_path =~ "realm=rehearsal"
    assert filtered_path =~ "data_source_id=#{source_context.data_source_id}"
    assert filtered_path =~ "source_binding_id=#{source_context.binding_id}"
    refute filtered_path =~ "time_mode=latest"
    refute filtered_path =~ "order=desc"
    refute filtered_path =~ "limit=100"

    filtered_vue = telemetry_explore_vue(view)

    assert filtered_vue.props["page"]["empty_samples_message"] ==
             "Physical samples exist, but none matched the current selection view or validity filter."

    assert row_value(filtered_vue.props["diagnostics"]["rows"], "Returned") == "0"
    assert row_value(filtered_vue.props["diagnostics"]["rows"], "Physical exists") == "true"
    assert filtered_vue.props["page"]["source_state"] == "matched"
    assert filtered_vue.props["page"]["selected_sample_state"] == "missing"
    assert filtered_vue.props["selected_sample"] == nil

    assert filtered_vue.props["page"]["selected_sample_status"] == %{
             "heading" => "Selected sample is outside the current result set",
             "icon" => "hero-exclamation-triangle",
             "id" => "telemetry-explore-selected-sample-status",
             "sample_id" => older_sample.sample_id,
             "state" => "missing"
           }

    assert_json_safe_vue(filtered_vue)
  end

  test "telemetry explore route marks stale source evidence targets as missing" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/explore?#{%{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id, realm: "rehearsal", data_source_id: "retired-rehearsal-tsdb", source_binding_id: "retired-rehearsal-binding"}}"
      )

    vue = telemetry_explore_vue(view)

    assert vue.props["page"]["source_state"] == "missing"
    assert vue.props["page"]["data_source_id"] == "retired-rehearsal-tsdb"
    assert vue.props["page"]["source_binding_id"] == "retired-rehearsal-binding"
    assert vue.props["page"]["selected_sample_state"] == "none"
    assert vue.props["source_context"]["state"] == "missing"
    assert vue.props["source_context"]["data_source_id"] == "retired-rehearsal-tsdb"
    assert vue.props["source_context"]["source_binding_id"] == "retired-rehearsal-binding"
    assert row_value(vue.props["source_context"]["rows"], "State") == "missing"
    assert row_value(vue.props["diagnostics"]["rows"], "Returned") == "0"
    assert_json_safe_vue(vue)
  end

  test "question-led Explore stages a dashboard candidate without writing until Save" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               org.organization_id,
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               []
             )

    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Investigation Board")

    {:ok, explore, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/explore")

    assert has_element?(explore, "#ops-context-rail-component")
    assert has_element?(explore, "#ops-telemetry-explore-component.contents")
    refute has_element?(explore, "#telemetry-explore-questions")

    initial_vue = telemetry_explore_vue(explore)
    what_changed = Enum.find(initial_vue.props["questions"], &(&1["id"] == "what_changed"))
    assert what_changed["dom_id"] == "telemetry-explore-question-what_changed"

    render_hook(explore, "apply_question", %{"question" => what_changed["id"]})

    preset_path = assert_patch(explore)
    assert preset_path =~ "question=what_changed"
    assert preset_path =~ "time_mode=last_1h"
    assert preset_path =~ "selection_view=all_revisions"

    preset_vue = telemetry_explore_vue(explore)
    briefing = preset_vue.props["question_briefing"]
    authoring = preset_vue.props["authoring"]

    assert briefing["id"] == "telemetry-explore-question-briefing"
    assert briefing["question"] == "what_changed"
    assert Enum.any?(briefing["actions"], &(&1["id"] == "telemetry-explore-question-timeline"))
    assert authoring["form"]["id"] == "telemetry-explore-add-to-dashboard-form"

    assert authoring["form"]["values"] == %{
             "dashboard_id" => "",
             "title" => "",
             "widget_type" => "time_series"
           }

    assert Enum.any?(
             authoring["form"]["fields"]["dashboard_id"]["options"],
             &(&1 == %{"label" => "Investigation Board", "value" => dashboard.dashboard_id})
           )

    add_payload = %{
      "add_to_dashboard" => %{
        "dashboard_id" => dashboard.dashboard_id,
        "widget_type" => "time_series",
        "title" => "Counter investigation"
      }
    }

    assert Enum.all?(add_payload["add_to_dashboard"], fn {key, value} ->
             is_binary(key) and is_binary(value)
           end)

    render_hook(explore, "add_to_dashboard", add_payload)

    {editor_path, _flash} = assert_redirect(explore)
    assert editor_path =~ "/ops/dashboards/#{dashboard.dashboard_id}/edit"
    assert editor_path =~ "candidate_source=explore"
    assert editor_path =~ "candidate_point_id=HK.counter"

    assert version_count(org, mission, dashboard) == 1

    {:ok, editor, _html} = live(conn, editor_path)
    render_dashboard_async(editor)

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-dashboard-editor="true"][data-editor-dirty="true"])
           )

    assert version_count(org, mission, dashboard) == 1
    assert {:ok, %Document{placements: []}} = fetch_document(org, mission, dashboard)

    click_editor_action(editor, "dashboard-editor-save")
    render_dashboard_async(editor)

    assert version_count(org, mission, dashboard) == 2

    assert {:ok, %Document{placements: [placement]}} = fetch_document(org, mission, dashboard)
    assert placement.widget_def.title == "Counter investigation"
    assert placement.widget_def.binding.observables == ["HK.counter"]

    stop_dashboard_view(editor)
  end

  test "presentation contract omits dashboard targets across the non-author boundary" do
    viewer_props =
      false
      |> presentation_assigns()
      |> OpsTelemetryExploreComponents.presentation_props()

    author_props =
      true
      |> presentation_assigns()
      |> OpsTelemetryExploreComponents.presentation_props()

    refute Map.has_key?(viewer_props, :authoring)

    assert get_in(author_props, [:authoring, :form, :id]) ==
             "telemetry-explore-add-to-dashboard-form"

    assert get_in(author_props, [
             :authoring,
             :form,
             :fields,
             :dashboard_id,
             :options
           ]) == [
             %{label: "Choose a dashboard", value: ""},
             %{label: "Author Board", value: "dashboard-author"}
           ]

    viewer_json = Jason.encode!(viewer_props)
    author_json = Jason.encode!(author_props)

    refute viewer_json =~ "dashboard-author"
    refute viewer_json =~ "Author Board"
    assert author_json =~ "dashboard-author"
    assert author_json =~ "Author Board"
    refute_sensitive_keys(viewer_props)
    refute_sensitive_keys(author_props)
  end

  defp click_editor_action(view, id) do
    assert has_element?(view, "#dashboard-editor-actions-component")
    vue = LiveVue.Test.get_vue(view, id: "dashboard-editor-actions-component")
    assert vue.component == "DashboardEditorActions"
    assert action = Enum.find(vue.props["presentation"]["elements"], &(&1["attrs"]["id"] == id))
    attrs = action["attrs"]

    render_click(
      view,
      Map.fetch!(attrs, "phx-click"),
      Enum.reduce(attrs, %{}, fn
        {"phx-value-" <> key, value}, params -> Map.put(params, key, value)
        {_attribute, _value}, params -> params
      end)
    )
  end

  defp telemetry_explore_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-telemetry-explore-component")
  end

  defp sample_props(vue, sample_id) do
    assert sample = Enum.find(vue.props["samples"], &(&1["sample_id"] == sample_id))
    sample
  end

  defp row_value(rows, label) do
    assert row = Enum.find(rows, &(&1["label"] == label))
    row["value"]
  end

  defp assert_filter_form_contract(filter_form) do
    assert filter_form["id"] == "telemetry-explore-filter-form"

    assert Map.keys(filter_form["values"]) |> Enum.sort() ==
             ~w(
               data_source_id from limit limit_mode logical_source order point_id question realm
               replay_run_id sample_id scope_id scope_kind selected_time selection_view
               source_binding_id source_dashboard_id spacecraft_id time_axis time_mode to
               validity_state
             )

    assert Enum.all?(filter_form["values"], fn {key, value} ->
             is_binary(key) and is_binary(value)
           end)

    assert filter_form["fields"]["point_id"]["id"] == "explore_point_id"
    assert filter_form["fields"]["point_id"]["name"] == "explore[point_id]"
    assert filter_form["fields"]["limit"]["min"] == "1"
    assert filter_form["fields"]["limit"]["max"] == "1000"

    assert filter_form["submit"] == %{
             "icon" => "hero-arrow-path",
             "id" => "telemetry-explore-apply-filters",
             "label" => "Load"
           }
  end

  defp assert_json_safe_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp refute_sensitive_keys(value) when is_map(value) do
    sensitive_keys =
      ~w(
        capabilities credentials credentials_ref current_scope current_user metadata password
        provenance scope secret secrets token user
      )

    Enum.each(value, fn {key, nested} ->
      refute to_string(key) in sensitive_keys
      refute_sensitive_keys(nested)
    end)
  end

  defp refute_sensitive_keys(value) when is_list(value),
    do: Enum.each(value, &refute_sensitive_keys/1)

  defp refute_sensitive_keys(_value), do: :ok

  defp presentation_assigns(dashboard_author?) do
    context = %{
      point_id: "HK.counter",
      sample_id: nil,
      spacecraft_id: nil,
      scope_kind: nil,
      scope_id: nil,
      time_mode: "latest",
      time_axis: nil,
      from: nil,
      to: nil,
      from_text: nil,
      to_text: nil,
      realm: nil,
      logical_source: :telemetry,
      logical_source_text: "telemetry",
      data_source_id: nil,
      source_binding_id: nil,
      source_dashboard_id: nil,
      selected_time: nil,
      replay_run_id: nil,
      question: nil,
      limit_mode: nil,
      limit: 100,
      limit_text: "100",
      order: :desc,
      order_text: "desc",
      selection_view: :canonical,
      selection_view_text: "canonical",
      validity_state: nil,
      validity_state_text: ""
    }

    %{
      current_mission: %{mission_id: "mission-author-boundary"},
      explore_context: context,
      filter_form: Phoenix.Component.to_form(%{}, as: :explore),
      add_to_dashboard_form:
        Phoenix.Component.to_form(
          %{"dashboard_id" => "", "widget_type" => "time_series", "title" => ""},
          as: :add_to_dashboard
        ),
      points: [%{point_id: "HK.counter"}],
      spacecraft: [],
      data_sources: [],
      data_bindings: [],
      data_realms: [],
      point: %{
        point_id: "HK.counter",
        packet_name: "HK",
        field_name: "counter",
        unit: nil,
        description: nil
      },
      samples: [],
      selected_sample: nil,
      selected_sample_state: "none",
      source_context: %{
        state: "none",
        data_source_id: nil,
        source_binding_id: nil,
        logical_source: "telemetry",
        realm: nil,
        matched_data_source_id: nil,
        matched_source_binding_id: nil
      },
      history_diagnostics: %{
        requested_logical_limit: 100,
        logical_selected_count: 0,
        physical_candidate_count: 0,
        physical_candidate_limit: nil,
        effective_selection?: true,
        candidate_window_exhausted?: false,
        physical_samples_exist?: false,
        selection_view: "canonical",
        validity_state: "",
        error: nil
      },
      investigation_path: "/missions/mission-author-boundary/ops/explore?point_id=HK.counter",
      investigation_fingerprint: "0123456789ab",
      dashboard_author?: dashboard_author?,
      ops_dashboards: [
        %{
          dashboard_id: "dashboard-author",
          name: "Author Board",
          lifecycle_state: "active"
        }
      ]
    }
  end

  defp version_count(org, mission, dashboard) do
    Cadence.Dashboards.list_versions(
      org.organization_id,
      mission.mission_id,
      dashboard.dashboard_id
    )
    |> length()
  end

  defp fetch_document(org, mission, dashboard) do
    Cadence.Dashboards.fetch_document(
      org.organization_id,
      mission.mission_id,
      dashboard.dashboard_id
    )
  end
end
