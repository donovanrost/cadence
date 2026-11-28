defmodule CadenceWeb.Console.TelemetrySampleAPITest do
  @moduledoc """
  §11c(D) D1: one sample for Investigate's Sample aside. The read runs the authorized exploration
  read and its allowlisted projection, and adds names beside the ids (nil when unresolved, never
  the id).
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.ResolutionContext
  alias Cadence.Dashboards.Sources.Telemetry
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Management.DataSources
  alias Cadence.Protocol.{Origin, PacketRecord}
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Reads.ConsoleSample
  alias Cadence.Repo
  alias Cadence.Telemetry.{HistoryStore, PhysicalSampleQuery}
  alias Cadence.TestSupport.PhysicalSampleFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    assert {:ok, _} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "sample-source",
               adapter: Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, bounded_history?: true},
               metadata: %{"display_name" => "Ground archive"}
             })

    assert {:ok, binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "sample-binding",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 realm: :flight,
                 data_source_id: "sample-source",
                 dataset: "flight"
               },
               occurred_at: ~U[2026-09-08 11:00:00Z]
             )

    sample =
      PhysicalSampleFixtures.sample(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id
      })

    storage =
      Map.merge(sample.provenance["storage"], %{
        "organization_id" => org.organization_id,
        "data_source_id" => "sample-source",
        "binding_id" => binding.binding_id
      })

    %{
      user: user,
      org: org.organization_id,
      mission: mission.mission_id,
      spacecraft: spacecraft.spacecraft_id,
      scope: scope,
      sample: %{sample | provenance: %{"storage" => storage}}
    }
  end

  # The packet the sample came from, in the protocol archive (the test archive is Postgres).
  defp archive_packet!(c, origin) do
    evidence =
      RawEvidence.new(%{
        evidence_id: c.sample.evidence_id,
        mission_id: c.mission,
        protocol_family: :tm,
        raw: <<1, 2>>,
        receipt_time: c.sample.receipt_time
      })

    Repo.insert!(RawEvidenceRow.changeset(evidence))

    Repo.insert!(
      PacketRecordRow.changeset(%PacketRecord{
        packet_id: c.sample.packet_id,
        evidence_id: c.sample.evidence_id,
        mission_id: c.mission,
        protocol_family: :tm,
        packet_kind: :space_packet,
        source_endpoint_ref: origin.source_endpoint_id,
        apid: 42,
        sequence_flags: 3,
        sequence_count: 1,
        secondary_header?: false,
        packet_data: <<1, 2>>,
        receipt_time: c.sample.receipt_time,
        provenance: %{
          origin: Origin.stored(origin),
          tm: %{scid: origin.scid, vcid: origin.vcid, map_id: origin.map_id}
        }
      })
    )
  end

  defp selection(c, receipt_time),
    do: %{
      sample_id: "sample-physical",
      point_id: "HK.counter",
      spacecraft_id: c.spacecraft,
      receipt_time: receipt_time,
      at: nil
    }

  test "a ready sample carries the projection plus names, matched on its receipt time", c do
    receipt = c.sample.receipt_time

    assert %{status: "ready", sample: sample} =
             ConsoleSample.load(c.scope, c.mission, selection(c, receipt), runtime(c))

    assert %{
             sample_id: "sample-physical",
             point_id: "HK.counter",
             quality: "suspect",
             engineering_unit: nil,
             source: %{
               realm: "flight",
               data_source_id: "sample-source",
               data_source_name: "Ground archive",
               source_binding_id: "sample-binding",
               binding_label: nil,
               binding_version: 1,
               endpoint_label: nil,
               replay_run_label: nil
             },
             record: %{
               packet_definition_id: "definition-physical",
               packet_definition_name: nil,
               validity_state: "superseded"
             }
           } = sample

    assert %{state: "ready", text: "12.34"} = sample.engineering_value
    assert_received {:physical_read, %{receipt_time: ^receipt}}
  end

  test "a sample whose packet the archive no longer holds has a null origin and says why", c do
    assert %{status: "ready", sample: sample} =
             ConsoleSample.load(
               c.scope,
               c.mission,
               selection(c, c.sample.receipt_time),
               runtime(c)
             )

    assert sample.origin == nil
    assert sample.origin_reason == "packet_not_archived"
  end

  test "a sample's origin is read back from its archived packet (#1078 E1a)", c do
    archive_packet!(c, %{
      v: 1,
      kind: :direct,
      source_endpoint_id: "endpoint-physical",
      scid: 11,
      vcid: 2,
      map_id: nil,
      apid: 42,
      relay: nil
    })

    assert %{status: "ready", sample: sample} =
             ConsoleSample.load(
               c.scope,
               c.mission,
               selection(c, c.sample.receipt_time),
               runtime(c)
             )

    assert sample.origin_reason == nil

    assert sample.origin == %{
             "v" => 1,
             "kind" => "direct",
             "source_endpoint_id" => "endpoint-physical",
             "scid" => 11,
             "vcid" => 2,
             "map_id" => nil,
             "apid" => 42,
             "relay" => nil
           }

    # It reaches the wire as JSON values.
    assert {:ok, _json} = Jason.encode(%{data: %{status: "ready", sample: sample}})
  end

  test "without a receipt time, at bounds the search to ±60 s of generation time", c do
    selection = %{selection(c, nil) | at: c.sample.generation_time}

    assert %{status: "ready"} = ConsoleSample.load(c.scope, c.mission, selection, runtime(c))
    assert_received {:physical_read, query}
    assert query.from_observed_at == DateTime.add(c.sample.generation_time, -60, :second)
    assert query.to_observed_at == DateTime.add(c.sample.generation_time, 60, :second)
  end

  test "a sample the store doesn't have is not_found, with no sample", c do
    opts = runtime(c, read: fn _query, _opts -> {:error, :not_found} end)

    assert %{status: "not_found", sample: nil} =
             ConsoleSample.load(c.scope, c.mission, selection(c, c.sample.receipt_time), opts)
  end

  test "the endpoint needs a point and a spacecraft, and a valid receipt time", c do
    path = "/api/v1/missions/#{c.mission}/telemetry/samples/sample-physical"
    conn = TestFixtures.member_conn(c.user)

    assert %{"code" => "invalid_params", "details" => details} =
             conn
             |> get(path, %{"receipt_time" => "yesterday", "at" => "soon"})
             |> json_response(422)
             |> Map.fetch!("error")

    assert Map.keys(details) |> Enum.sort() == ["at", "point_id", "receipt_time", "spacecraft_id"]
  end

  def fetch_sample(query, opts), do: Keyword.fetch!(opts, :read).(query, opts)

  defp runtime(c, overrides \\ []) do
    parent = self()

    read =
      Keyword.get(overrides, :read, fn query, _ ->
        if PhysicalSampleQuery.matches?(query, c.sample, c.org),
          do: {:ok, %{organization_id: c.org, sample: c.sample}},
          else: {:error, :not_found}
      end)

    policy =
      HistoryStore.policy(
        module: __MODULE__,
        read: fn query, opts ->
          send(parent, {:physical_read, query})
          read.(query, opts)
        end
      )

    context =
      ResolutionContext.new!(
        persisted?: true,
        validate_dashboard_contract?: true,
        source_execution_opts: [
          source_circuit_breaker?: false,
          record_source_health_events?: false,
          source_watermark_events?: false,
          source_health_events?: false,
          source_opts: %{
            telemetry: [
              history_store_policy: policy,
              latest_fun: fn _, _, _, _ -> c.sample end,
              history_fun: fn _, _, _, _ -> {:ok, [c.sample]} end,
              watermark_fun: fn _, _, _, _ -> nil end
            ]
          }
        ]
      )

    [resolution_context: context, now: ~U[2026-09-08 12:10:00Z]]
  end
end
