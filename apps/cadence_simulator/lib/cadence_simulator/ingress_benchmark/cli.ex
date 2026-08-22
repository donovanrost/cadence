defmodule CadenceSimulator.IngressBenchmark.CLI do
  @moduledoc """
  Escript commands for safe local ingress preflight, source, and sink roles.
  """

  alias CadenceSimulator.IngressBenchmark.{Manifest, Preflight, TrafficDriver, ValidatingSink}

  @switches [
    manifest: :string,
    component: :string,
    tcp: :string,
    listen: :string,
    connect_timeout_ms: :integer,
    send_timeout_ms: :integer,
    timeout_ms: :integer,
    pace: :boolean,
    pretty: :boolean,
    help: :boolean
  ]

  @spec main(:preflight | :source | :sink, [binary()]) :: no_return()
  def main(mode, args) do
    case run(mode, args) do
      {:ok, output} ->
        IO.puts(output)
        System.halt(0)

      {:error, output} ->
        IO.puts(:stderr, output)
        System.halt(1)
    end
  end

  @spec run(:preflight | :source | :sink, [binary()], keyword()) ::
          {:ok, binary()} | {:error, binary()}
  def run(mode, args, runtime_opts \\ [])

  def run(mode, args, runtime_opts)
      when mode in [:preflight, :source, :sink] and is_list(args) and is_list(runtime_opts) do
    _ = Application.ensure_all_started(:crypto)

    case parse_args(mode, args) do
      {:ok, opts} -> execute(mode, opts, runtime_opts)
      {:help, usage} -> {:ok, usage}
      {:error, message} -> {:error, encode(%{status: "failed", errors: [message]}, false)}
    end
  end

  @spec parse_args(:preflight | :source | :sink, [binary()]) ::
          {:ok, keyword()} | {:help, binary()} | {:error, binary()}
  def parse_args(mode, args) when mode in [:preflight, :source, :sink] and is_list(args) do
    {parsed, positional, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      parsed[:help] ->
        {:help, usage(mode)}

      invalid != [] ->
        {:error, "invalid options: #{inspect(invalid)}"}

      positional != [] ->
        {:error, "unexpected arguments: #{Enum.join(positional, " ")}"}

      true ->
        validate_options(mode, parsed)
    end
  end

  @spec usage(:preflight | :source | :sink) :: binary()
  def usage(:preflight) do
    """
    Usage:
      cadence_simulator ingress_preflight --manifest PATH [--component NAME] [--pretty]

    Reads the manifest and Linux mount table, emits a JSON safety report, and
    performs no benchmark writes or network traffic.
    """
  end

  def usage(:source) do
    """
    Usage:
      cadence_simulator ingress_source --manifest PATH --tcp HOST:PORT [options]

    Options:
      --component NAME          Manifest container role (default: harness)
      --connect-timeout-ms MS   Bounded TCP connect window (default: 5000)
      --send-timeout-ms MS      Bounded wait for each socket send (default: 1000)
      --no-pace                 Test-only: send without schedule pacing
      --pretty                  Pretty-print the final JSON report
    """
  end

  def usage(:sink) do
    """
    Usage:
      cadence_simulator ingress_sink --manifest PATH --listen HOST:PORT [options]

    Options:
      --component NAME    Manifest container role (default: harness)
      --timeout-ms MS     Accept, receive, and stream-close timeout (default: 10000)
      --pretty            Pretty-print the final JSON report
    """
  end

  defp validate_options(mode, parsed) do
    with {:ok, manifest_path} <- require_string(parsed[:manifest], "--manifest is required"),
         {:ok, endpoint} <- endpoint_options(mode, parsed),
         :ok <- validate_positive_option(parsed[:connect_timeout_ms], "--connect-timeout-ms"),
         :ok <- validate_positive_option(parsed[:send_timeout_ms], "--send-timeout-ms"),
         :ok <- validate_positive_option(parsed[:timeout_ms], "--timeout-ms") do
      {:ok,
       [
         manifest_path: manifest_path,
         component: parsed[:component] || "harness",
         pretty?: parsed[:pretty] || false,
         pace?: parsed[:pace] != false,
         connect_timeout_ms: parsed[:connect_timeout_ms],
         send_timeout_ms: parsed[:send_timeout_ms],
         timeout_ms: parsed[:timeout_ms]
       ] ++ endpoint}
    end
  end

  defp endpoint_options(:preflight, _parsed), do: {:ok, []}
  defp endpoint_options(:source, parsed), do: parse_endpoint(parsed[:tcp], "--tcp")
  defp endpoint_options(:sink, parsed), do: parse_endpoint(parsed[:listen], "--listen")

  defp parse_endpoint(value, option) do
    case require_string(value, "#{option} is required") do
      {:ok, endpoint} ->
        parse_endpoint_value(endpoint, option)

      {:error, message} ->
        {:error, message}
    end
  end

  defp parse_endpoint_value(endpoint, option) do
    with [host, port_text] <- String.split(endpoint, ":", parts: 2),
         {port, ""} when port in 1..65_535 <- Integer.parse(port_text),
         true <- host != "" do
      {:ok, [host: host, port: port]}
    else
      _invalid -> {:error, "#{option} must be HOST:PORT"}
    end
  end

  defp validate_positive_option(nil, _option), do: :ok

  defp validate_positive_option(value, _option) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_option(_value, option), do: {:error, "#{option} must be positive"}

  defp require_string(value, _message) when is_binary(value) and value != "", do: {:ok, value}
  defp require_string(_value, message), do: {:error, message}

  defp execute(mode, opts, runtime_opts) do
    safety_opts =
      runtime_opts
      |> Keyword.take([:mountinfo])
      |> Keyword.put(:component, opts[:component])

    with {:ok, manifest} <- Manifest.load(opts[:manifest_path]),
         {:ok, preflight} <- Preflight.evaluate(manifest, safety_opts) do
      execute_permitted(mode, preflight, opts)
    else
      {:error, errors} when is_list(errors) ->
        {:error, encode(%{status: "failed", stage: "preflight", errors: errors}, opts[:pretty?])}

      {:error, reason} ->
        {:error,
         encode(
           %{status: "failed", stage: "manifest", errors: [to_string(reason)]},
           opts[:pretty?]
         )}
    end
  end

  defp execute_permitted(:preflight, preflight, opts) do
    {:ok, encode(Preflight.result(preflight), opts[:pretty?])}
  end

  defp execute_permitted(:source, preflight, opts) do
    driver_opts =
      [host: opts[:host], port: opts[:port], pace?: opts[:pace?]]
      |> maybe_put(:connect_timeout_ms, opts[:connect_timeout_ms])
      |> maybe_put(:send_timeout_ms, opts[:send_timeout_ms])

    case TrafficDriver.run(preflight, driver_opts) do
      {:ok, report} -> {:ok, encode(report, opts[:pretty?])}
      {:error, _reason, report} -> {:error, encode(report, opts[:pretty?])}
    end
  end

  defp execute_permitted(:sink, preflight, opts) do
    sink_opts =
      [host: opts[:host], port: opts[:port]]
      |> maybe_put(:timeout_ms, opts[:timeout_ms])

    case ValidatingSink.run(preflight, sink_opts) do
      {:ok, report} -> {:ok, encode(report, opts[:pretty?])}
      {:error, _reason, report} -> {:error, encode(report, opts[:pretty?])}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp encode(payload, true), do: Jason.encode!(payload, pretty: true)
  defp encode(payload, false), do: Jason.encode!(payload)
end
