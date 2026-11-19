defmodule Cadence.IngressJournal.FileSystemResumeTest do
  @moduledoc """
  A consumer's read position vs its durable resume point (domain's partial-frame fix, 11-15): a
  consumer holding a partial frame acks what it has read with an earlier `resume_offset:`, and
  the journal keeps every byte from that point's entry until the consumer is truly past it.
  """
  use ExUnit.Case, async: true

  alias Cadence.IngressJournal.FileSystem

  setup %{tmp_dir: tmp_dir} do
    binding = "provider-#{System.unique_integer([:positive])}"
    name = {:via, Registry, {Cadence.Runtime.Registry, {:journal_resume_test, binding}}}

    opts = [
      mission_id: "mission-journal-resume",
      realized_contact_id: "contact-journal-resume",
      path_id: "path-journal-resume",
      name: name,
      provider_binding_id: binding,
      base_path: tmp_dir,
      durability: :sync,
      max_bytes: 4_096,
      segment_bytes: 512,
      checkpoint_interval_ms: 10
    ]

    %{name: name, opts: opts, binding: binding}
  end

  @tag :tmp_dir
  test "an ack with an earlier resume point reads on, but keeps and resumes from that entry",
       ctx do
    start_supervised!({FileSystem, ctx.opts})
    [first, second, third] = append!(ctx, 3)

    # Read through the second entry; a frame starting 10 bytes into the second is incomplete.
    resume = second.start_offset + 10

    assert :ok =
             FileSystem.acknowledge(ctx.name, :processing, second.end_offset,
               resume_offset: resume
             )

    assert :ok = FileSystem.acknowledge(ctx.name, :archive, third.end_offset)

    # Live reading goes on from the read position.
    assert {:ok, [next]} = FileSystem.next_entries(ctx.name, :processing, 10, 10_000)
    assert next.start_offset == third.start_offset
    assert {:ok, ^resume} = FileSystem.resume_offset(ctx.name, :processing)

    assert_eventually(fn ->
      assert {:ok, snapshot} = FileSystem.snapshot(ctx.name)
      assert snapshot.durable_cursors.processing == second.start_offset
      assert snapshot.resume_points.processing == %{boundary: second.start_offset, resume: resume}
      # The first entry is truly done: its segment goes; the second's stays.
      refute File.exists?(first.segment_path)
      assert File.exists?(second.segment_path)
    end)

    assert %{version: 1, cursors: %{processing: boundary}, resume: %{processing: ^resume}} =
             checkpoint(ctx)

    assert boundary == second.start_offset

    # A restart reads from that entry, and says how far into it the work was done.
    restart!(ctx)
    assert {:ok, [again | _]} = FileSystem.next_entries(ctx.name, :processing, 10, 10_000)
    assert again.start_offset == second.start_offset
    assert {:ok, ^resume} = FileSystem.resume_offset(ctx.name, :processing)
  end

  @tag :tmp_dir
  test "a resume point on an entry start is that boundary; without one it is the ack", ctx do
    start_supervised!({FileSystem, ctx.opts})
    [first, second] = append!(ctx, 2)

    assert :ok =
             FileSystem.acknowledge(ctx.name, :processing, second.end_offset,
               resume_offset: second.start_offset
             )

    assert {:ok, %{resume_points: %{processing: %{boundary: b, resume: r}}}} =
             FileSystem.snapshot(ctx.name)

    assert b == second.start_offset and r == second.start_offset
    assert first.end_offset == second.start_offset

    # The archive acks as always: its resume point is its read position.
    assert :ok = FileSystem.acknowledge(ctx.name, :archive, second.end_offset)
    assert {:ok, end_offset} = FileSystem.resume_offset(ctx.name, :archive)
    assert end_offset == second.end_offset
  end

  @tag :tmp_dir
  test "refuses a resume point past the ack, going backwards, or for several consumers", ctx do
    start_supervised!({FileSystem, ctx.opts})
    [first, second] = append!(ctx, 2)
    mid = first.start_offset + 5

    assert {:error, {:ingress_journal_resume_beyond_ack, _, _}} =
             FileSystem.acknowledge(ctx.name, :processing, first.end_offset,
               resume_offset: first.end_offset + 1
             )

    assert :ok =
             FileSystem.acknowledge(ctx.name, :processing, first.end_offset, resume_offset: mid)

    assert {:error, {:ingress_journal_resume_regression, :processing, _, ^mid}} =
             FileSystem.acknowledge(ctx.name, :processing, second.end_offset,
               resume_offset: mid - 1
             )

    assert {:error, {:ingress_journal_resume_requires_one_consumer, _}} =
             FileSystem.acknowledge(ctx.name, [:processing, :archive], second.end_offset,
               resume_offset: second.end_offset
             )
  end

  @tag :tmp_dir
  test "a stream isn't sealed or drained on disk until the resume point reaches the tail", ctx do
    start_supervised!({FileSystem, Keyword.put(ctx.opts, :checkpoint_interval_ms, 60_000)})
    [entry] = append!(ctx, 1)
    tail = entry.end_offset

    assert :ok = FileSystem.acknowledge(ctx.name, :archive, tail)

    assert :ok =
             FileSystem.acknowledge(ctx.name, :processing, tail,
               resume_offset: entry.start_offset + 3
             )

    assert {:error, {:journal_not_drained, _, _}} = FileSystem.seal(ctx.name)

    {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    stop!(ctx)

    assert {:not_drained, {:cursors_behind, [processing: 0], ^tail}, _bytes} =
             FileSystem.stored_stream_drain(snapshot.stream_path, snapshot.stream_id)

    # The consumer gives up the incomplete frame at the end: resume = tail.
    start_supervised!({FileSystem, Keyword.put(ctx.opts, :checkpoint_interval_ms, 60_000)})
    assert {:ok, [_entry]} = FileSystem.next_entries(ctx.name, :processing, 10, 10_000)
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, tail, resume_offset: tail)
    assert {:ok, %{tail: ^tail}} = FileSystem.seal(ctx.name)
    stop!(ctx)

    assert {:drained, _bytes} =
             FileSystem.stored_stream_drain(snapshot.stream_path, snapshot.stream_id)
  end

  @tag :tmp_dir
  test "an older cursors.term (no resume key) reads as resume = boundary", ctx do
    start_supervised!({FileSystem, ctx.opts})
    [first, _second] = append!(ctx, 2)
    assert :ok = FileSystem.acknowledge(ctx.name, :processing, first.end_offset)
    assert :ok = FileSystem.acknowledge(ctx.name, :archive, first.end_offset)

    assert_eventually(fn ->
      checkpoint = checkpoint(ctx)
      assert checkpoint.cursors == %{processing: first.end_offset, archive: first.end_offset}
      # Nothing differs from its boundary: the file is exactly what older code writes.
      refute Map.has_key?(checkpoint, :resume)
    end)

    # And a file written by older code, exactly: version 1, cursors only.
    {:ok, snapshot} = FileSystem.snapshot(ctx.name)
    stop!(ctx)

    File.write!(
      Path.join(snapshot.stream_path, "cursors.term"),
      :erlang.term_to_binary(%{
        version: 1,
        cursors: %{processing: first.end_offset, archive: first.end_offset},
        next_offset: snapshot.next_offset,
        next_sequence: 2
      })
    )

    start_supervised!({FileSystem, ctx.opts})
    assert {:ok, resume} = FileSystem.resume_offset(ctx.name, :processing)
    assert resume == first.end_offset
    assert {:ok, [next]} = FileSystem.next_entries(ctx.name, :processing, 10, 10_000)
    assert next.start_offset == first.end_offset
  end

  defp append!(ctx, count) do
    for byte <- 1..count do
      {:ok, entry} =
        FileSystem.append(ctx.name, :binary.copy(<<byte>>, 80), DateTime.utc_now(), %{})

      entry
    end
  end

  defp checkpoint(ctx) do
    {:ok, snapshot} = FileSystem.snapshot(ctx.name)

    snapshot.stream_path
    |> Path.join("cursors.term")
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
  end

  defp stop!(ctx), do: :ok = stop_supervised({:ingress_journal, ctx.binding})

  defp restart!(ctx) do
    stop!(ctx)
    start_supervised!({FileSystem, ctx.opts})
  end

  defp assert_eventually(assertion, attempts \\ 50)
  defp assert_eventually(assertion, 1), do: assertion.()

  defp assert_eventually(assertion, attempts) do
    assertion.()
  rescue
    _not_yet in [ExUnit.AssertionError, File.Error] ->
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
  end
end
