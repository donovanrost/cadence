defmodule Cadence.Protocol.RecordArchiveTest do
  use ExUnit.Case, async: true

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Protocol.RecordArchive.{FileSystem, Postgres}
  alias Cadence.Protocol.RecordArchive.FileSystem.Writer
  alias Cadence.Replay.Scope

  @instance_name Cadence.Protocol.RecordArchiveTest.Writer

  test "policy and child spec retain explicit backend instance state" do
    base_path = "/tmp/cadence-record-archive-facade"

    policy =
      RecordArchive.policy(
        module: FileSystem,
        name: @instance_name,
        instance_id: "facade-test",
        base_path: base_path,
        repo: Cadence.Repo
      )

    assert policy == %{
             backend: FileSystem,
             backend_opts: [
               name: @instance_name,
               instance_id: "facade-test",
               base_path: base_path,
               repo: Cadence.Repo
             ]
           }

    assert %{
             id: @instance_name,
             start: {Writer, :start_link, [backend_opts]}
           } = RecordArchive.child_spec(policy)

    assert backend_opts == policy.backend_opts
    assert RecordArchive.policy([]) == %{backend: Postgres, backend_opts: []}

    assert %{id: Writer, start: {Writer, :start_link, [[base_path: ^base_path]]}} =
             Writer.child_spec(base_path: base_path)
  end

  test "facade passes backend options through option-aware calls and batch fallback" do
    raw_evidence =
      RawEvidence.new(%{
        evidence_id: "record-archive-facade-evidence",
        mission_id: "record-archive-facade-mission",
        protocol_family: :tm,
        direction: :downlink,
        raw: <<1>>,
        receipt_time: DateTime.from_unix!(1_700_000_000, :second)
      })

    backend_opts = [test_pid: self(), instance_id: "facade-option-aware"]
    policy = %{backend: __MODULE__, backend_opts: backend_opts}
    scope = Scope.new(%{})

    assert %Multi{} =
             RecordArchive.persist_records_multi(policy, Multi.new(), raw_evidence, [], [])

    assert_receive {:persist_records_multi, ^backend_opts}

    assert :ok = RecordArchive.persist_records(policy, raw_evidence, [], [])
    assert_receive {:persist_records, ^backend_opts}

    assert :ok = RecordArchive.persist_records_many(policy, [{raw_evidence, [], []}])
    assert_receive {:persist_records, ^backend_opts}

    assert {:ok, []} =
             RecordArchive.fetch_packet_records(policy, raw_evidence.mission_id, scope)

    assert_receive {:fetch_packet_records, ^backend_opts}

    assert {:ok, []} =
             RecordArchive.fetch_transfer_frame_records(policy, raw_evidence.mission_id, scope)

    assert_receive {:fetch_transfer_frame_records, ^backend_opts}

    assert :ok = RecordArchive.flush(policy, raw_evidence.mission_id)
    assert_receive {:flush, ^backend_opts}

    assert :ok = RecordArchive.reset(policy)
    assert_receive {:reset, ^backend_opts}

    assert %{queue_depth: 17} = RecordArchive.stats(policy, raw_evidence.mission_id)
    assert_receive {:stats, ^backend_opts}

    assert :ok = RecordArchive.reset_stats(policy, raw_evidence.mission_id)
    assert_receive {:reset_stats, ^backend_opts}
  end

  def persist_records_multi(%Multi{} = multi, %RawEvidence{}, [], [], backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:persist_records_multi, backend_opts})
    multi
  end

  def persist_records(%RawEvidence{}, [], [], backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:persist_records, backend_opts})
    :ok
  end

  def fetch_packet_records(_mission_id, %Scope{}, backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:fetch_packet_records, backend_opts})
    {:ok, []}
  end

  def fetch_transfer_frame_records(_mission_id, %Scope{}, backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:fetch_transfer_frame_records, backend_opts})
    {:ok, []}
  end

  def flush(_mission_id, backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:flush, backend_opts})
    :ok
  end

  def reset(backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:reset, backend_opts})
    :ok
  end

  def stats(_mission_id, backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:stats, backend_opts})
    %{queue_depth: 17}
  end

  def reset_stats(_mission_id, backend_opts) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:reset_stats, backend_opts})
    :ok
  end
end
