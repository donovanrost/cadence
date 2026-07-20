defmodule Cadence.Catalog.Importer do
  @moduledoc """
  Behavior for persistence-independent catalog importers.
  """

  alias Cadence.Catalog.{ImporterDescriptor, ImportResult, Source}

  @callback descriptor() :: ImporterDescriptor.t()
  @callback validate(Source.t()) :: :ok | {:error, term()}
  @callback import(Source.t(), map()) :: {:ok, ImportResult.t()} | {:error, term()}

  @optional_callbacks validate: 1
end
