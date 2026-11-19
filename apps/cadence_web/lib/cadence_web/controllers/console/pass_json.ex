defmodule CadenceWeb.Console.PassJSON do
  @moduledoc "Wire shape of the console passes read. Contract: docs/apogee/api/contacts.md."

  @spec passes(map()) :: map()
  def passes(result) do
    %{from: result.from, to: result.to, truncated: result.truncated, passes: result.passes}
  end
end
