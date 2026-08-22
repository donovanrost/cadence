defmodule Cadence.Dashboards.Version do
  @moduledoc """
  Immutable dashboard document snapshot.

  Version rows are the durable history for a mission-shared dashboard. The
  current dashboard row remains the fast pointer to the latest document; this
  struct carries the saved document content for audit and future rollback.
  """

  alias Cadence.Dashboards.Document

  @type snapshot_kind :: :draft_save | :publish | :revert | :migration

  @type t :: %__MODULE__{
          dashboard_version_id: binary() | nil,
          organization_id: binary(),
          mission_id: binary(),
          dashboard_id: binary(),
          version: pos_integer(),
          document: Document.t(),
          snapshot_kind: snapshot_kind(),
          parent_version: pos_integer() | nil,
          based_on_version: pos_integer() | nil,
          schema_version: pos_integer(),
          change_summary: binary() | nil,
          created_by: binary() | nil,
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :dashboard_version_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :version,
    :document,
    :parent_version,
    :based_on_version,
    :change_summary,
    :created_by,
    :inserted_at,
    snapshot_kind: :draft_save,
    schema_version: 1
  ]
end
