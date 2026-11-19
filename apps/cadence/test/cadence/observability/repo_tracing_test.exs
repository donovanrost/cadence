defmodule Cadence.Observability.RepoTracingTest do
  @moduledoc """
  RepoTracing finds the same parent context OpentelemetryEcto did, without copying any process
  dictionary (step 4, 11-15).
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Observability
  alias Cadence.Observability.RepoTracing

  # The library's lookup, for comparison: whole-dictionary copies.
  defp library_parent_context do
    case OpentelemetryProcessPropagator.fetch_ctx(self()) do
      :undefined -> OpentelemetryProcessPropagator.fetch_parent_ctx(1, :"$callers")
      context -> context
    end
  end

  test "inside a span, the process's own context, as the library found it" do
    Observability.with_root_span("test.repo_tracing.own", %{}, fn ->
      assert RepoTracing.parent_context() != :undefined
      assert RepoTracing.parent_context() == library_parent_context()
      assert RepoTracing.parent_context() == OpenTelemetry.Ctx.get_current()
    end)
  end

  test "in a Task with no context of its own, its caller's" do
    Observability.with_root_span("test.repo_tracing.caller", %{}, fn ->
      caller = OpenTelemetry.Ctx.get_current()

      {ours, library} =
        Task.async(fn -> {RepoTracing.parent_context(), library_parent_context()} end)
        |> Task.await()

      assert ours == caller
      assert ours == library
    end)
  end

  test "with no context anywhere, :undefined, like the library" do
    {ours, library} =
      Task.async(fn -> {RepoTracing.parent_context(), library_parent_context()} end)
      |> Task.await()

    assert ours == library
  end

  test "a caller that's gone is :undefined, not a crash" do
    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _reason}

    {ours, _library} =
      Task.async(fn ->
        Process.put(:"$callers", [dead])
        {RepoTracing.parent_context(), :ignored}
      end)
      |> Task.await()

    assert ours == :undefined
  end
end
