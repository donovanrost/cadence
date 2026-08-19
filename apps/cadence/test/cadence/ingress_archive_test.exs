defmodule Cadence.IngressArchiveTest do
  use ExUnit.Case, async: true

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.{Batch, Receipt}
  alias Cadence.Replay.Scope

  test "threads backend options through option-aware callbacks and the per-evidence fallback" do
    raw_evidence = raw_evidence()

    policy =
      IngressArchive.policy(
        module: __MODULE__,
        test_pid: self(),
        raw_evidence: raw_evidence,
        instance_id: "facade-instance"
      )

    assert policy.backend_opts == [
             test_pid: self(),
             raw_evidence: raw_evidence,
             instance_id: "facade-instance"
           ]

    assert nil == IngressArchive.child_spec(policy)
    assert_receive {:archive_call, :child_spec, backend_opts}
    assert backend_opts == policy.backend_opts

    multi = Multi.new()
    assert ^multi = IngressArchive.persist_raw_evidence_multi(policy, multi, raw_evidence)
    assert_receive {:archive_call, :persist_raw_evidence_multi, ^backend_opts}

    assert :ok = IngressArchive.persist_raw_evidences(policy, [raw_evidence, raw_evidence])
    assert_receive {:archive_call, :persist_raw_evidence, ^backend_opts}
    assert_receive {:archive_call, :persist_raw_evidence, ^backend_opts}

    batch = Batch.new("facade-stream", 0, 3, [raw_evidence])
    assert {:ok, %Receipt{batch_id: batch_id}} = IngressArchive.persist_batch(policy, batch)
    assert batch_id == batch.batch_id
    assert_receive {:archive_call, :persist_batch, ^backend_opts}

    scope = Scope.new(%{evidence_ids: [raw_evidence.evidence_id]})

    assert {:ok, [^raw_evidence]} =
             IngressArchive.fetch_raw_evidences(policy, raw_evidence.mission_id, scope)

    assert_receive {:archive_call, :fetch_raw_evidences, ^backend_opts}

    assert :ok = IngressArchive.flush(policy, raw_evidence.mission_id)
    assert_receive {:archive_call, :flush, ^backend_opts}

    assert %{instance_id: "facade-instance"} =
             IngressArchive.stats(policy, raw_evidence.mission_id)

    assert_receive {:archive_call, :stats, ^backend_opts}

    assert :ok = IngressArchive.reset_stats(policy, raw_evidence.mission_id)
    assert_receive {:archive_call, :reset_stats, ^backend_opts}

    assert :ok = IngressArchive.reset(policy)
    assert_receive {:archive_call, :reset, ^backend_opts}
  end

  def child_spec(backend_opts) do
    notify(backend_opts, :child_spec)
    nil
  end

  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{}, backend_opts) do
    notify(backend_opts, :persist_raw_evidence_multi)
    multi
  end

  def persist_raw_evidence(%RawEvidence{}, backend_opts) do
    notify(backend_opts, :persist_raw_evidence)
    :ok
  end

  def persist_batch(%Batch{} = batch, backend_opts) do
    notify(backend_opts, :persist_batch)
    {:ok, Receipt.for_batch(batch, :durable)}
  end

  def fetch_raw_evidences(_mission_id, %Scope{}, backend_opts) do
    notify(backend_opts, :fetch_raw_evidences)
    {:ok, [Keyword.fetch!(backend_opts, :raw_evidence)]}
  end

  def flush(_mission_id, backend_opts) do
    notify(backend_opts, :flush)
    :ok
  end

  def reset(backend_opts) do
    notify(backend_opts, :reset)
    :ok
  end

  def stats(_mission_id, backend_opts) do
    notify(backend_opts, :stats)
    %{instance_id: Keyword.fetch!(backend_opts, :instance_id)}
  end

  def reset_stats(_mission_id, backend_opts) do
    notify(backend_opts, :reset_stats)
    :ok
  end

  defp notify(backend_opts, function) do
    send(Keyword.fetch!(backend_opts, :test_pid), {:archive_call, function, backend_opts})
  end

  defp raw_evidence do
    RawEvidence.new(%{
      evidence_id: "facade-evidence",
      mission_id: "facade-mission",
      protocol_family: :tm,
      direction: :downlink,
      raw: <<1, 2, 3>>,
      receipt_time: DateTime.from_unix!(1_701_000_000, :second)
    })
  end
end
