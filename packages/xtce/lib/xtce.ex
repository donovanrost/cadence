defmodule XTCE do
  @moduledoc """
  Parse and validate XML Telemetric and Command Exchange (XTCE) documents.

  The library currently supports the OMG XTCE 1.3 namespace. Parsing is
  bounded and rejects document type and entity declarations before invoking
  the XML parser. Optional schema validation uses a pinned, offline copy of the
  normative XTCE schema and never follows document-supplied schema locations.

  Schema validation requires the `xmllint` executable. Structural parsing and
  document-tree queries do not.
  """

  alias XTCE.{Document, Element, Parser, SchemaValidator}

  @version "1.3"
  @namespace "http://www.omg.org/spec/XTCE/20250214"

  @doc "Returns the supported XTCE specification version."
  @spec version() :: binary()
  def version, do: @version

  @doc "Returns the supported XTCE XML namespace."
  @spec namespace() :: binary()
  def namespace, do: @namespace

  @doc "Returns the SHA-256 identity of the pinned normative schema."
  @spec schema_sha256() :: binary()
  defdelegate schema_sha256, to: SchemaValidator

  @doc """
  Parses an XTCE XML binary into an `XTCE.Document`.

  The parser accepts `:max_bytes`, `:max_depth`, and `:max_nodes` limits. Set
  `:validate_schema` to `true` to validate against the pinned normative schema
  before returning the document.
  """
  @spec parse(binary(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def parse(xml, opts \\ []) when is_binary(xml) and is_list(opts) do
    with {:ok, root} <- Parser.parse(xml, opts),
         {:ok, document} <- document(root),
         :ok <- maybe_validate_schema(xml, opts) do
      {:ok, document}
    end
  end

  @doc "Parses an XTCE document from a filesystem path."
  @spec parse_file(Path.t(), keyword()) :: {:ok, Document.t()} | {:error, term()}
  def parse_file(path, opts \\ []) when is_binary(path) and is_list(opts) do
    case File.read(path) do
      {:ok, xml} -> parse(xml, opts)
      {:error, reason} -> {:error, {:xtce_file_read_failed, reason}}
    end
  end

  @doc """
  Structurally parses and schema-validates an XTCE XML binary.

  Returns `:xtce_schema_validator_unavailable` when `xmllint` is unavailable.
  """
  @spec validate(binary(), keyword()) :: :ok | {:error, term()}
  def validate(xml, opts \\ []) when is_binary(xml) and is_list(opts) do
    case parse(xml, Keyword.put(opts, :validate_schema, true)) do
      {:ok, %Document{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Structurally parses and schema-validates an XTCE document at a path."
  @spec validate_file(Path.t(), keyword()) :: :ok | {:error, term()}
  def validate_file(path, opts \\ []) when is_binary(path) and is_list(opts) do
    case parse_file(path, Keyword.put(opts, :validate_schema, true)) do
      {:ok, %Document{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp document(%Element{name: "SpaceSystem", namespace: @namespace} = root),
    do: {:ok, Document.new(@version, @namespace, root)}

  defp document(%Element{name: "SpaceSystem", namespace: namespace}),
    do: {:error, {:unsupported_xtce_namespace, namespace}}

  defp document(%Element{}), do: {:error, :xtce_space_system_root_required}

  defp maybe_validate_schema(xml, opts) do
    if Keyword.get(opts, :validate_schema, false) do
      SchemaValidator.validate(xml)
    else
      :ok
    end
  end
end
