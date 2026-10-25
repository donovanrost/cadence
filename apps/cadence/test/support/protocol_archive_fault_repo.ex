defmodule Cadence.ProtocolArchiveFaultRepo do
  @moduledoc false
  use Agent

  def start_link(opts) do
    Agent.start_link(fn -> %{owner: Keyword.fetch!(opts, :owner), failure: nil} end,
      name: __MODULE__
    )
  end

  def fail_with(exception), do: Agent.update(__MODULE__, &%{&1 | failure: exception})
  def recover, do: Agent.update(__MODULE__, &%{&1 | failure: nil})

  def transaction(fun) do
    %{owner: owner, failure: failure} = Agent.get(__MODULE__, & &1)

    if failure do
      send(owner, :archive_write_failed)
      raise failure
    else
      result = Cadence.Repo.transaction(fun)
      send(owner, {:archive_write_completed, result})
      result
    end
  end

  defdelegate insert_all(schema, rows, opts), to: Cadence.Repo
  defdelegate all(query), to: Cadence.Repo
  defdelegate rollback(reason), to: Cadence.Repo
end
