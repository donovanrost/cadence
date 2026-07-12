defmodule CadenceWeb.OpsDashboardShowLive.StatusMatrixDataTableTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.StatusMatrixData

  test "data table rows preserve the public table projection" do
    rows = [
      %{
        observable_id: "contacts.phase:contact-1",
        frame_observable_id: "contacts.phase",
        label: "contacts.phase / scheduled / contact-1",
        source: :operational_observables,
        status_policy: :contact_phase,
        product_family: :contacts_phase,
        link_id: "link-alpha",
        value: :active,
        normalized_state: :active,
        links: [],
        stale?: false,
        internal_only: :ignored
      }
    ]

    assert [
             %{
               observable_id: "contacts.phase:contact-1",
               frame_observable_id: "contacts.phase",
               label: "contacts.phase / scheduled / contact-1",
               source: :operational_observables,
               status_policy: :contact_phase,
               product_family: :contacts_phase,
               link_id: "link-alpha",
               value: :active,
               normalized_state: :active,
               unit: nil,
               links: [],
               stale?: false
             }
           ] = StatusMatrixData.data_table_rows(rows)

    refute Map.has_key?(hd(StatusMatrixData.data_table_rows(rows)), :internal_only)
  end

  test "data table rows preserve query scope context" do
    assert [
             %{
               observable_id: "comms.transport.connection_state:transport-alpha",
               query_scope_kind: "transport",
               query_scope_id: "transport-alpha",
               query_scope_ids: ["transport-alpha", "transport-beta"]
             }
           ] =
             StatusMatrixData.data_table_rows([
               %{
                 observable_id: "comms.transport.connection_state:transport-alpha",
                 query_scope_kind: "transport",
                 query_scope_id: "transport-alpha",
                 query_scope_ids: ["transport-alpha", "transport-beta"]
               }
             ])
  end
end
