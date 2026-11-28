defmodule Cadence.Persistence.Retention.SweeperTest do
  use Cadence.DataCase, async: false

  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.TestSupport.RetentionLock

  # A rule of `n` chunks of 10 rows, then done; the cursor counts the chunks swept.
  defmodule CountingRule do
    @behaviour Cadence.Persistence.Retention.Rule

    @impl true
    def name, do: :counting_test_rule
    @impl true
    def enabled?(_settings), do: true
    @impl true
    def initial_cursor, do: 0

    @impl true
    def sweep_chunk(cursor, _now, settings) do
      send(Keyword.fetch!(settings, :test_pid), {:chunk, cursor})
      Process.sleep(Keyword.get(settings, :chunk_ms, 0))
      done = cursor + 1 >= Keyword.fetch!(settings, :chunks)

      {if(done, do: :done, else: :more), 10, cursor + 1,
       fn -> send(Keyword.fetch!(settings, :test_pid), {:committed, cursor}) end}
    end
  end

  defp sweep(cursor \\ 0, opts),
    do: Sweeper.sweep(CountingRule, cursor, Keyword.merge([test_pid: self(), pause_ms: 0], opts))

  test "it sweeps chunks until the rule says done, running each chunk's after-commit work" do
    assert %{chunks: 3, rows: 30, stopped: :done} = sweep(chunks: 3)
    for n <- 0..2, do: assert_received({:committed, ^n})
  end

  test "a session outside the test that holds the rule's lock makes a sweep report :locked; a lock_key of its own is unaffected (#939)" do
    # A second database session, as another run on the same test database would be.
    config = Cadence.Repo.config()
    keys = [:hostname, :port, :username, :password, :database, :socket_dir, :socket]
    {:ok, other} = Postgrex.start_link(Keyword.put(Keyword.take(config, keys), :pool_size, 1))

    Postgrex.transaction(other, fn conn ->
      Postgrex.query!(conn, "SELECT pg_advisory_xact_lock(hashtext($1))", [
        "retention:#{CountingRule.name()}"
      ])

      assert %{stopped: :locked, chunks: 0, rows: 0} = sweep(chunks: 3)

      key = RetentionLock.key(CountingRule)
      assert %{stopped: :done, chunks: 3, rows: 30} = sweep(chunks: 3, lock_key: key)
    end)
  end

  test "it stops at the budget and hands back the cursor to resume from" do
    assert %{stopped: :budget, chunks: chunks, cursor: cursor} =
             sweep(chunks: 1_000, chunk_ms: 20, budget_ms: 50)

    assert chunks >= 1 and chunks < 1_000
    assert cursor == chunks

    # Resuming from that cursor continues the walk.
    assert %{stopped: :done, rows: 10} = sweep(999, chunks: 1_000)
  end

  test "it emits a chunk event and a run event per sweep for the scorecard" do
    handler = "sweeper-test-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach_many(
      handler,
      [[:cadence, :retention, :chunk], [:cadence, :retention, :run]],
      fn event, measurements, metadata, _ ->
        send(parent, {:event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    sweep(chunks: 2)

    assert_receive {:event, [:cadence, :retention, :chunk], %{rows: 10, duration_us: us},
                    %{rule: :counting_test_rule}}

    assert is_integer(us)

    assert_receive {:event, [:cadence, :retention, :run], %{chunks: 2, rows: 20},
                    %{rule: :counting_test_rule}}
  end

  test "a failing chunk stops the sweep without raising" do
    defmodule FailingRule do
      @behaviour Cadence.Persistence.Retention.Rule
      @impl true
      def name, do: :failing_test_rule
      @impl true
      def enabled?(_settings), do: true
      @impl true
      def initial_cursor, do: nil
      @impl true
      def sweep_chunk(_cursor, _now, _settings), do: raise("boom")
    end

    assert %{stopped: {:error, "boom"}, chunks: 0} = Sweeper.sweep(FailingRule, nil, pause_ms: 0)
  end
end
