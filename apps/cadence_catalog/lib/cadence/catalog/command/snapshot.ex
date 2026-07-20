defmodule Cadence.Catalog.Command.Snapshot do
  @moduledoc """
  Immutable canonical command catalog snapshot derived from one import run.
  """

  alias Cadence.Catalog.Command.{
    Argument,
    ArgumentType,
    Definition,
    EncodingLayout,
    Normalize,
    Provenance
  }

  alias Cadence.Catalog.Ids

  @type t :: %__MODULE__{
          snapshot_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          artifact_id: binary(),
          import_run_id: binary(),
          importer_key: binary(),
          snapshot_name: binary(),
          snapshot_version: binary() | nil,
          description: binary() | nil,
          published_at: DateTime.t() | nil,
          superseded_at: DateTime.t() | nil,
          argument_types: [ArgumentType.t()],
          arguments: [Argument.t()],
          encoding_layouts: [EncodingLayout.t()],
          command_definitions: [Definition.t()],
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :snapshot_id,
    :organization_id,
    :mission_id,
    :artifact_id,
    :import_run_id,
    :importer_key,
    :snapshot_name,
    :snapshot_version,
    :description,
    :published_at,
    :superseded_at,
    :provenance,
    argument_types: [],
    arguments: [],
    encoding_layouts: [],
    command_definitions: [],
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      snapshot_id: Normalize.get(attrs, :snapshot_id, Ids.new("command_snapshot")),
      organization_id: Normalize.get(attrs, :organization_id),
      mission_id: Normalize.fetch!(attrs, :mission_id),
      artifact_id: Normalize.fetch!(attrs, :artifact_id),
      import_run_id: Normalize.fetch!(attrs, :import_run_id),
      importer_key: Normalize.fetch!(attrs, :importer_key),
      snapshot_name: Normalize.fetch!(attrs, :snapshot_name),
      snapshot_version: Normalize.get(attrs, :snapshot_version),
      description: Normalize.get(attrs, :description),
      published_at: Normalize.get(attrs, :published_at),
      superseded_at: Normalize.get(attrs, :superseded_at),
      argument_types: Normalize.nested_list(attrs, :argument_types, ArgumentType),
      arguments: Normalize.nested_list(attrs, :arguments, Argument),
      encoding_layouts: Normalize.nested_list(attrs, :encoding_layouts, EncodingLayout),
      command_definitions: Normalize.nested_list(attrs, :command_definitions, Definition),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end
end
