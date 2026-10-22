defmodule CadenceWeb.Release do
  @moduledoc "Database preparation for the Cadence web release, before starting replicas."

  def migrate do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Cadence.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
      end)
  end
end
