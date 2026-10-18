defmodule CadenceWeb.FrontendReleasePublication.ArtifactStore do
  @moduledoc """
  Content-addressed storage boundary for admitted frontend artifacts.

  The digest is the complete `sha256:<64 lowercase hex>` logical object identity.
  An implementation must never replace an existing object with different bytes,
  and `object_key` is never a filesystem path.
  """

  @type digest :: binary()
  @type stored_object :: %{
          required(:digest) => digest(),
          required(:object_key) => binary(),
          required(:size) => non_neg_integer(),
          required(:status) => :stored | :existing
        }

  @callback put(digest(), binary()) :: {:ok, stored_object()} | {:error, term()}
  @callback verify(digest(), binary() | non_neg_integer()) :: :ok | {:error, term()}

  @callback read_chunk(digest(), non_neg_integer(), pos_integer()) ::
              {:ok, binary()} | {:error, term()}
end
