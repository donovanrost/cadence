defmodule CadenceWeb.ApplicationActionInput do
  @moduledoc "Host JSON admission within the shared JSON bounds."
  alias Cadence.Applications.JSONBoundary

  @spec safe(term()) :: {:ok, term()} | {:error, term()}
  def safe(params) do
    case JSONBoundary.safe(params) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :application_surface_bounds_exceeded}
    end
  end
end
