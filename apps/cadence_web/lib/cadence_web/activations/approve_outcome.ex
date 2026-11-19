defmodule CadenceWeb.Activations.ApproveOutcome do
  @moduledoc """
  REST activation approve, once the approval is recorded (#263): runs the apply and says how it
  went, never as a refusal. The approval stands whatever the apply does, so an apply that fails,
  doesn't finish or raises is `needs_review` (the console's L10 words), and the cause is logged
  server-side (its first line only, as #262), never sent.
  """

  require Logger

  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Platform.ExitShape

  @typedoc "The closed set the answer's `outcome` takes."
  @type outcome :: binary()

  @spec after_approval(term(), binary(), (term() ->
                                            {:ok, ActivationExecution.t()} | {:error, term()})) ::
          {ActivationExecution.t() | nil, outcome()}
  def after_approval(approved, request_id, execute \\ &ControlActivations.execute/1) do
    case run(execute, approved) do
      {:ok, %ActivationExecution{status: :succeeded} = execution} ->
        {execution, "applied"}

      {:ok, %ActivationExecution{} = execution} ->
        {execution, "needs_review"}

      {:error, reason} ->
        Logger.error(
          "activation request #{request_id}: approved, but its apply didn't run: #{cause(reason)}"
        )

        {nil, "needs_review"}
    end
  end

  # An exit (a pool or GenServer timeout, noproc, a linked exit) or a throw is caught too: the
  # approval is committed, so nothing after it may fail the answer (ca-security, api-ops).
  defp run(execute, approved) do
    execute.(approved)
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    :exit, reason -> {:error, "exit: " <> ExitShape.describe(reason)}
    :throw, value -> {:error, "throw: " <> ExitShape.describe(value)}
  end

  # The cause's first line only: a database error's later lines can carry row values.
  defp cause(reason) when is_binary(reason), do: reason |> String.split("\n", parts: 2) |> hd()
  defp cause(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp cause(reason) when is_tuple(reason), do: reason |> elem(0) |> cause()
  defp cause(_reason), do: "an unexpected result"
end
