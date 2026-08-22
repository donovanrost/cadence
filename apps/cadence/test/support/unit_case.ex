defmodule Cadence.UnitCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :unit
    end
  end
end
