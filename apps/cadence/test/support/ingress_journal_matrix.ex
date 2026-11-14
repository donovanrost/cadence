defmodule Cadence.TestSupport.IngressJournalMatrix do
  @moduledoc """
  The ingress journal matrix (director 11-14). Production's default is the journal OFF
  (config/config.exs); tests run with it on unless `CADENCE_TEST_INGRESS_JOURNAL=off`. CI reruns
  the `@moduletag :ingest_journal_matrix` modules with it off:

      CADENCE_TEST_INGRESS_JOURNAL=off mix test --only ingest_journal_matrix

  A journal-only test inside a matrix module calls `requires_ingress_journal()` just before it:
  with the journal off it is skipped, visibly ("needs the ingress journal"). Tagging and then
  excluding wouldn't work, because `--only` includes the module's tag and include beats exclude.
  Whole journal-only modules simply stay out of the matrix.
  """

  @doc "Whether this test run has the ingress journal on."
  @spec journal_on?() :: boolean()
  def journal_on?, do: System.get_env("CADENCE_TEST_INGRESS_JOURNAL", "on") != "off"

  @doc "Skips the next test when the journal is off (call it in the module body, before `test`)."
  defmacro requires_ingress_journal do
    quote do
      unless unquote(__MODULE__).journal_on?() do
        @tag skip: "needs the ingress journal (CADENCE_TEST_INGRESS_JOURNAL=off)"
      end
    end
  end
end
