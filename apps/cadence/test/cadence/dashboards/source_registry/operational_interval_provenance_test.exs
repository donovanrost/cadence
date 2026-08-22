defmodule Cadence.Dashboards.SourceRegistry.OperationalIntervalProvenanceTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    SourceResult
  }

  alias Cadence.Dashboards.SourceRegistry.OperationalIntervalProvenance
  alias Cadence.OperationalEvents.EffectiveInterval

  test "selects injected binding, application, and catalog intervals at the result time" do
    parent = self()

    opts = [
      persisted?: true,
      binding_set_intervals_fun: interval_reader(parent, :binding_set),
      application_binding_intervals_fun: interval_reader(parent, :application_binding),
      catalog_revision_intervals_fun: interval_reader(parent, :catalog_revision)
    ]

    provenance =
      OperationalIntervalProvenance.build(
        request(),
        %ResolvedSourceBinding{},
        opts,
        result(~U[2026-07-19 10:00:00Z], "endpoint-1")
      )

    assert provenance.selected_operational_interval_at == ~U[2026-07-19 10:00:00Z]

    assert Enum.map(provenance.selected_operational_intervals, & &1.kind) == [
             :binding_set,
             :application_binding,
             :catalog_revision
           ]

    assert_received {:interval_read, :binding_set, "org-1", "mission-1",
                     [at: ~U[2026-07-19 10:00:00Z]]}

    assert_received {:interval_read, :application_binding, "org-1", "mission-1",
                     [at: ~U[2026-07-19 10:00:00Z], source_endpoint_ref: "endpoint-1"]}

    assert_received {:interval_read, :catalog_revision, "org-1", "mission-1",
                     [at: ~U[2026-07-19 10:00:00Z], catalog_family: :telemetry]}
  end

  test "uses a binding segment start before explicit or frame times" do
    parent = self()
    segment_time = ~U[2026-07-19 09:55:00Z]

    provenance =
      OperationalIntervalProvenance.build(
        request(),
        %ResolvedSourceBinding{segment_from: segment_time},
        [
          persisted?: true,
          operational_interval_at: ~U[2026-07-19 09:58:00Z],
          binding_set_intervals_fun: interval_reader(parent, :binding_set),
          catalog_revision_intervals_fun: fn _organization_id, _mission_id, _opts -> [] end
        ],
        result(~U[2026-07-19 10:00:00Z], nil)
      )

    assert provenance.selected_operational_interval_at == segment_time
    assert_received {:interval_read, :binding_set, "org-1", "mission-1", [at: ^segment_time]}
  end

  test "omits provenance for non-persisted source results" do
    refute OperationalIntervalProvenance.reader_configured?(:source_health, [])

    assert OperationalIntervalProvenance.build(
             request(),
             %ResolvedSourceBinding{},
             [],
             result(~U[2026-07-19 10:00:00Z], nil)
           ) == %{}
  end

  defp request do
    %PlannedSourceRequest{
      request_id: "request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry
    }
  end

  defp result(at, source_endpoint_id) do
    %SourceResult{
      frames: [
        %Frame{
          frame_id: "frame-1",
          source: :telemetry,
          shape: :long,
          fields: [
            %Field{name: "value", kind: :number, values: [42]},
            %Field{name: "time", kind: :time, values: [at]}
          ],
          meta: %{source_endpoint_id: source_endpoint_id}
        }
      ]
    }
  end

  defp interval_reader(parent, kind) do
    fn organization_id, mission_id, opts ->
      send(parent, {:interval_read, kind, organization_id, mission_id, opts})
      [interval(kind)]
    end
  end

  defp interval(kind) do
    %EffectiveInterval{
      interval_id: "#{kind}-interval-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: kind,
      subject_kind: :mission,
      subject_id: "mission-1",
      starts_at: ~U[2026-07-19 09:00:00Z],
      source_event_id: "#{kind}-event-1"
    }
  end
end
