defmodule Cadence.Catalog.Importers.Xtce13.SchemaValidator do
  @moduledoc """
  Offline validation against the pinned normative XTCE 1.3 schema.

  The schema and its XML namespace import are vendored as compressed assets.
  Validation uses `xmllint --nonet`; no source-controlled or source-supplied
  schema location is followed and validation never performs network access.
  """

  @schema_sha256 "a243cf7ac7d51fae15f985193503326b86602322b13c0e40cc44706ed99921d2"
  @xml_schema_sha256 "a539aa2fb154fa50e0f5cc97e6ad7cbc66f8ec3e3746f61ec6a8b0d5d15ecdf2"
  @xml_schema_url "http://www.w3.org/2001/03/xml.xsd"

  @spec validate(binary()) :: :ok | {:error, term()}
  def validate(xml) when is_binary(xml) do
    with {:ok, executable} <- validator_executable(),
         {:ok, schema_path} <- materialize_schema(),
         {:ok, input_path} <- write_input(xml) do
      try do
        case System.cmd(
               executable,
               ["--noout", "--nonet", "--schema", schema_path, input_path],
               stderr_to_stdout: true
             ) do
          {_output, 0} -> :ok
          {output, _status} -> {:error, {:invalid_xtce_schema, diagnostic(output)}}
        end
      after
        File.rm(input_path)
      end
    end
  end

  @spec schema_sha256() :: binary()
  def schema_sha256, do: @schema_sha256

  defp validator_executable do
    configured =
      Application.get_env(:cadence_catalog, :xtce_schema_validator_executable)

    case configured || System.find_executable("xmllint") do
      executable when is_binary(executable) and executable != "" -> {:ok, executable}
      _other -> {:error, :xtce_schema_validator_unavailable}
    end
  end

  defp materialize_schema do
    directory = Path.join(System.tmp_dir!(), "cadence_xtce_13_" <> @schema_sha256)
    schema_path = Path.join(directory, "SpaceSystem.xsd")
    xml_schema_path = Path.join(directory, "xml.xsd")

    with :ok <- File.mkdir_p(directory),
         {:ok, schema} <- read_asset("SpaceSystem.xsd.gz.b64", @schema_sha256),
         {:ok, xml_schema} <- read_asset("xml.xsd.gz.b64", @xml_schema_sha256),
         schema <- String.replace(schema, @xml_schema_url, xml_schema_path),
         :ok <- write_exact(xml_schema_path, xml_schema),
         :ok <- write_exact(schema_path, schema) do
      {:ok, schema_path}
    end
  end

  defp read_asset(name, expected_sha256) do
    path = Path.join([priv_dir(), "xtce_13", name])

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

  defp write_exact(path, contents) do
    case File.read(path) do
      {:ok, ^contents} -> :ok
      _other -> File.write(path, contents, [:binary])
    end
  end

  defp write_input(xml) do
    name = "input_#{System.unique_integer([:positive, :monotonic])}.xml"
    path = Path.join(System.tmp_dir!(), name)

    case File.write(path, xml, [:binary, :exclusive]) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:xtce_schema_input_write_failed, reason}}
    end
  end

  defp diagnostic(output) do
    output
    |> String.replace(~r{/[^\s:]+/input_\d+\.xml}, "XTCE source")
    |> String.trim()
    |> String.slice(0, 4_000)
  end

  defp priv_dir do
    :cadence_catalog
    |> :code.priv_dir()
    |> List.to_string()
  end
end
