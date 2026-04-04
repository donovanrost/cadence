defmodule Cadence.Catalog.Importer do
  @moduledoc """
  Behavior for first-party catalog importers.
  """

  alias Cadence.Catalog.{Artifact, ImporterDescriptor, ImportResult}

  @callback descriptor() :: ImporterDescriptor.t()
  @callback validate_artifact(Artifact.t()) :: :ok | {:error, term()}
  @callback import(Artifact.t(), map()) :: {:ok, ImportResult.t()} | {:error, term()}

  @optional_callbacks validate_artifact: 1
end
