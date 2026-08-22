defmodule Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider do
  @moduledoc "Read-side provider contract behind host-owned surface query dispatch."

  alias Cadence.Applications.{HostContext, SurfaceDocument, SurfaceQueryRequest}
  alias Cadence.Auth.Scope

  @callback load(Scope.t(), HostContext.t(), SurfaceQueryRequest.t()) ::
              {:ok, SurfaceDocument.t()} | {:error, term()}
end
