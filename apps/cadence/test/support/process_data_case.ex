defmodule Cadence.ProcessDataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using opts do
    if Keyword.get(opts, :async, false) do
      raise ArgumentError, "Cadence.ProcessDataCase does not support async tests"
    end

    quote do
      @moduletag :data
      @moduletag :process_data

      alias Cadence.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Cadence.DataCase
    end
  end

  setup tags do
    if tags[:async] do
      raise ArgumentError, "Cadence.ProcessDataCase does not support async tests"
    end

    owner = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)

    on_exit(fn ->
      Cadence.DataCase.stop_sandbox_owner(owner)
    end)

    :ok
  end
end
