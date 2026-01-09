defmodule Cadence.UseCaseCase do
  @moduledoc """
  Test case for application-layer use cases with in-memory adapters.

  Use this for unit-style tests that exercise application services while
  avoiding the database.
  """

  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset

  using do
    quote do
      use Cadence.PureCase, async: false
      import Cadence.UseCaseCase

      @moduletag :use_case
    end
  end

  setup do
    # Some use cases emit Outbox events, which write to the database even when
    # domain repositories are swapped to in-memory adapters.
    owner = Sandbox.start_owner!(Cadence.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    cleanup = Cadence.TestSupport.enable_in_memory_adapters()
    on_exit(cleanup)
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.
  """
  def errors_on(changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
