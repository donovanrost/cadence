defmodule CadenceWeb.OpsDashboardShowLive.MatrixWidgetDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.MatrixWidgetData

  test "renders status matrix rows with aggregated widget lifecycle" do
    placement_frames = operational_contact_phase_frames()

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             rows: [
               %{
                 observable_id: "contacts.phase:contact-1",
                 label: "contacts.phase / scheduled / contact-1",
                 source: :operational_observables,
                 status_policy: :contact_phase,
                 contact_id: "contact-1",
                 value: :active,
                 normalized_state: :active,
                 links: [%{target: :contact, target_id: "contact-1"}]
               }
             ]
           } = MatrixWidgetData.status_matrix(placement_frames)
  end

  test "renders data table rows from status matrix rows" do
    placement_frames = operational_contact_phase_frames()

    assert %{
             kind: :data_table,
             engine_backed?: true,
             lifecycle_state: :ready,
             rows: [
               %{
                 observable_id: "contacts.phase:contact-1",
                 frame_observable_id: "contacts.phase",
                 source_request_id: "ops-latest-1",
                 logical_source: :operational_observables,
                 value: :active,
                 normalized_state: :active,
                 links: [%{target: :contact, target_id: "contact-1"}]
               }
             ]
           } = MatrixWidgetData.data_table(placement_frames)
  end

  test "empty matrix widgets retain lifecycle and data-management placement context" do
    placement_frames = %PlacementFrames{primary: []}

    assert %{
             kind: :status_matrix,
             rows: [],
             lifecycle_state: :no_data,
             engine_backed?: true,
             unresolved?: false
           } = MatrixWidgetData.status_matrix(placement_frames)

    assert %{
             kind: :data_table,
             rows: [],
             lifecycle_state: :no_data,
             engine_backed?: true,
             unresolved?: false
           } = MatrixWidgetData.data_table(placement_frames)
  end

  defp operational_contact_phase_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["contacts.phase"]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1"]},
            %Field{name: "contact_kind", kind: :enum, values: [:scheduled]},
            %Field{name: "phase", kind: :enum, values: [:active]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [300_000]}
          ],
          meta: %{
            observable_id: "contacts.phase",
            supported_capability: :contacts_phase,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: [
              %DataLink{
                link_id: "contact:contact-1",
                target: :contact,
                target_id: "contact-1",
                label: "Contact"
              }
            ]
          }
        }
      ]
    }
  end
end
