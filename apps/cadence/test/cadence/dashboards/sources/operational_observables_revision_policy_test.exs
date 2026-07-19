defmodule Cadence.Dashboards.Sources.OperationalObservablesRevisionPolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeCacheKey
  alias Cadence.Dashboards.Sources.OperationalObservables.RevisionPolicy

  @revision_families [
    :contacts_phase,
    :connection_state,
    :ground_station_antenna_pointing_state,
    :link_rf_lock_state,
    :link_rf_frame_sync_state,
    :link_rf_metric,
    :transport_bitrate,
    :transport_execution_state,
    :managed_runtime_activity,
    :transport_runtime_activity,
    :ingress_processing_latency,
    :command_queue_depth
  ]

  test "routes individual products through their family revision callback" do
    assert data_revision(:contacts_phase_history, ["contacts.phase"]) == "contacts_phase"

    assert data_revision(
             :transport_execution_state_history,
             ["comms.transport.execution_state"]
           ) == "transport_execution_state"

    assert data_revision(
             :command_queue_depth,
             ["commanding.queue_depth"],
             command_queue_revision_fun: fn _organization_id, _mission_id, _opts ->
               "custom-command-queue"
             end
           ) == "custom-command-queue"
  end

  test "preserves product-specific RF family keys in aggregate fingerprints" do
    assert data_revision(:operational_latest, ["link.rf_lock_state"]) ==
             aggregate_revision(
               "operational_latest",
               link_rf_lock_state: "link_rf_lock_state"
             )

    assert data_revision(:operational_state_history, ["link.rf_lock_state"]) ==
             aggregate_revision(
               "operational_state_history",
               link_rf: "link_rf_lock_state"
             )
  end

  defp data_revision(product, observables, opts \\ []) do
    RevisionPolicy.data_revision(
      product,
      observables,
      "organization-id",
      "mission-id",
      [realm: :flight],
      opts,
      default_funs()
    )
  end

  defp default_funs do
    Enum.map(@revision_families, fn family ->
      {family,
       fn _organization_id, _mission_id, _opts ->
         Atom.to_string(family)
       end}
    end)
  end

  defp aggregate_revision(prefix, family_revisions) do
    prefix <>
      ":" <>
      RuntimeCacheKey.fingerprint(%{
        family_revisions: Enum.sort_by(family_revisions, &elem(&1, 0))
      })
  end
end
