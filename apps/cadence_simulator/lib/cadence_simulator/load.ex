defmodule CadenceSimulator.Load do
  @moduledoc "Drives the Provider Contact data plane into a TCP sink or a Cadence stack."

  alias CadenceSimulator.{CatalogCache, PacketEncoder, Provider}
  alias CadenceSimulator.Load.{BinaryOwners, Shape, TcpSink}
  alias CadenceSimulator.Provider.{ContactLifecycle, DeliveryProfiles, Orchestrator, Store}
  alias CadenceSimulator.Providers.DatabaseDynamics

  @definitions Path.expand("../../../../dev/catalogs/demo_spacecraft.yaml", __DIR__)
  @sites 10
  @frame_size 1115
  @packets_per_second 10
  @diagnostics_interval_seconds 10

  def run(opts, target \\ nil) do
    directory = Path.join(System.tmp_dir!(), "cadence-simulator-load-#{System.pid()}")
    File.mkdir!(directory)
    store_path = Path.join(directory, "store.ets")

    try do
      Application.put_env(:cadence_simulator, :provider_http, enabled: false)

      Application.put_env(:cadence_simulator, :provider_store,
        path: store_path,
        snapshot_observer: self()
      )

      {:ok, _apps} = Application.ensure_all_started(:cadence_simulator)
      :ok = Logger.configure(level: :warning)
      exercise(opts, store_path, target)
    after
      Application.stop(:cadence_simulator)
      report_store_termination()
      File.rm_rf!(directory)
    end
  end

  defp exercise(opts, store_path, nil) do
    fleet = Shape.fleet(opts.craft, @sites)

    active =
      for {scid, _site} <- fleet,
          Shape.in_contact?(scid, @sites, opts.shape, opts.per_site),
          do: scid

    counters = :counters.new(opts.craft * 2, [:atomics])

    sinks =
      for site <- 0..(@sites - 1),
          do: TcpSink.start_link(site, @sites, opts.craft, @frame_size, counters)

    try do
      {run, frames_per_step, rate_hz} = create_run(fleet)

      by_site =
        sinks |> Enum.map(fn {_pid, port} -> delivery_profile(run, port) end) |> List.to_tuple()

      seed_contacts(fleet, run, fn _scid, site -> elem(by_site, site) end, @sites, opts)
      :ok = Store.flush()

      await_paths(active, counters, now_ms() + 30_000)
      path_target = frames_per_step * rate_hz
      target = round(length(active) * path_target)

      IO.puts(
        "Measuring #{length(active)}/#{opts.craft} active paths over #{@sites} sites " <>
          "at #{target} frames/s for #{opts.duration}s. JSONL: #{opts.output}"
      )

      diagnostics = fn -> diagnostics(store_path, opts.binary_owners?) end
      report_diagnostics("start", diagnostics.())
      File.mkdir_p!(Path.dirname(opts.output))

      result =
        File.open!(opts.output, [:write, :utf8], fn output ->
          measure(output, active, counters, opts.duration, diagnostics)
        end)

      outcome = report(result, frames_per_step, rate_hz, length(active))
      stop_run(run["id"], diagnostics)
      outcome
    after
      for {pid, _port} <- sinks do
        Process.unlink(pid)
        Process.exit(pid, :shutdown)
      end
    end
  end

  defp exercise(opts, store_path, %{ports: ports, sites: sites, measure: measure}) do
    fleet = Shape.fleet(opts.craft, sites)

    active =
      Enum.filter(fleet, fn {scid, _site} ->
        Shape.in_contact?(scid, sites, opts.shape, opts.per_site)
      end)

    scids = Enum.map(active, &elem(&1, 0)) |> MapSet.new()

    if scids != MapSet.new(Map.keys(ports)),
      do: raise("Cadence listener SCIDs do not match the selected load shape")

    {run, frames_per_step, rate_hz} = create_run(fleet)
    profiles = Map.new(ports, fn {scid, port} -> {scid, delivery_profile(run, port)} end)
    seed_contacts(active, run, fn scid, _site -> Map.fetch!(profiles, scid) end, sites, opts)
    :ok = Store.flush()

    await_transmission(scids, now_ms() + 30_000)
    expected_fps = round(length(active) * frames_per_step * rate_hz)
    {summary, summary_path, {live, bytes}} = measure.(fn -> transmit_for(opts.duration) end)

    diagnostics = fn -> diagnostics(store_path, opts.binary_owners?) end
    stop_run(run["id"], diagnostics)

    %{
      summary: summary,
      summary_path: summary_path,
      paths_sending: live,
      paths_expected: length(active),
      frames_sent: div(bytes, @frame_size),
      frames_per_second_expected: expected_fps
    }
  end

  defp transmit_for(duration) do
    started = transmitted_bytes()
    Process.sleep(duration * 1_000)
    finished = transmitted_bytes()

    Enum.reduce(started, {0, 0}, fn {scid, before}, {live, bytes} ->
      case Map.get(finished, scid, 0) - before do
        sent when sent > 0 -> {live + 1, bytes + sent}
        _ -> {live, bytes}
      end
    end)
  end

  defp await_transmission(scids, deadline) do
    sent = transmitted_bytes()

    cond do
      scids == MapSet.new(Map.keys(sent)) ->
        sent

      now_ms() >= deadline ->
        raise "Only #{map_size(sent)}/#{MapSet.size(scids)} TCP paths sent frames"

      true ->
        Process.sleep(100)
        await_transmission(scids, deadline)
    end
  end

  defp transmitted_bytes do
    for {_, pid, :worker, _} <-
          DynamicSupervisor.which_children(CadenceSimulator.RuntimeSupervisor),
        %{frame: %{scid: scid}, send_buffer_stats: %{bytes_sent: bytes}} <- [
          CadenceSimulator.simulator_stats(pid)
        ],
        bytes > 0,
        into: %{},
        do: {scid, bytes}
  end

  defp create_run(fleet) do
    {:ok, {encoder, dynamics}} =
      CatalogCache.fetch([definitions_path: @definitions], DatabaseDynamics)

    frames = Map.new(fleet, fn {scid, _site} -> {craft_ref(scid), %{"scid" => scid}} end)

    {:ok, state} = DatabaseDynamics.init(%{catalog: dynamics})
    {:ok, values, _state} = DatabaseDynamics.generate_packet_values(state, 0)

    {:ok, packets} =
      PacketEncoder.encode_packet_values_with_sequence(encoder, "load", values, fn _apid -> 0 end)

    count = length(packets)
    if count == 0, do: raise("load catalog emitted no packets")
    frame_payload = @frame_size - 6

    frames_per_step =
      Enum.sum_by(packets, fn {_name, packet} -> ceil(byte_size(packet) / frame_payload) end)

    rate_hz = @packets_per_second / count

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => length(fleet),
        "telemetry_profile" => %{
          "definitions_path" => @definitions,
          "rate_hz" => rate_hz,
          "spacecraft_frames" => frames
        }
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 716})
    {run, frames_per_step, rate_hz}
  end

  defp delivery_profile(run, port) do
    {:ok, profile} =
      DeliveryProfiles.provision(run, %{
        "display_name" => "Load TCP receiver",
        "client_reference" => "load-site-#{port}",
        "direction" => "downlink",
        "delivery_kind" => "realtime_stream",
        "target" => %{
          "protocol" => "tcp",
          "mode" => "provider_connects",
          "host" => "127.0.0.1",
          "port" => port
        },
        "framing" => %{
          "family" => "ccsds_tm",
          "mode" => "fixed_size",
          "frame_bytes" => @frame_size
        }
      })

    {:ok, internal} = DeliveryProfiles.fetch_internal(run, profile["id"])
    internal
  end

  # Synthetic windows isolate the contact runtime from orbit prediction and booking.
  defp seed_contacts(fleet, run, profile_for, sites, opts) do
    now = DateTime.utc_now()
    active_start = DateTime.add(now, 3)
    idle_start = DateTime.add(active_start, opts.duration + 120)

    Enum.each(fleet, fn {scid, site} ->
      profile = profile_for.(scid, site)

      starts =
        if Shape.in_contact?(scid, sites, opts.shape, opts.per_site),
          do: DateTime.add(active_start, rem(div(scid - 1, sites), 10) * 100, :millisecond),
          else: idle_start

      {:ok, _contact} =
        ContactLifecycle.create(%{
          "id" => "load-contact-#{scid}",
          "run_id" => run["id"],
          "spacecraft_ref" => craft_ref(scid),
          "ground_station_ref" => "load-site-#{site}",
          "delivery_profile_ref" => profile["id"],
          "starts_at" => DateTime.to_iso8601(starts),
          "ends_at" => starts |> DateTime.add(opts.duration + 60) |> DateTime.to_iso8601(),
          "status" => "pending",
          "pass_phase" => "scheduled",
          "delivery" => %{"status" => "pending", "endpoint_ref" => profile["id"]},
          "delivery_profile_snapshot" => profile,
          "created_at" => DateTime.to_iso8601(now)
        })
    end)
  end

  defp await_paths(active, counters, deadline) do
    connected = Enum.count(active, &(:counters.get(counters, &1 * 2 - 1) > 0))

    cond do
      connected == length(active) ->
        :ok

      now_ms() < deadline ->
        Process.sleep(100)
        await_paths(active, counters, deadline)

      true ->
        raise "only #{connected}/#{length(active)} paths received frames. Check TCP and open-file limits."
    end
  end

  defp measure(output, active, counters, duration, diagnostics) do
    previous_flag = :erlang.system_flag(:scheduler_wall_time, true)
    start = now_ms()
    first = snapshot(active, counters)

    try do
      initial = %{
        previous: first,
        before_previous: nil,
        first: first,
        all_live?: true,
        peak_scheduler: 0.0,
        min_memory: first.memory_bytes,
        peak_memory: first.memory_bytes
      }

      result =
        Enum.reduce(1..duration, initial, fn second, acc ->
          Process.sleep(max(start + second * 1000 - now_ms(), 0))
          current = snapshot(active, counters)

          sample =
            second
            |> sample(acc.previous, current)
            |> maybe_add_diagnostics(diagnostics)

          :ok = IO.binwrite(output, [Jason.encode_to_iodata!(sample), "\n"])
          print_sample(sample)

          %{
            acc
            | previous: current,
              before_previous: acc.previous,
              all_live?:
                acc.all_live? and sample.active_streams == length(active) and
                  paths_progressed?(acc.before_previous, current),
              peak_scheduler: max(acc.peak_scheduler, sample.busiest_scheduler_utilization),
              min_memory: min(acc.min_memory, current.memory_bytes),
              peak_memory: max(acc.peak_memory, current.memory_bytes)
          }
        end)

      Map.put(result, :elapsed_s, (result.previous.time - start) / 1000)
    after
      :erlang.system_flag(:scheduler_wall_time, previous_flag)
    end
  end

  defp snapshot(active, counters) do
    paths =
      Enum.map(active, fn scid ->
        {scid, :counters.get(counters, scid * 2 - 1), :counters.get(counters, scid * 2)}
      end)

    %{
      time: now_ms(),
      paths: paths,
      memory_bytes: :erlang.memory(:total),
      schedulers:
        Map.new(:erlang.statistics(:scheduler_wall_time), fn {id, active, total} ->
          {id, {active, total}}
        end)
    }
  end

  defp sample(second, previous, current) do
    paths = path_deltas(previous, current)
    {busy, total, busiest} = scheduler_deltas(previous, current)
    interval = current.time - previous.time
    {frames, bytes, live} = totals(paths)

    %{
      second: second,
      interval_ms: interval,
      active_streams: Orchestrator.active_stream_count(),
      live_paths: live,
      frames: frames,
      bytes: bytes,
      frames_per_second: frames * 1000 / max(1, interval),
      scheduler_utilization: ratio(busy, total),
      busiest_scheduler_utilization: busiest,
      memory_bytes: current.memory_bytes,
      paths: paths
    }
  end

  defp maybe_add_diagnostics(sample, diagnostics) do
    if rem(sample.second, @diagnostics_interval_seconds) == 0 do
      Map.put(sample, :diagnostics, diagnostics.())
    else
      sample
    end
  end

  defp diagnostics(store_path, binary_owners?) do
    sample = %{
      store: Map.put(Store.diagnostics(), :snapshot_file_bytes, File.stat!(store_path).size),
      snapshots: drain_snapshot_samples([]),
      memory: Map.new(:erlang.memory())
    }

    if binary_owners?,
      do: Map.put(sample, :binary_owners, BinaryOwners.snapshot()),
      else: sample
  end

  defp drain_snapshot_samples(samples) do
    receive do
      {:provider_store_snapshot, sample} -> drain_snapshot_samples([sample | samples])
    after
      0 -> Enum.reverse(samples)
    end
  end

  defp stop_run(run_id, diagnostics) do
    started = System.monotonic_time(:microsecond)
    {:ok, _run} = Provider.transition_run(run_id, "stop")
    :ok = Orchestrator.reconcile()
    flush_started = System.monotonic_time(:microsecond)

    try do
      :ok = Store.flush()
    after
      flush_ended = System.monotonic_time(:microsecond)

      report_diagnostics(
        "shutdown",
        Map.merge(diagnostics.(), %{
          contact_shutdown_us: flush_started - started,
          final_flush_us: flush_ended - flush_started
        })
      )
    end
  end

  defp report_diagnostics(phase, diagnostics) do
    IO.puts("Provider store #{phase} " <> Jason.encode!(diagnostics))
  end

  defp report_store_termination do
    receive do
      {:provider_store_terminated, timings} -> report_diagnostics("terminate", timings)
    after
      0 -> :ok
    end
  end

  defp path_deltas(previous, current) do
    Enum.zip_with(previous.paths, current.paths, fn {scid, prior_frames, prior_bytes},
                                                    {scid, frames, bytes} ->
      %{scid: scid, frames: frames - prior_frames, bytes: bytes - prior_bytes}
    end)
  end

  defp paths_progressed?(nil, _current), do: true

  defp paths_progressed?(previous, current) do
    previous
    |> path_deltas(current)
    |> Enum.all?(&(&1.frames > 0))
  end

  defp scheduler_deltas(previous, current) do
    normal = :erlang.system_info(:schedulers)

    Enum.reduce(current.schedulers, {0, 0, 0.0}, fn {id, {busy, total}},
                                                    {busy_sum, total_sum, peak} ->
      if id <= normal do
        {prior_busy, prior_total} = Map.fetch!(previous.schedulers, id)
        busy = busy - prior_busy
        total = total - prior_total
        {busy_sum + busy, total_sum + total, max(peak, ratio(busy, total))}
      else
        {busy_sum, total_sum, peak}
      end
    end)
  end

  defp totals(paths) do
    Enum.reduce(paths, {0, 0, 0}, fn path, {frames, bytes, live} ->
      {frames + path.frames, bytes + path.bytes, live + if(path.frames > 0, do: 1, else: 0)}
    end)
  end

  defp print_sample(sample) do
    IO.puts(
      "#{sample.second}s #{sample.active_streams} active, #{sample.live_paths} sending " <>
        "#{round(sample.frames_per_second)} frames/s " <>
        "#{sample.bytes} bytes schedulers #{percent(sample.scheduler_utilization)}% " <>
        "busiest #{percent(sample.busiest_scheduler_utilization)}%, " <>
        "memory #{mib(sample.memory_bytes)} MiB"
    )
  end

  defp report(result, frames_per_step, rate_hz, active) do
    path_target = frames_per_step * rate_hz
    target = round(path_target * active)
    paths = path_deltas(result.first, result.previous)
    {frames, bytes, _live} = totals(paths)
    {busy, total, _busiest} = scheduler_deltas(result.first, result.previous)
    min_path_frames = Enum.min_by(paths, & &1.frames).frames
    min_path_rate = min_path_frames / result.elapsed_s
    rate = frames / result.elapsed_s
    expected_steps = result.elapsed_s * rate_hz

    # Short runs can straddle the edge of a generation step.
    min_steps = max(1, min(expected_steps * 0.98, floor(expected_steps) - 1))

    IO.puts(
      "Total #{frames} frames, #{bytes} bytes in #{Float.round(result.elapsed_s, 3)}s. " <>
        "#{Float.round(rate, 1)}/#{target} frames/s, minimum path #{Float.round(min_path_rate, 2)} frames/s. " <>
        "Scheduler mean #{percent(ratio(busy, total))}%, busiest 1s #{percent(result.peak_scheduler)}%. " <>
        "BEAM memory #{mib(result.min_memory)}–#{mib(result.peak_memory)} MiB " <>
        "(#{mib(result.first.memory_bytes)} start, #{mib(result.previous.memory_bytes)} end)."
    )

    if result.all_live? and min_path_frames >= min_steps * frames_per_step,
      do: :ok,
      else: {:error, "one or more paths stalled or delivered below the expected frame count"}
  end

  defp craft_ref(scid), do: "SC-#{String.pad_leading(Integer.to_string(scid), 3, "0")}"
  defp now_ms, do: System.monotonic_time(:millisecond)
  defp ratio(_active, total) when total <= 0, do: 0.0
  defp ratio(active, total), do: active / total
  defp mib(bytes), do: Float.round(bytes / (1024 * 1024), 1)
  defp percent(ratio), do: Float.round(ratio * 100, 2)
end
