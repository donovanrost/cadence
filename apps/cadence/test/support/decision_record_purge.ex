defmodule Cadence.TestSupport.DecisionRecordPurge do
  @moduledoc """
  For tests that clean up decision rows outside the SQL sandbox: runs `fun` in a transaction with
  the transaction-local purge setting on, which the append-only triggers honour only in a test
  database (DECISIONS #107, P3 step 1). Never used under lib/ or priv/ (the guard test checks).
  """

  alias Cadence.Repo

  def run(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL cadence.decision_record_test_purge = 'on'")
      fun.()
    end)
  end
end
