defmodule Cadence.SemanticRuntime.Terms do
  @moduledoc """
  Safe decoding of persisted semantic runtime terms (commits and checkpoints).

  `binary_to_term(..., [:safe])` refuses atoms the VM hasn't created yet. Persisted terms carry
  the semantic runtime's struct fields and states (e.g. `MonitoringResult`'s `:candidate_state`),
  which exist only once their modules are loaded. In an interactively loaded VM (dev, tests)
  partition recovery can run before those modules load, and the decode would fail forever,
  because the code that loads them never runs while the partition can't start. So on failure
  this loads every `Cadence.SemanticRuntime` module and decodes once more, still `:safe`.
  Releases preload all modules, where the retry never triggers.
  """

  @spec decode(binary()) :: {:ok, term()} | {:error, :semantic_runtime_commit_decode_failed}
  def decode(binary) when is_binary(binary) do
    {:ok, safe_decode(binary)}
  rescue
    ArgumentError ->
      load_semantic_modules()

      try do
        {:ok, safe_decode(binary)}
      rescue
        ArgumentError -> {:error, :semantic_runtime_commit_decode_failed}
      end
  end

  @spec encode(term()) :: binary()
  def encode(term), do: :erlang.term_to_binary(term, compressed: 6)

  @doc false
  @spec load_semantic_modules() :: :ok
  def load_semantic_modules do
    {:ok, modules} = :application.get_key(:cadence, :modules)

    modules
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.Cadence.SemanticRuntime."))
    |> Enum.each(&Code.ensure_loaded/1)
  end

  defp safe_decode(binary), do: :erlang.binary_to_term(binary, [:safe])
end
