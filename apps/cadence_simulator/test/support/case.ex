defmodule CadenceSimulator.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use ExUnit.Case, unquote(opts)
    end
  end
end
