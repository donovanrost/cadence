defmodule Cadence.Configuration.Kinds do
  @moduledoc """
  Registry of `Cadence.Platform.ConfigKind` implementations, configured with
  `config :cadence, :configuration_kinds, [Module, ...]`.

  Kinds live in the context that owns the entity. The change-set core reaches them only through
  this configured list, so it has no compile-time dependency on those contexts.
  """

  # Optional callbacks are probed with `function_exported?/3`, which is false for a module that
  # isn't loaded yet, so every kind is loaded here.
  @spec all() :: [module()]
  def all do
    kinds = Application.get_env(:cadence, :configuration_kinds, [])
    Enum.each(kinds, &Code.ensure_loaded!/1)
    kinds
  end

  @spec fetch(String.t()) :: {:ok, module()} | {:error, :unknown_kind}
  def fetch(kind) when is_binary(kind) do
    case Enum.find(all(), &(&1.kind() == kind)) do
      nil -> {:error, :unknown_kind}
      module -> {:ok, module}
    end
  end

  def fetch(_kind), do: {:error, :unknown_kind}

  @doc "The lane a kind's changes stage in, as stored on a change set: `\"configuration\"` unless the kind says otherwise."
  @spec lane(module()) :: String.t()
  def lane(kind) when is_atom(kind) do
    if function_exported?(kind, :lane, 0), do: Atom.to_string(kind.lane()), else: "configuration"
  end

  @spec fetch!(String.t()) :: module()
  def fetch!(kind) do
    {:ok, module} = fetch(kind)
    module
  end
end
