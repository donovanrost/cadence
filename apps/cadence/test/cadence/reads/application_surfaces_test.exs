defmodule Cadence.Reads.ApplicationSurfacesTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Applications.{ApplicationInstallations, HostContext, Registry, SurfaceDefinition}
  alias Cadence.Applications.SurfaceElements.{Diagnostic, Diagnostics}
  alias Cadence.Auth.Scope
  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Extensions.Presentation.{ReferenceOption, ReferencePage}
  alias Cadence.Limits.Definition
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store
  alias Cadence.Listing.Page
  alias Cadence.Reads.{ApplicationReferences, ApplicationSurfaces}
  alias Cadence.Reads.Applications, as: ApplicationReads
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Telemetry.PacketDefinition

  @organization_id "org-application-surfaces"
  @mission_id "mission-application-surfaces"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)
    {:ok, definition} = Registry.fetch_available("derived_telemetry")
    {:ok, surface} = Registry.fetch_default_surface(definition, :mission)

    %{scope: scope, host_context: host_context, definition: definition, surface: surface}
  end

  test "requires the exact active installation before loading a declared surface", context do
    assert {:error, :application_not_installed} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface
             )

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    assert {:ok, document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface
             )

    assert document.title == "Derived Telemetry"
    assert document.form.action_id == "save_definition"
    assert document.form.success_message == "Derived telemetry definition saved."
    assert document.table.id == "derived-telemetry-definitions"
    assert document.table.page == %Page{items: [], total_count: 0, page: 1, page_size: 20}
  end

  test "rejects undeclared surface contracts even when their query id is known", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    %SurfaceDefinition{} = surface = context.surface

    altered_surface = %SurfaceDefinition{surface | surface_id: "operator-supplied-surface"}

    assert {:error, :undeclared_application_surface} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               altered_surface
             )
  end

  test "returns bounded definition pages from declarative surface queries", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               context.definition.application_key
             )

    for number <- 1..25 do
      suffix = number |> Integer.to_string() |> String.pad_leading(3, "0")

      definition =
        DerivedDefinition.new(%{
          mission_id: @mission_id,
          derived_definition_id: "paged-definition-#{suffix}",
          point_id: "DERIVED.paged_#{suffix}",
          point_name: "Paged #{suffix}",
          expression: "HK.source_#{suffix} * 2"
        })

      assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)
    end

    assert {:ok, first_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface
             )

    assert %Page{page: 1, page_size: 20, total_count: 25, items: first_rows} =
             first_document.table.page

    assert length(first_rows) == 20
    assert hd(first_rows).point == "DERIVED.paged_001"
    assert List.last(first_rows).point == "DERIVED.paged_020"

    assert {:ok, second_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface,
               %{"page" => "2"}
             )

    assert %Page{page: 2, page_size: 20, total_count: 25, items: second_rows} =
             second_document.table.page

    assert Enum.map(second_rows, & &1.point) ==
             Enum.map(21..25, fn number ->
               "DERIVED.paged_#{number |> Integer.to_string() |> String.pad_leading(3, "0")}"
             end)

    assert {:ok, clamped_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               context.definition.application_key,
               context.definition.version,
               context.surface,
               %{"page" => "999"}
             )

    assert clamped_document.table.page.page == 2
  end

  test "composes limits definitions and current severity into typed host elements", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "limits"
             )

    definition =
      Definition.new(%{
        mission_id: @mission_id,
        limit_definition_id: "limit-definition-surface",
        point_id: "HK.bus_voltage",
        limit_set_name: "FLIGHT",
        thresholds: %{"yellow_high" => 31.0, "red_high" => 32.5}
      })

    assert {:ok, ^definition} = Cadence.Limits.persist_limit_definition(definition)

    activate_point_catalog_fixture()

    derived_definition =
      DerivedDefinition.new(%{
        mission_id: @mission_id,
        derived_definition_id: "derived-definition-surface",
        point_id: "DERIVED.bus_power",
        point_name: "Bus power",
        expression: "HK.bus_voltage * 2"
      })

    assert {:ok, ^derived_definition} =
             Cadence.Governance.persist_derived_definition(derived_definition)

    now = DateTime.utc_now()

    event = %Event{
      limit_event_id: "limit-event-surface",
      mission_id: @mission_id,
      spacecraft_id: "spacecraft-surface",
      point_id: "HK.bus_voltage",
      point_name: "Bus voltage",
      source_sample_type: :telemetry_sample,
      sample_id: "sample-surface",
      limit_definition_id: definition.limit_definition_id,
      limit_definition_version: definition.version,
      limit_set_name: definition.limit_set_name,
      evaluated_value: 33.2,
      limit_state: :red_high,
      normalized_state: :red,
      violation: true,
      generation_time: now,
      receipt_time: now,
      provenance: %{}
    }

    assert {:ok, [_row]} = Store.persist_latest_states(Cadence.Repo, [event])

    assert {:ok, limits_definition} = Registry.fetch_available("limits")

    assert {:ok, definitions_surface} =
             Registry.fetch_surface(limits_definition, :mission, "manage")

    assert {:ok, document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               definitions_surface
             )

    assert document.title == "Limit definitions"
    assert document.form.action_id == "save_limit_definition"
    assert document.form.success_message == "Limit definition saved."

    assert [point_field | _remaining_fields] = document.form.fields
    assert point_field.field == :point_id
    assert point_field.type == :reference
    assert point_field.reference.provider_id == "cadence.telemetry.canonical_points"
    assert point_field.reference.version == 1
    assert point_field.reference.mode == :search
    assert point_field.reference.result_limit == 20

    assert %ReferencePage{query: "", more?: false} = point_field.reference_page

    assert point_field.reference_page.options == [
             %ReferenceOption{
               value: "DERIVED.bus_power",
               label: "DERIVED.bus_power",
               description: "Derived telemetry · Bus power"
             },
             %ReferenceOption{
               value: "HK.bus_voltage",
               label: "HK.bus_voltage",
               description: "Active telemetry · Unit: V"
             }
           ]

    assert document.table.id == "limit-definitions"

    assert %Page{page: 1, page_size: 20, total_count: 1, items: rows} =
             document.table.page

    assert [%{point: "HK.bus_voltage", version: "v1"}] = rows
    assert document.activity == nil

    assert {:ok, activity_surface} =
             Registry.fetch_surface(limits_definition, :mission, "activity")

    assert {:ok, activity_document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               activity_surface
             )

    assert activity_document.title == "Current posture"
    assert activity_document.form == nil
    assert activity_document.table == nil

    assert %Diagnostics{
             id: "limit-current-diagnostics",
             title: "Current departures",
             total_count: 1,
             items: [
               %Diagnostic{
                 id: "red-departures",
                 code: "limits.current.red",
                 severity: :error,
                 value: "1 RED"
               }
             ]
           } = activity_document.diagnostics

    assert [activity_item] = activity_document.activity.items
    assert activity_item.title == "Bus voltage"
    assert activity_item.tone == :blocked
    assert activity_item.value == "33.2"

    assert {:ok, status} =
             ApplicationReads.load_status(
               context.scope,
               limits_definition,
               context.host_context
             )

    assert status.state == :red
    assert status.label == "Red limits"
    assert status.tone == :blocked
  end

  test "searches bounded reference pages through the authorized installed surface", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "limits"
             )

    for number <- 1..25 do
      suffix = number |> Integer.to_string() |> String.pad_leading(3, "0")

      definition =
        DerivedDefinition.new(%{
          mission_id: @mission_id,
          derived_definition_id: "search-definition-#{suffix}",
          point_id: "DERIVED.channel_#{suffix}",
          point_name: "Channel #{suffix}",
          expression: "HK.source_#{suffix} * 2"
        })

      assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)
    end

    assert {:ok, limits_definition} = Registry.fetch_available("limits")

    assert {:ok, surface} =
             Registry.fetch_surface(limits_definition, :mission, "manage")

    assert {:ok, document} =
             ApplicationSurfaces.load(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface
             )

    assert [point_field | _remaining_fields] = document.form.fields

    assert %ReferencePage{query: "", more?: true, options: options} =
             point_field.reference_page

    assert length(options) == 20

    assert {:ok,
            %ReferencePage{
              query: "channel_025",
              more?: false,
              options: [%ReferenceOption{value: "DERIVED.channel_025"}]
            }} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "point_id",
               "channel_025"
             )

    assert {:ok, %ReferencePage{query: "missing", more?: false, options: []}} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "point_id",
               "missing"
             )

    assert {:error, :unknown_application_surface_reference} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "operator_field",
               "channel"
             )

    assert {:ok, _installation} =
             ApplicationInstallations.disable(
               context.scope,
               context.host_context,
               limits_definition.application_key
             )

    assert {:error, :application_installation_disabled} =
             ApplicationReferences.search(
               context.scope,
               context.host_context,
               limits_definition.application_key,
               limits_definition.version,
               surface,
               "point_id",
               "channel"
             )
  end

  defp activate_point_catalog_fixture do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: @mission_id,
        packet_definition_id: "hk-surface-packet",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            name: "bus_voltage",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint,
            engineering_unit: "V"
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: @mission_id,
        binding_set_id: "surface-point-catalog-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, persisted} =
             Cadence.Governance.persist_binding_set(@organization_id, binding_set)

    content_sha256 = MissionRuntimeSpec.content_sha256(persisted)

    assert {:ok, _activation} =
             Cadence.Activations.record_binding_set_activation(
               @organization_id,
               @mission_id,
               persisted.binding_set_id,
               persisted.version,
               binding_set_content_sha256: content_sha256
             )
  end
end
