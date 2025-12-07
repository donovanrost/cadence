defmodule Cadence.Procedures.Dag.CancellationTokenTest do
  use ExUnit.Case, async: true

  alias Cadence.Procedures.Dag.CancellationToken

  describe "new/0" do
    test "creates a token in the :none state" do
      token = CancellationToken.new()
      assert CancellationToken.check(token) == :none
    end
  end

  describe "request_pause/1" do
    test "sets pause signal from :none state" do
      token = CancellationToken.new()
      assert :ok = CancellationToken.request_pause(token)
      assert CancellationToken.check(token) == :pause
    end

    test "returns :already_signaled when pause is already set" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_pause(token)
      assert :already_signaled = CancellationToken.request_pause(token)
    end

    test "returns :already_signaled when abort is already set" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_abort(token)
      assert :already_signaled = CancellationToken.request_pause(token)
    end
  end

  describe "request_abort/1" do
    test "sets abort signal from :none state" do
      token = CancellationToken.new()
      assert :ok = CancellationToken.request_abort(token)
      assert CancellationToken.check(token) == :abort
    end

    test "abort overrides pause" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_pause(token)
      assert CancellationToken.check(token) == :pause

      :ok = CancellationToken.request_abort(token)
      assert CancellationToken.check(token) == :abort
    end
  end

  describe "clear/1" do
    test "clears pause signal" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_pause(token)
      :ok = CancellationToken.clear(token)
      assert CancellationToken.check(token) == :none
    end

    test "clears abort signal" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_abort(token)
      :ok = CancellationToken.clear(token)
      assert CancellationToken.check(token) == :none
    end
  end

  describe "signaled?/1" do
    test "returns false when no signal" do
      token = CancellationToken.new()
      refute CancellationToken.signaled?(token)
    end

    test "returns true when pause is set" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_pause(token)
      assert CancellationToken.signaled?(token)
    end

    test "returns true when abort is set" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_abort(token)
      assert CancellationToken.signaled?(token)
    end
  end

  describe "pause_requested?/1" do
    test "returns true only for pause" do
      token = CancellationToken.new()
      refute CancellationToken.pause_requested?(token)

      :ok = CancellationToken.request_pause(token)
      assert CancellationToken.pause_requested?(token)
    end

    test "returns false for abort" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_abort(token)
      refute CancellationToken.pause_requested?(token)
    end
  end

  describe "abort_requested?/1" do
    test "returns true only for abort" do
      token = CancellationToken.new()
      refute CancellationToken.abort_requested?(token)

      :ok = CancellationToken.request_abort(token)
      assert CancellationToken.abort_requested?(token)
    end

    test "returns false for pause" do
      token = CancellationToken.new()
      :ok = CancellationToken.request_pause(token)
      refute CancellationToken.abort_requested?(token)
    end
  end

  describe "concurrent access" do
    test "signals are immediately visible across processes" do
      token = CancellationToken.new()

      # Start a watcher process
      parent = self()

      watcher =
        spawn(fn ->
          # Poll until signaled or timeout
          result =
            Enum.reduce_while(1..100, :none, fn _, _acc ->
              case CancellationToken.check(token) do
                :none ->
                  Process.sleep(10)
                  {:cont, :none}

                signal ->
                  {:halt, signal}
              end
            end)

          send(parent, {:watcher_result, result})
        end)

      # Give watcher time to start polling
      Process.sleep(50)

      # Signal pause
      :ok = CancellationToken.request_pause(token)

      # Watcher should see it
      assert_receive {:watcher_result, :pause}, 500

      # Cleanup
      if Process.alive?(watcher), do: Process.exit(watcher, :kill)
    end

    test "multiple concurrent pause requests are safe" do
      token = CancellationToken.new()

      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            CancellationToken.request_pause(token)
          end)
        end

      results = Task.await_many(tasks)

      # Exactly one should succeed, rest should get :already_signaled
      assert Enum.count(results, &(&1 == :ok)) == 1
      assert Enum.count(results, &(&1 == :already_signaled)) == 9
      assert CancellationToken.check(token) == :pause
    end
  end
end
