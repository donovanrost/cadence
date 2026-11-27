defmodule Cadence.Persistence.RetentionTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Persistence.Retention

  setup do
    saved =
      for key <- [:retention, :telemetry_observation_retention, :ingress_journal],
          do: {key, Application.get_env(:cadence, key)}

    on_exit(fn ->
      for {key, value} <- saved do
        if value == nil,
          do: Application.delete_env(:cadence, key),
          else: Application.put_env(:cadence, key, value)
      end
    end)

    :ok
  end

  test "the archives follow the observation retention unless set" do
    Application.put_env(:cadence, :telemetry_observation_retention, retention_days: 45)
    Application.delete_env(:cadence, :retention)

    assert Retention.observation_days() == 45
    assert Retention.ingress_archive_days() == 45
    assert Retention.protocol_archive_days() == 45

    Application.put_env(:cadence, :retention, ingress_archive_days: 10)
    assert Retention.ingress_archive_days() == 10
    assert Retention.protocol_archive_days() == 45
  end

  test "completed jobs keep fourteen days unless configured otherwise" do
    assert Retention.background_job_days() == 14

    Application.put_env(:cadence, :retention, background_job_days: 21)
    assert Retention.background_job_days() == 21
  end

  test "the replay horizon is the longest window a stream can be replayed from, plus the margin" do
    Application.put_env(:cadence, :telemetry_observation_retention, retention_days: 30)
    Application.put_env(:cadence, :ingress_journal, completed_stream_retention_ms: 72 * 3_600_000)
    Application.put_env(:cadence, :retention, stream_key_margin_days: 7)

    # 30 (archives) vs 3 (journal): the archives, + 7.
    assert Retention.replay_horizon_days() == 37

    Application.put_env(:cadence, :retention, ingress_archive_days: 60, stream_key_margin_days: 7)
    assert Retention.replay_horizon_days() == 67

    Application.put_env(:cadence, :retention,
      protocol_archive_days: 90,
      stream_key_margin_days: 2
    )

    assert Retention.replay_horizon_days() == 92

    # The journal can be the longest.
    Application.put_env(:cadence, :retention,
      ingress_archive_days: 1,
      protocol_archive_days: 1,
      stream_key_margin_days: 7
    )

    Application.put_env(:cadence, :ingress_journal,
      completed_stream_retention_ms: 20 * 86_400_000 + 1
    )

    assert Retention.replay_horizon_days() == 21 + 7
  end

  test "no sweepers run when retention is off, and each enabled rule gets one" do
    rules = [
      Cadence.Jobs.Retention,
      Cadence.Runtime.PartitionStreamKeys.Retention,
      Cadence.IngressArchive.Retention
    ]

    assert Retention.children(rules, enabled?: false) == []

    # The ingress archive rule needs a configured filesystem archive; the stream-key rule does not.
    children = Retention.children(rules, Keyword.merge(Retention.settings(), enabled?: true))
    assert Enum.all?(children, &match?({Cadence.Persistence.Retention.Sweeper, [rule: _]}, &1))

    assert Cadence.Runtime.PartitionStreamKeys.Retention in Enum.map(children, fn {_m, opts} ->
             opts[:rule]
           end)

    assert Cadence.Jobs.Retention in Enum.map(children, fn {_m, opts} -> opts[:rule] end)
  end
end
