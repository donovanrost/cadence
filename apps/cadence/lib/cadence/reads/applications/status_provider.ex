defmodule Cadence.Reads.Applications.StatusProvider do
  @moduledoc "Read-side contract for a registered application status projection."

  alias Cadence.Applications.{HostContext, Status}
  alias Cadence.Auth.Scope

  @callback load(Scope.t(), HostContext.t()) :: {:ok, Status.t()} | {:error, term()}

  @doc "Invokes an already-admitted provider and contains malformed data or provider failure."
  def invoke(provider, scope, context) do
    case provider.load(scope, context) do
      {:ok, status} ->
        if Status.valid?(status), do: {:ok, status}, else: {:error, :invalid_application_status}

      _ ->
        {:error, :application_status_unavailable}
    end
  rescue
    _ -> {:error, :application_status_unavailable}
  catch
    _, _ -> {:error, :application_status_unavailable}
  end
end
