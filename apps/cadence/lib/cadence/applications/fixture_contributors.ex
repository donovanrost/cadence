defmodule Cadence.Applications.FixtureContributors do
  @moduledoc """
  Test-only application contributors, appended by each application registry.

  The registries (`Registry`, `CatalogRegistry`, `ReleaseRegistry`, `ActionProviderRegistry`,
  `HostQueryRegistry` and `Cadence.Reads.ApplicationSurfaces.ProviderRegistry`) are fixed module
  lists. The console federation smoke needs an application that product deletions can't remove
  (the `surface_fixture` fixture), so this one extension point lets the test environment add
  contributor modules:

      config :cadence, :fixture_application_contributors, [Cadence.TestSupport.SurfaceFixtureApplication]

  It is read with `Application.compile_env/3`, like the lists themselves: empty unless the config
  for the compiling environment sets it, and only `config/test.exs` does (a guard test reads the
  dev and prod configs). A runtime config can't add one: a value that differs from the compiled
  one makes the application refuse to boot.

  Even in the test environment the fixtures are OFF until a test turns them on
  (`enable/0` … `disable/0`, from a synchronous test), so the product registries every other
  test asserts on stay exactly the product's.
  """

  @contributors Application.compile_env(:cadence, :fixture_application_contributors, [])
  @enabled_key :fixture_applications_enabled

  @doc "The compiled fixture contributors (empty outside the test environment), enabled or not."
  @spec configured() :: [module()]
  def configured, do: @contributors

  @doc "The fixture contributors the registries see now: none unless a test enabled them."
  @spec all() :: [module()]
  def all, do: if(enabled?(), do: @contributors, else: [])

  @doc "The enabled fixture contributors that implement `function/arity` (a registry's callback)."
  @spec exporting(atom(), non_neg_integer()) :: [module()]
  def exporting(function, arity) when is_atom(function) and is_integer(arity) do
    Enum.filter(all(), fn contributor ->
      Code.ensure_loaded?(contributor) and function_exported?(contributor, function, arity)
    end)
  end

  @doc "Turns the compiled fixtures on (a no-op where none are compiled, i.e. dev and prod)."
  @spec enable() :: :ok
  def enable, do: Application.put_env(:cadence, @enabled_key, true)

  @doc "Turns them off again."
  @spec disable() :: :ok
  def disable, do: Application.delete_env(:cadence, @enabled_key)

  defp enabled?, do: @contributors != [] and Application.get_env(:cadence, @enabled_key, false)
end
