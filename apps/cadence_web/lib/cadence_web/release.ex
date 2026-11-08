defmodule CadenceWeb.Release do
  @moduledoc "Database preparation and graceful draining for the Cadence web release."

  alias Cadence.Platform.Drain

  def migrate do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Cadence.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
      end)
  end

  @doc "Drains a running release via RPC; usable by any process supervisor."
  def drain do
    case Drain.run(settle_ms: 10_000, timeout_ms: 65_000) do
      {:ok, summary} -> IO.puts("CADENCE_DRAIN=" <> Jason.encode!(summary))
      {:error, reason} -> raise "Cadence drain failed: #{inspect(reason)}"
    end
  end
end
