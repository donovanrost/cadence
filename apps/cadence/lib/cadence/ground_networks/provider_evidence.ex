defmodule Cadence.GroundNetworks.ProviderEvidence do
  @moduledoc "Sanitized, content-addressed evidence captured from a provider boundary."

  @type storage_kind :: :inline | :external

  @type t :: %__MODULE__{
          provider_evidence_id: binary(),
          organization_id: binary(),
          provider_account_id: binary(),
          storage_kind: storage_kind(),
          schema_type: binary(),
          media_type: binary(),
          captured_at: DateTime.t(),
          byte_count: non_neg_integer(),
          content_sha256: binary(),
          document: map() | nil,
          external_object_ref: binary() | nil,
          metadata: map()
        }

  defstruct [
    :provider_evidence_id,
    :organization_id,
    :provider_account_id,
    :storage_kind,
    :schema_type,
    :media_type,
    :captured_at,
    :byte_count,
    :content_sha256,
    :document,
    :external_object_ref,
    metadata: %{}
  ]
end
