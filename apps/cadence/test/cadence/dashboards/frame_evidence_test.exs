defmodule Cadence.Dashboards.FrameEvidenceTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DataLink,
    EvidenceRef,
    Field,
    Frame,
    FrameEvidence,
    PlacementFrames
  }

  test "aggregates evidence, links, and actions for a primary frame and relevant overlays" do
    frame_action = %DashboardAction{
      action_id: "telemetry-explore:req-1:HK.counter:frame",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{"point_id" => "HK.counter"},
      source: :frame
    }

    field_action = %DashboardAction{frame_action | action_id: "field-action", source: :field}

    telemetry_link = %DataLink{
      link_id: "telemetry-point:HK.counter",
      target: :telemetry_point,
      target_id: "HK.counter",
      source: :frame
    }

    limit_link = %DataLink{
      link_id: "limit-event:limit-1",
      target: :limit_event,
      target_id: "limit-1",
      source: :frame
    }

    serialized_link = %{
      "link_id" => "mission-event:event-1",
      "label" => "Mission event",
      "target" => "mission_event",
      "target_id" => "event-1",
      "presentation" => "side_panel",
      "source" => "frame"
    }

    evidence_ref = %EvidenceRef{
      kind: :raw_evidence,
      id: "evidence-1",
      source: :telemetry,
      confidence: :direct
    }

    serialized_evidence_ref = %{
      "kind" => "source_request",
      "id" => "req-1",
      "source" => "telemetry",
      "confidence" => "direct"
    }

    primary = %Frame{
      frame_id: "req-1:HK.counter",
      source: :telemetry,
      shape: :scalar,
      fields: [
        %Field{
          name: "HK.counter",
          kind: :number,
          values: [42],
          metadata: %{actions: [field_action]}
        }
      ],
      meta: %{
        observable_id: "HK.counter",
        evidence: [evidence_ref, serialized_evidence_ref],
        links: [telemetry_link, serialized_link],
        actions: [frame_action]
      }
    }

    relevant_overlay = %Frame{
      frame_id: "limits:HK.counter",
      source: :limits,
      shape: :events,
      meta: %{
        observable_id: "HK.counter",
        links: [limit_link, telemetry_link],
        evidence: [evidence_ref]
      }
    }

    unrelated_overlay = %Frame{
      frame_id: "limits:OTHER.counter",
      source: :limits,
      shape: :events,
      meta: %{observable_id: "OTHER.counter"}
    }

    placement_frames = %PlacementFrames{
      primary: [primary],
      overlays: %{limits: [relevant_overlay, unrelated_overlay]}
    }

    assert %{
             frame: ^primary,
             overlay_frames: [^relevant_overlay],
             frames: [^primary, ^relevant_overlay],
             links: [
               ^telemetry_link,
               %DataLink{link_id: "mission-event:event-1", target: :mission_event},
               ^limit_link
             ],
             evidence_refs: [^evidence_ref, %EvidenceRef{kind: :source_request, id: "req-1"}],
             actions: [
               %DashboardAction{action_id: "telemetry-explore:req-1:HK.counter:frame"},
               %DashboardAction{action_id: "field-action"}
             ]
           } = FrameEvidence.inspect(placement_frames, "HK.counter")
  end

  test "aggregates selected interval evidence from field metadata" do
    frame_interval_ref = %EvidenceRef{
      kind: :source_binding_interval,
      id: "source-binding-interval-1",
      source: :telemetry,
      confidence: :selected
    }

    field_interval_ref = %EvidenceRef{
      kind: :binding_set_interval,
      id: "binding-set-interval-1",
      source: :operational_event,
      confidence: :selected
    }

    primary = %Frame{
      frame_id: "req-1:HK.counter",
      source: :telemetry,
      shape: :scalar,
      fields: [
        %Field{
          name: "HK.counter",
          kind: :number,
          values: [42],
          metadata: %{evidence: [field_interval_ref, frame_interval_ref]}
        }
      ],
      meta: %{
        observable_id: "HK.counter",
        evidence: [frame_interval_ref]
      }
    }

    placement_frames = %PlacementFrames{primary: [primary]}

    assert %{
             evidence_refs: [
               ^frame_interval_ref,
               ^field_interval_ref
             ]
           } = FrameEvidence.inspect(placement_frames, "HK.counter")
  end

  test "aggregates frame evidence from evidence_refs metadata" do
    interval_ref = %EvidenceRef{
      kind: :link_rf_lock_state_interval,
      id: "effective_interval:link_rf_lock_state:event-1",
      source: :operational_observables,
      confidence: :projected
    }

    source_event_ref = %EvidenceRef{
      kind: :operational_interval,
      id: "event-1",
      source: :operational_observables,
      confidence: :direct
    }

    primary = %Frame{
      frame_id: "req-1:link_rf_lock_state_history",
      source: :operational_observables,
      shape: :events,
      fields: [],
      meta: %{
        observable_id: "link.rf_lock_state",
        evidence_refs: [interval_ref, source_event_ref]
      }
    }

    placement_frames = %PlacementFrames{primary: [primary]}

    assert %{
             evidence_refs: [
               ^interval_ref,
               ^source_event_ref
             ]
           } = FrameEvidence.inspect(placement_frames, "link.rf_lock_state")
  end

  test "matches primary and overlay frames by observable_ids metadata" do
    primary = %Frame{
      frame_id: "req-1:connection_state_history",
      source: :operational_observables,
      shape: :events,
      fields: [],
      meta: %{
        observable_ids: ["comms.transport.connection_state", "ground.station.connection_state"]
      }
    }

    overlay = %Frame{
      frame_id: "limits:connection_state",
      source: :limits,
      shape: :events,
      fields: [],
      meta: %{observable_ids: ["ground.station.connection_state"]}
    }

    unrelated_overlay = %Frame{
      frame_id: "limits:rf_state",
      source: :limits,
      shape: :events,
      fields: [],
      meta: %{observable_ids: ["link.rf_lock_state"]}
    }

    placement_frames = %PlacementFrames{
      primary: [primary],
      overlays: %{limits: [overlay, unrelated_overlay]}
    }

    assert %{
             frame: ^primary,
             overlay_frames: [^overlay],
             frames: [^primary, ^overlay]
           } = FrameEvidence.inspect(placement_frames, "ground.station.connection_state")
  end

  test "returns nil when no primary frame matches the requested observable" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "req-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          meta: %{observable_id: "HK.counter"}
        }
      ]
    }

    assert FrameEvidence.inspect(placement_frames, "OTHER.counter") == nil
  end
end
