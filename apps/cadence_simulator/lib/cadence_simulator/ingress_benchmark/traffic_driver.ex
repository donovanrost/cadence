defmodule CadenceSimulator.IngressBenchmark.TrafficDriver do
  @moduledoc """
  Deterministic, byte-budgeted TCP source for ingress benchmark scenarios.
  """

  alias CadenceSimulator.IngressBenchmark.{DeterministicPattern, Manifest, Preflight}

  @default_connect_timeout_ms 5_000
  @default_send_timeout_ms 1_000
  @socket_buffer 4_194_304

  @doc false
  @spec target_rate_met?(non_neg_integer(), pos_integer(), pos_integer(), number()) :: boolean()
  def target_rate_met?(accepted_bytes, duration_us, target_bps, minimum_rate_ratio)
      when is_integer(accepted_bytes) and accepted_bytes >= 0 and is_integer(duration_us) and
             duration_us > 0 and is_integer(target_bps) and target_bps > 0 and
             is_number(minimum_rate_ratio) do
    accepted_bytes * 8 * 1_000_000 / duration_us >= target_bps * minimum_rate_ratio
  end

  @spec run(Preflight.t(), keyword()) :: {:ok, map()} | {:error, term(), map()}
  def run(%Preflight{} = preflight, opts) when is_list(opts) do
    with {:ok, config} <- config(preflight.manifest),
         {:ok, pattern} <-
           DeterministicPattern.new(config.seed, config.pattern_size_bytes, config.corpus_id),
         {:ok, transport} <- open_transport(opts) do
      try do
        execute(preflight, config, pattern, transport, opts)
      after
        transport.close.()
      end
    else
      {:error, reason} ->
        {:error, reason, failure_report(preflight, reason)}
    end
  end

  defp execute(preflight, config, pattern, transport, opts) do
    started_at = DateTime.utc_now()
    started_us = System.monotonic_time(:microsecond)
    deadline_us = started_us + preflight.safety.max_wall_clock_seconds * 1_000_000

    initial_state = %{
      accepted_bytes: 0,
      attempted_bytes: 0,
      block_count: 0,
      deadline_us: deadline_us,
      hash_context: :crypto.hash_init(:sha256),
      phase_reports: [],
      source_offset: 0
    }

    case run_phases(config.phases, initial_state, config, pattern, transport, opts) do
      {:ok, state} ->
        {:ok, report(preflight, pattern, state, started_at, started_us, "passed", nil)}

      {:error, reason, state} ->
        {:error, reason,
         report(preflight, pattern, state, started_at, started_us, "failed", reason)}
    end
  end

  defp run_phases([], state, _config, _pattern, _transport, _opts), do: {:ok, state}

  defp run_phases([phase | rest], state, config, pattern, transport, opts) do
    phase_started_us = System.monotonic_time(:microsecond)

    case run_phase(phase, state, phase_started_us, config, pattern, transport, opts) do
      {:ok, next_state, phase_report} ->
        run_phases(
          rest,
          %{next_state | phase_reports: [phase_report | next_state.phase_reports]},
          config,
          pattern,
          transport,
          opts
        )

      {:error, reason, next_state, phase_report} ->
        {:error, reason, %{next_state | phase_reports: [phase_report | next_state.phase_reports]}}
    end
  end

  defp run_phase(phase, state, phase_started_us, config, pattern, transport, opts) do
    pace? = Keyword.get(opts, :pace?, true)
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)

    context = %{
      config: config,
      pace?: pace?,
      pattern: pattern,
      phase: phase,
      phase_started_us: phase_started_us,
      sleep_fun: sleep_fun,
      transport: transport
    }

    case send_phase_bytes(0, state, context) do
      {:ok, next_state} ->
        if pace? do
          sleep_until(
            phase_started_us + phase.duration_seconds * 1_000_000,
            sleep_fun
          )
        end

        phase_report = phase_report(phase, next_state, state, phase_started_us, "passed")

        cond do
          System.monotonic_time(:microsecond) >= next_state.deadline_us ->
            {:error, :max_wall_clock_exceeded, next_state, %{phase_report | status: "failed"}}

          context.pace? and not phase_report.target_rate_met ->
            {:error, {:target_rate_not_met, phase.name}, next_state,
             %{phase_report | status: "failed"}}

          true ->
            {:ok, next_state, phase_report}
        end

      {:error, reason, next_state} ->
        {:error, reason, next_state,
         phase_report(phase, next_state, state, phase_started_us, "failed")}
    end
  end

  defp send_phase_bytes(sent, state, %{phase: %{target_bytes: target_bytes}})
       when sent >= target_bytes,
       do: {:ok, state}

  defp send_phase_bytes(sent, state, context) do
    %{config: config, pattern: pattern, phase: phase, transport: transport} = context

    if System.monotonic_time(:microsecond) >= state.deadline_us do
      {:error, :max_wall_clock_exceeded, state}
    else
      if context.pace? and sent > 0 do
        target_us = div(sent * 8 * 1_000_000, phase.target_bps)
        sleep_until(context.phase_started_us + target_us, context.sleep_fun)
      end

      chunk_size = min(config.block_size_bytes, phase.target_bytes - sent)
      chunk = DeterministicPattern.slice(pattern, state.source_offset, chunk_size)
      attempted_state = %{state | attempted_bytes: state.attempted_bytes + chunk_size}

      case transport.send.(chunk) do
        :ok ->
          next_state = %{
            attempted_state
            | accepted_bytes: attempted_state.accepted_bytes + chunk_size,
              block_count: attempted_state.block_count + 1,
              hash_context: :crypto.hash_update(attempted_state.hash_context, chunk),
              source_offset: attempted_state.source_offset + chunk_size
          }

          send_phase_bytes(sent + chunk_size, next_state, context)

        {:error, reason} ->
          {:error, {:send_failed, reason}, attempted_state}
      end
    end
  end

  defp config(%Manifest{} = manifest) do
    seed = Manifest.get(manifest, [:traffic, :seed])
    corpus_id = Manifest.get(manifest, [:traffic, :corpus_id], "deterministic-pattern-v1")
    block_size_bytes = Manifest.get(manifest, [:traffic, :block_size_bytes])
    pattern_size_bytes = Manifest.get(manifest, [:traffic, :pattern_size_bytes], 65_536)
    minimum_rate_ratio = Manifest.get(manifest, [:traffic, :minimum_rate_ratio], 0.99)
    phases = Manifest.get(manifest, [:traffic, :phases], [])

    cond do
      not is_integer(seed) or seed < 0 ->
        {:error, "traffic.seed must be a non-negative integer"}

      not is_integer(block_size_bytes) or block_size_bytes <= 0 ->
        {:error, "traffic.block_size_bytes must be a positive integer"}

      not is_number(minimum_rate_ratio) or minimum_rate_ratio <= 0 or minimum_rate_ratio > 1 ->
        {:error, "traffic.minimum_rate_ratio must be greater than 0 and no greater than 1"}

      true ->
        {:ok,
         %{
           corpus_id: corpus_id,
           seed: seed,
           block_size_bytes: block_size_bytes,
           pattern_size_bytes: pattern_size_bytes,
           phases: Enum.map(phases, &phase_config(&1, minimum_rate_ratio))
         }}
    end
  end

  defp phase_config(phase, minimum_rate_ratio) do
    duration_seconds = field(phase, :duration_seconds)
    target_bps = field(phase, :target_bps)

    %{
      name: field(phase, :name) || "unnamed",
      duration_seconds: duration_seconds,
      target_bps: target_bps,
      target_bytes: div(target_bps * duration_seconds + 7, 8),
      minimum_rate_ratio: minimum_rate_ratio
    }
  end

  defp open_transport(opts) do
    case Keyword.get(opts, :send_fun) do
      send_fun when is_function(send_fun, 1) ->
        {:ok, %{send: send_fun, close: Keyword.get(opts, :close_fun, fn -> :ok end)}}

      nil ->
        connect_transport(opts)
    end
  end

  defp connect_transport(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    connect_timeout_ms = Keyword.get(opts, :connect_timeout_ms, @default_connect_timeout_ms)
    send_timeout_ms = Keyword.get(opts, :send_timeout_ms, @default_send_timeout_ms)
    deadline_ms = System.monotonic_time(:millisecond) + connect_timeout_ms

    socket_opts = [
      :binary,
      packet: :raw,
      active: false,
      nodelay: true,
      send_timeout: send_timeout_ms,
      send_timeout_close: true,
      sndbuf: @socket_buffer,
      buffer: @socket_buffer
    ]

    with {:ok, socket} <- connect_until(host, port, socket_opts, deadline_ms) do
      {:ok,
       %{
         send: &:gen_tcp.send(socket, &1),
         close: fn -> :gen_tcp.close(socket) end
       }}
    end
  end

  defp connect_until(host, port, socket_opts, deadline_ms) do
    remaining_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    case :gen_tcp.connect(String.to_charlist(host), port, socket_opts, min(remaining_ms, 250)) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, _reason} when remaining_ms > 0 ->
        Process.sleep(min(remaining_ms, 50))
        connect_until(host, port, socket_opts, deadline_ms)

      {:error, reason} ->
        {:error, {:connect_failed, reason}}
    end
  end

  defp sleep_until(target_us, sleep_fun) do
    remaining_us = target_us - System.monotonic_time(:microsecond)

    if remaining_us >= 1_000 do
      sleep_fun.(div(remaining_us, 1_000))
      sleep_until(target_us, sleep_fun)
    end
  end

  defp phase_report(phase, state, previous_state, started_us, status) do
    duration_us = max(System.monotonic_time(:microsecond) - started_us, 1)
    accepted_bytes = state.accepted_bytes - previous_state.accepted_bytes
    observed_bps = accepted_bytes * 8 * 1_000_000 / duration_us

    %{
      name: phase.name,
      status: status,
      target_bps: phase.target_bps,
      target_bytes: phase.target_bytes,
      minimum_rate_ratio: phase.minimum_rate_ratio,
      minimum_acceptable_bps: phase.target_bps * phase.minimum_rate_ratio,
      target_rate_met:
        target_rate_met?(
          accepted_bytes,
          duration_us,
          phase.target_bps,
          phase.minimum_rate_ratio
        ),
      observed_bps: observed_bps,
      accepted_bytes: accepted_bytes,
      duration_us: duration_us
    }
  end

  defp report(preflight, pattern, state, started_at, started_us, status, reason) do
    %{
      status: status,
      manifest_sha256: preflight.manifest.sha256,
      pattern_sha256: pattern.sha256,
      started_at: DateTime.to_iso8601(started_at),
      duration_us: max(System.monotonic_time(:microsecond) - started_us, 0),
      source_end_offset: state.attempted_bytes,
      transport_accepted_end_offset: state.accepted_bytes,
      block_count: state.block_count,
      stream_sha256: finalize_hash(state.hash_context),
      phases: Enum.reverse(state.phase_reports),
      error: if(is_nil(reason), do: nil, else: inspect(reason))
    }
  end

  defp failure_report(preflight, reason) do
    %{
      status: "failed",
      manifest_sha256: preflight.manifest.sha256,
      source_end_offset: 0,
      transport_accepted_end_offset: 0,
      block_count: 0,
      phases: [],
      error: inspect(reason)
    }
  end

  defp finalize_hash(context) do
    context
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_value, _key), do: nil
end
