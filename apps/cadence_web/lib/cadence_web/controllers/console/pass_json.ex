defmodule CadenceWeb.Console.PassJSON do
  @moduledoc "Wire shape of the console passes read. Contract: docs/apogee/api/contacts.md."

  @spec passes(map()) :: map()
  def passes(result) do
    Map.take(result, [:from, :to, :truncated, :passes, :counts])
  end
end
