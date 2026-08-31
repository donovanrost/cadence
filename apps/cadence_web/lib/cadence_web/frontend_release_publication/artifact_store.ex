defmodule CadenceWeb.FrontendReleasePublication.ArtifactStore do
  @moduledoc """
  Offline content-addressed storage boundary for admitted frontend artifacts.

  The digest is the complete `sha256:<64 lowercase hex>` object identity. An
  implementation must never replace an existing object with different bytes.
  """

  @type digest :: binary()
  @type stored_object :: %{
          required(:digest) => digest(),
          required(:object_key) => binary(),
          required(:size) => non_neg_integer(),
          required(:status) => :stored | :existing
        }

  @callback put(digest(), binary()) :: {:ok, stored_object()} | {:error, term()}
  @callback readback(digest()) :: {:ok, binary()} | {:error, term()}
end
