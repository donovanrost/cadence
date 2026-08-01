defmodule CadenceSimulator.IngressBenchmark.ValidatingSink do
  @moduledoc """
  Single-stream TCP sink that validates deterministic bytes at arbitrary reads.
  """

  alias CadenceSimulator.IngressBenchmark.{DeterministicPattern, Manifest, Preflight}

  @default_timeout_ms 10_000
  @socket_buffer 4_194_304

  @spec run(Preflight.t(), keyword()) :: {:ok, map()} | {:error, term(), map()}
  def run(%Preflight{} = preflight, opts) when is_list(opts) do
    with {:ok, config} <- config(preflight),
         {:ok, pattern} <-
           DeterministicPattern.new(config.seed, config.pattern_size_bytes, config.corpus_id),
         {:ok, listener} <- listen(opts) do
      try do
        accept_and_validate(listener, preflight, pattern, config, opts)
      after
        :gen_tcp.close(listener)
      end
    else
      {:error, reason} -> {:error, reason, failure_report(preflight, reason)}
    end
  end

  defp accept_and_validate(listener, preflight, pattern, config, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    case :gen_tcp.accept(listener, timeout_ms) do
      {:ok, socket} ->
        try do
          validate_socket(socket, preflight, pattern, config.expected_bytes, timeout_ms)
        after
          :gen_tcp.close(socket)
        end

      {:error, reason} ->
        {:error, {:accept_failed, reason}, failure_report(preflight, {:accept_failed, reason})}
    end
  end

  defp validate_socket(socket, preflight, pattern, expected_bytes, timeout_ms) do
    started_at = DateTime.utc_now()
    started_us = System.monotonic_time(:microsecond)

    initial_state = %{
      actual_hash_context: :crypto.hash_init(:sha256),
      bytes_received: 0,
      chunks_received: 0,
      expected_hash_context: :crypto.hash_init(:sha256),
      first_mismatch_offset: nil
    }

    case receive_bytes(socket, pattern, expected_bytes, timeout_ms, initial_state) do
      {:ok, state} ->
        report = report(preflight, state, expected_bytes, started_at, started_us, nil)

        if report.status == "passed" do
          {:ok, report}
        else
          {:error, :validation_failed, report}
        end

      {:error, reason, state} ->
        {:error, reason, report(preflight, state, expected_bytes, started_at, started_us, reason)}
    end
  end

  defp receive_bytes(_socket, _pattern, expected_bytes, _timeout_ms, state)
       when state.bytes_received > expected_bytes,
       do: {:ok, state}

  defp receive_bytes(socket, _pattern, expected_bytes, timeout_ms, state)
       when state.bytes_received == expected_bytes do
    case :gen_tcp.recv(socket, 0, timeout_ms) do
      {:error, :closed} ->
        {:ok, state}

      {:ok, extra_bytes} ->
        next_state = %{
          state
          | actual_hash_context: :crypto.hash_update(state.actual_hash_context, extra_bytes),
            bytes_received: state.bytes_received + byte_size(extra_bytes),
            chunks_received: state.chunks_received + 1
        }

        {:ok, next_state}

      {:error, reason} ->
        {:error, {:stream_end_failed, reason}, state}
    end
  end

  defp receive_bytes(socket, pattern, expected_bytes, timeout_ms, state) do
    case :gen_tcp.recv(socket, 0, timeout_ms) do
      {:ok, bytes} ->
        expected = DeterministicPattern.slice(pattern, state.bytes_received, byte_size(bytes))

        mismatch =
          state.first_mismatch_offset ||
            first_mismatch_offset(bytes, expected, state.bytes_received)

        next_state = %{
          state
          | actual_hash_context: :crypto.hash_update(state.actual_hash_context, bytes),
            bytes_received: state.bytes_received + byte_size(bytes),
            chunks_received: state.chunks_received + 1,
            expected_hash_context: :crypto.hash_update(state.expected_hash_context, expected),
            first_mismatch_offset: mismatch
        }

        receive_bytes(socket, pattern, expected_bytes, timeout_ms, next_state)

      {:error, reason} ->
        {:error, {:receive_failed, reason}, state}
    end
  end

  defp config(%Preflight{} = preflight) do
    manifest = preflight.manifest
    seed = Manifest.get(manifest, [:traffic, :seed])
    corpus_id = Manifest.get(manifest, [:traffic, :corpus_id], "deterministic-pattern-v1")
    pattern_size_bytes = Manifest.get(manifest, [:traffic, :pattern_size_bytes], 65_536)
    expected_bytes = preflight.safety.planned_source_bytes

    if is_integer(expected_bytes) and expected_bytes > 0 do
      {:ok,
       %{
         corpus_id: corpus_id,
         seed: seed,
         pattern_size_bytes: pattern_size_bytes,
         expected_bytes: expected_bytes
       }}
    else
      {:error, "validating sink requires a positive planned source byte count"}
    end
  end

  defp listen(opts) do
    host = Keyword.get(opts, :host, "0.0.0.0")
    port = Keyword.fetch!(opts, :port)

    with {:ok, ip} <- resolve_ip(host) do
      :gen_tcp.listen(port, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        backlog: 16,
        ip: ip,
        recbuf: @socket_buffer,
        buffer: @socket_buffer
      ])
    end
  end

  defp resolve_ip(host) do
    host_charlist = String.to_charlist(host)

    case :inet.parse_address(host_charlist) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> :inet.getaddr(host_charlist, :inet)
    end
  end

  defp first_mismatch_offset(actual, expected, _base_offset) when actual == expected, do: nil

  defp first_mismatch_offset(actual, expected, base_offset) do
    find_mismatch(actual, expected, base_offset)
  end

  defp find_mismatch(<<actual, actual_rest::binary>>, <<expected, expected_rest::binary>>, offset) do
    if actual == expected do
      find_mismatch(actual_rest, expected_rest, offset + 1)
    else
      offset
    end
  end

  defp find_mismatch(<<>>, <<>>, _offset), do: nil

  defp report(preflight, state, expected_bytes, started_at, started_us, reason) do
    actual_sha256 = finalize_hash(state.actual_hash_context)
    expected_sha256 = finalize_hash(state.expected_hash_context)

    passed? =
      is_nil(reason) and state.bytes_received == expected_bytes and
        is_nil(state.first_mismatch_offset) and actual_sha256 == expected_sha256

    %{
      status: if(passed?, do: "passed", else: "failed"),
      manifest_sha256: preflight.manifest.sha256,
      started_at: DateTime.to_iso8601(started_at),
      duration_us: max(System.monotonic_time(:microsecond) - started_us, 0),
      expected_bytes: expected_bytes,
      bytes_received: state.bytes_received,
      chunks_received: state.chunks_received,
      first_mismatch_offset: state.first_mismatch_offset,
      expected_sha256: expected_sha256,
      actual_sha256: actual_sha256,
      error: if(is_nil(reason), do: nil, else: inspect(reason))
    }
  end

  defp failure_report(preflight, reason) do
    %{
      status: "failed",
      manifest_sha256: preflight.manifest.sha256,
      expected_bytes: preflight.safety.planned_source_bytes,
      bytes_received: 0,
      chunks_received: 0,
      first_mismatch_offset: nil,
      error: inspect(reason)
    }
  end

  defp finalize_hash(context) do
    context
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
