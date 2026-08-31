defmodule CadenceWeb.FrontendReleasePublisherController do
  @moduledoc false

  use CadenceWeb, :controller

  alias CadenceWeb.FrontendReleasePublication
  alias CadenceWeb.Plugs.FrontendReleaseRequestBody
  alias Plug.Conn.Utils

  @publisher_identity_header "x-cadence-publisher-identity"
  @max_publisher_identity_bytes 128

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    with :ok <- application_json?(conn),
         {:ok, body} <- FrontendReleaseRequestBody.raw_body(conn),
         {:ok, request} <- decode_request(body),
         {:ok, publisher_identity} <- publisher_identity(conn),
         {:ok, outcome, publication} <-
           publish(request, publisher_identity) do
      response(conn, outcome, publication)
    else
      {:error, :unsupported_media_type} ->
        error_response(conn, 415, "unsupported_media_type")

      {:error, :malformed_json} ->
        error_response(conn, 400, "malformed_json")

      {:error, :malformed_body} ->
        error_response(conn, 400, "malformed_body")

      {:error, :admission_rejected} ->
        error_response(conn, 422, "admission_rejected")

      {:error, :conflict} ->
        error_response(conn, 409, "conflict")

      {:error, :transient_persistence_failure} ->
        error_response(conn, 503, "transient_persistence_failure")
    end
  end

  defp application_json?(conn) do
    case get_req_header(conn, "content-type") do
      [value] ->
        case Utils.content_type(value) do
          {:ok, "application", "json", _params} -> :ok
          _invalid -> {:error, :unsupported_media_type}
        end

      _missing_or_duplicate ->
        {:error, :unsupported_media_type}
    end
  end

  defp decode_request(body) when is_binary(body) do
    case strict_decode(body) do
      {:ok, value} -> strict_request(value)
      {:error, :malformed_json} -> {:error, :malformed_json}
    end
  end

  defp strict_decode(body) do
    case Jason.decode(body, objects: :ordered_objects, strings: :copy) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, :malformed_json}
    end
  rescue
    _error -> {:error, :malformed_json}
  catch
    _kind, _reason -> {:error, :malformed_json}
  end

  defp strict_request(%Jason.OrderedObject{values: values}) do
    with {:ok, request} <- strict_object(values),
         true <- Map.keys(request) |> Enum.sort() == ["artifacts", "document"],
         {:ok, document} <- required_string(request, "document"),
         {:ok, artifacts} <- required_list(request, "artifacts"),
         {:ok, artifact_values} <- strict_artifacts(artifacts) do
      {:ok, %{document: document, artifacts: artifact_values}}
    else
      _invalid -> {:error, :malformed_body}
    end
  end

  defp strict_request(_invalid), do: {:error, :malformed_body}

  defp strict_artifacts(artifacts) do
    artifacts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new(), []}, &reduce_artifact/2)
    |> case do
      {:ok, _paths, values} -> {:ok, Enum.reverse(values)}
      {:error, _reason} -> {:error, :malformed_body}
    end
  end

  defp reduce_artifact({artifact, _index}, {:ok, paths, values}) do
    case strict_artifact(artifact) do
      {:ok, path, bytes} -> add_artifact(path, bytes, paths, values)
      {:error, _reason} -> {:halt, {:error, :malformed_body}}
    end
  end

  defp add_artifact(path, bytes, paths, values) do
    case MapSet.member?(paths, path) do
      true ->
        {:halt, {:error, :malformed_body}}

      false ->
        {:cont, {:ok, MapSet.put(paths, path), [%{"path" => path, "bytes" => bytes} | values]}}
    end
  end

  defp strict_artifact(%Jason.OrderedObject{values: values}) do
    with {:ok, artifact} <- strict_object(values),
         true <- Map.keys(artifact) |> Enum.sort() == ["bytesBase64", "path"],
         {:ok, path} <- required_string(artifact, "path"),
         {:ok, encoded} <- required_string(artifact, "bytesBase64"),
         {:ok, bytes} <- strict_base64(encoded) do
      {:ok, path, bytes}
    else
      _invalid -> {:error, :malformed_body}
    end
  end

  defp strict_artifact(_invalid), do: {:error, :malformed_body}

  defp strict_object(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, %{}}, fn pair, {:ok, object} ->
      case pair do
        {key, value} when is_binary(key) ->
          put_object(object, key, value)

        _invalid ->
          {:halt, {:error, :malformed_body}}
      end
    end)
  end

  defp strict_object(_invalid), do: {:error, :malformed_body}

  defp put_object(object, key, value) do
    case Map.has_key?(object, key) do
      true -> {:halt, {:error, :duplicate_key}}
      false -> {:cont, {:ok, Map.put(object, key, value)}}
    end
  end

  defp required_string(object, key) do
    case Map.fetch(object, key) do
      {:ok, value} when is_binary(value) ->
        if String.valid?(value), do: {:ok, value}, else: {:error, :malformed_body}

      _invalid ->
        {:error, :malformed_body}
    end
  end

  defp required_list(object, key) do
    case Map.fetch(object, key) do
      {:ok, value} when is_list(value) -> {:ok, value}
      _invalid -> {:error, :malformed_body}
    end
  end

  defp strict_base64(encoded) do
    with true <- Base.valid64?(encoded),
         {:ok, bytes} <- Base.decode64(encoded),
         true <- Base.encode64(bytes) == encoded do
      {:ok, bytes}
    else
      _invalid -> {:error, :malformed_body}
    end
  rescue
    _error -> {:error, :malformed_body}
  end

  defp publisher_identity(conn) do
    case get_req_header(conn, @publisher_identity_header) do
      [] ->
        {:ok, nil}

      [identity] when is_binary(identity) ->
        if byte_size(identity) > 0 and byte_size(identity) <= @max_publisher_identity_bytes and
             String.valid?(identity),
           do: {:ok, identity},
           else: {:error, :malformed_body}

      _invalid ->
        {:error, :malformed_body}
    end
  end

  defp publish(%{document: document, artifacts: artifacts}, publisher_identity) do
    opts = if publisher_identity, do: [publisher_identity: publisher_identity], else: []

    case FrontendReleasePublication.publish_release_with_outcome(document, artifacts, opts) do
      {:ok, publication, outcome} ->
        {:ok, outcome, publication}

      {:error, %{code: code}}
      when code in [
             :release_identity_fork,
             :release_digest_conflict,
             :release_document_conflict,
             :artifact_conflict
           ] ->
        {:error, :conflict}

      {:error, %{code: _code}} ->
        {:error, :admission_rejected}

      {:error, _reason} ->
        {:error, :transient_persistence_failure}
    end
  rescue
    _error -> {:error, :transient_persistence_failure}
  catch
    _kind, _reason -> {:error, :transient_persistence_failure}
  end

  defp response(conn, :created, publication) do
    json(conn |> put_status(:created), %{data: publication_data(publication, "published")})
  end

  defp response(conn, :replayed, publication) do
    json(conn, %{data: publication_data(publication, "replayed")})
  end

  defp publication_data(publication, status) do
    %{
      publication_id: publication.publication_id,
      release_id: publication.release_id,
      status: status
    }
  end

  defp error_response(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code}})
  end
end
