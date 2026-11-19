defmodule CadenceWeb.Console.DataSourceRunError do
  @moduledoc """
  A data-source run's error as the console reads it (L11 runs[].error, qa (C)): `{code, message}`
  with a known code and a sentence, never an inspected term. The stored failure reason is a
  JSON-encoded term (`%{"tuple" => [...]}` for a tuple); its leading word picks the code.
  """

  @messages %{
    "tsdb_executor_not_configured" =>
      "This environment has nothing configured to run backend operations, so the run couldn't start.",
    "credentials_unavailable" => "The source's credentials couldn't be resolved for this run.",
    "worker_failed" => "The run stopped unexpectedly before it finished.",
    "requeued" => "The run was put back in the queue.",
    "outcome_unknown" =>
      "Outcome unknown: this job ran before a fix, and Cadence can't tell whether it succeeded.",
    "run_failed" => "The run failed."
  }

  @reasons %{
    "tsdb_backend_lifecycle_executor_not_configured" => "tsdb_executor_not_configured",
    "managed_questdb_provisioning_executor_not_configured" => "tsdb_executor_not_configured",
    "credential_reference_not_found" => "credentials_unavailable",
    "credential_disabled" => "credentials_unavailable",
    "credential_scope_mismatch" => "credentials_unavailable",
    "credential_material_resolver_not_configured" => "credentials_unavailable",
    "credential_material_resolution_failed" => "credentials_unavailable",
    "credential_material_authorization_denied" => "credentials_unavailable",
    "worker_exited" => "worker_failed",
    "worker_start_failed" => "worker_failed",
    "exception" => "worker_failed",
    "job_not_running" => "worker_failed",
    "requeued_after_restart" => "requeued",
    "requeued_by_operator" => "requeued",
    "tsdb_backend_lifecycle_requeued" => "requeued",
    "outcome_unknown" => "outcome_unknown"
  }

  @doc "The codes a run error can carry."
  @spec codes() :: [binary()]
  def codes, do: Map.keys(@messages)

  @spec view(term()) :: %{code: binary(), message: binary()} | nil
  def view(nil), do: nil

  def view(failure_reason) do
    code = failure_reason |> leading_word() |> then(&Map.get(@reasons, &1, "run_failed"))
    %{code: code, message: Map.fetch!(@messages, code)}
  end

  defp leading_word(%{"value" => value}), do: leading_word(value)
  defp leading_word(%{"tuple" => [first | _rest]}), do: leading_word(first)
  defp leading_word(%{"reason" => reason}), do: leading_word(reason)
  defp leading_word(%{"code" => code}), do: leading_word(code)
  defp leading_word({first, _detail}), do: leading_word(first)
  defp leading_word(word) when is_atom(word) and not is_nil(word), do: Atom.to_string(word)
  defp leading_word(word) when is_binary(word), do: word
  defp leading_word(_other), do: nil
end
