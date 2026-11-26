defmodule Cadence.TestSupport.RetentionLock do
  @moduledoc """
  A retention sweep of a real rule in a test takes an advisory lock shared with every other
  session on the database. A holder outside the test (another run on the same test database, a
  connection not yet returned) would make the sweep report `:locked` and the test fail by chance
  (#939). A test passes `lock_key: RetentionLock.key(rule)` to `Sweeper.sweep/3`: a key of its own.
  """

  @spec key(module()) :: String.t()
  def key(rule), do: "retention:#{rule.name()}:test:#{System.unique_integer([:positive])}"
end
