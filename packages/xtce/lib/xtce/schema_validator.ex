defmodule XTCE.SchemaValidator do
  @moduledoc """
  Offline validation against the pinned normative XTCE 1.3 schema.

  The schema and its XML namespace import are vendored as compressed assets.
  Validation uses `xmllint --nonet`; no source-controlled or source-supplied
  schema location is followed and validation never performs network access.
  """

  @schema_sha256 "a243cf7ac7d51fae15f985193503326b86602322b13c0e40cc44706ed99921d2"
  @xml_schema_sha256 "a539aa2fb154fa50e0f5cc97e6ad7cbc66f8ec3e3746f61ec6a8b0d5d15ecdf2"
  @xml_schema_url "http://www.w3.org/2001/03/xml.xsd"

  @doc "Validates an XTCE document against the pinned XTCE 1.3 XML schema."
  @spec validate(binary()) :: :ok | {:error, term()}
  def validate(xml) when is_binary(xml) do
    with {:ok, executable} <- validator_executable(),
         {:ok, directory} <- create_temp_directory() do
      try do
        with {:ok, schema_path} <- materialize_schema(directory),
             {:ok, input_path} <- write_input(directory, xml) do
          case System.cmd(
                 executable,
                 ["--noout", "--nonet", "--schema", schema_path, input_path],
                 stderr_to_stdout: true
               ) do
            {_output, 0} -> :ok
            {output, _status} -> {:error, {:invalid_xtce_schema, diagnostic(output)}}
          end
        end
      after
        cleanup_temp_directory(directory)
      end
    end
  end

  @doc "Returns the SHA-256 identity of the pinned XTCE 1.3 schema."
  @spec schema_sha256() :: binary()
  def schema_sha256, do: @schema_sha256

  defp validator_executable do
    case System.find_executable("xmllint") do
      executable when is_binary(executable) and executable != "" -> {:ok, executable}
      _other -> {:error, :xtce_schema_validator_unavailable}
    end
  end

  defp create_temp_directory do
    suffix = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    directory = Path.join(System.tmp_dir!(), "xtce_1_3_" <> suffix)

    case File.mkdir(directory) do
      :ok -> {:ok, directory}
      {:error, reason} -> {:error, {:xtce_schema_temp_directory_failed, reason}}
    end
  end

  defp materialize_schema(directory) do
    schema_path = Path.join(directory, "SpaceSystem.xsd")
    xml_schema_path = Path.join(directory, "xml.xsd")

    with {:ok, schema} <- read_asset("SpaceSystem.xsd.gz.b64", @schema_sha256),
         {:ok, xml_schema} <- read_asset("xml.xsd.gz.b64", @xml_schema_sha256),
         schema <- String.replace(schema, @xml_schema_url, xml_schema_path),
         :ok <- write_exclusive(xml_schema_path, xml_schema),
         :ok <- write_exclusive(schema_path, schema) do
      {:ok, schema_path}
    end
  end

  defp read_asset(name, expected_sha256) do
    path = Path.join([priv_dir(), "xtce_1_3", name])

    with {:ok, encoded} <- File.read(path),
         {:ok, compressed} <- Base.decode64(String.replace(encoded, ~r/\s+/, "")),
         document <- :zlib.gunzip(compressed),
         :ok <- verify_hash(document, expected_sha256) do
      {:ok, document}
    else
      :error -> {:error, {:xtce_schema_asset_invalid, name}}
      {:error, reason} -> {:error, {:xtce_schema_asset_invalid, name, reason}}
    end
  rescue
    ErlangError -> {:error, {:xtce_schema_asset_invalid, name}}
  end

  defp verify_hash(document, expected) do
    actual = :crypto.hash(:sha256, document) |> Base.encode16(case: :lower)
    if actual == expected, do: :ok, else: {:error, :checksum_mismatch}
  end

  defp write_exclusive(path, contents) do
    case File.write(path, contents, [:binary, :exclusive]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:xtce_schema_temp_write_failed, reason}}
    end
  end

  defp write_input(directory, xml) do
    path = Path.join(directory, "input.xml")

    case File.write(path, xml, [:binary, :exclusive]) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:xtce_schema_input_write_failed, reason}}
    end
  end

  defp diagnostic(output) do
    output
    |> String.replace(~r{/[^\s:]+/input\.xml}, "XTCE source")
    |> String.trim()
    |> String.slice(0, 4_000)
  end

  defp cleanup_temp_directory(directory) do
    Enum.each(["input.xml", "SpaceSystem.xsd", "xml.xsd"], fn name ->
      File.rm(Path.join(directory, name))
    end)

    File.rmdir(directory)
  end

  defp priv_dir do
    :xtce
    |> :code.priv_dir()
    |> List.to_string()
  end
end
