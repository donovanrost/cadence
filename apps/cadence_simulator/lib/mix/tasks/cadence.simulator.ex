defmodule Mix.Tasks.Cadence.Simulator do
  @moduledoc """
  Starts the simulator from a named dev profile.

  This task runs as its own local BEAM process, ensures the profile's dev
  contact/runtime exists, and then starts the simulator without requiring
  `mix escript.build`.
  """

  use Mix.Task

  alias CadenceSimulator.DevTools

  @shortdoc "Start the simulator from a named dev profile"

  @impl true
  def run(["--help"]), do: print_help()
  def run(["-h"]), do: print_help()

  def run([profile_identifier | simulator_args]) do
    {:ok, _started} = Application.ensure_all_started(:cadence_simulator)

    %{profile: profile, bootstrap_summary: bootstrap_summary, runtime_opts: runtime_opts} =
      case DevTools.resolve_profile_runtime(profile_identifier, simulator_args) do
        {:ok, runtime} ->
          runtime

        {:help, usage} ->
          Mix.shell().info(usage)
          System.halt(0)

        {:error, reason} when is_binary(reason) ->
          Mix.raise(reason)

        {:error, reason} ->
          Mix.raise("failed to resolve simulator runtime: #{inspect(reason)}")
      end

    Mix.shell().info("""
    Starting simulator profile #{profile.name}
      mission_id: #{bootstrap_summary.mission_id}
      realized_contact_id: #{get_in(bootstrap_summary, [:realized_contact, "realized_contact_id"]) || "(none)"}
      config: #{profile.path}
    """)

    start_runtime!(runtime_opts)
  end

  def run(_args) do
    print_help()
    Mix.raise("missing required PROFILE argument")
  end

  defp start_runtime!(runtime_opts) do
    result =
      case Keyword.fetch!(runtime_opts, :runtime_mode) do
        :telemetry ->
          CadenceSimulator.start_simulator(Keyword.delete(runtime_opts, :runtime_mode))

        :cop1_loopback ->
          CadenceSimulator.start_cop1_loopback_peer(Keyword.delete(runtime_opts, :runtime_mode))
      end

    case result do
      {:ok, pid} ->
        {:ok, _reason} = CadenceSimulator.await_simulator(pid)

      {:error, reason} ->
        Mix.raise("failed to start simulator: #{inspect(reason)}")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.simulator - Start the simulator from a named dev profile

    Usage:
      mix cadence.simulator PROFILE [simulator overrides...]

    Examples:
      mix cadence.simulator demo_spacecraft
      mix cadence.simulator demo_spacecraft --rate 25.0

    Notes:
      PROFILE resolves to dev/profiles/PROFILE.yaml by default.
      The task runs in its own local Mix/BEAM process; it does not run inside the Cadence server.
      Simulator overrides use the same flags as `cadence_simulator telemetry` or
      `cadence_simulator cop1_loopback`, depending on the profile's runtime mode.
    """)
  end
end
