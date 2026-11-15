defmodule Cadence.Applications.FixtureContributors do
  @moduledoc """
  Test-only application contributors, appended by each application registry.

  The registries (`Registry`, `CatalogRegistry`, `ReleaseRegistry`, `ActionProviderRegistry`,
  `HostQueryRegistry`) are fixed module lists. The console federation smoke needs an application
  that product deletions can't remove (the `contract_probe` fixture), so this one extension point
  lets the test environment add contributor modules:

      config :cadence, :fixture_application_contributors, [Cadence.TestSupport.ContractProbeApplication]

  It is read with `Application.compile_env/3`, like the lists themselves: empty unless the config
  for the compiling environment sets it, and only `config/test.exs` does (a guard test reads the
  dev and prod configs). A runtime config can't add one: a value that differs from the compiled
  one makes the application refuse to boot.
  """

  @contributors Application.compile_env(:cadence, :fixture_application_contributors, [])

  @doc "Every fixture contributor (empty outside the test environment)."
  @spec all() :: [module()]
  def all, do: @contributors

  @doc "The fixture contributors that implement `function/arity` (a registry's callback)."
  @spec exporting(atom(), non_neg_integer()) :: [module()]
  def exporting(function, arity) when is_atom(function) and is_integer(arity) do
    Enum.filter(@contributors, fn contributor ->
      Code.ensure_loaded?(contributor) and function_exported?(contributor, function, arity)
    end)
  end
end
