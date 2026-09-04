defmodule CadenceWeb.FrontendReleasePublisherController do
  @moduledoc false

  use CadenceWeb, :controller

  alias CadenceWeb.ApplicationReleaseRegistry
  alias CadenceWeb.FrontendReleaseActivation
  alias CadenceWeb.FrontendReleasePublication
  alias CadenceWeb.Plugs.FrontendReleasePublisher
  alias CadenceWeb.Plugs.FrontendReleaseRequestBody

  @publisher_identity_header "x-cadence-publisher-identity"
  @idempotency_key_header "idempotency-key"
  @promotion_route "/api/cadence/frontend-release/v1/promotions"
  @max_publisher_identity_bytes 128
  @publication_config_key :frontend_release_publication_config
  @authority_now_key :frontend_release_authority_now

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    authority_now = authority_now(conn)

    with :ok <- application_json?(conn),
         {:ok, authority_now} <- authority_now,
         {:ok, body} <- FrontendReleaseRequestBody.raw_body(conn),
         {:ok, request} <- decode_request(body),
         {:ok, publisher_identity} <- publisher_identity(conn),
         {:ok, outcome, publication} <-
           publish(request, publisher_identity, conn, authority_now) do
      response(conn, outcome, publication)
    else
      {:error, :unsupported_media_type} ->
        error_response(conn, 415, "unsupported_media_type")

      {:error, :malformed_json} ->
        error_response(conn, 400, "malformed_json")

      {:error, :malformed_body} ->
        error_response(conn, 400, "malformed_body")

      {:error, :invalid_authority_now} ->
        error_response(conn, 422, "admission_rejected")

      {:error, :admission_rejected} ->
        error_response(conn, 422, "admission_rejected")

      {:error, :conflict} ->
        error_response(conn, 409, "conflict")

      {:error, :transient_persistence_failure} ->
        error_response(conn, 503, "transient_persistence_failure")

      {:error, status, code} ->
        error_response(conn, status, code)
    end
  end

  @spec promote(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def promote(conn, _params) do
    authority_now = authority_now(conn)

    if conn.request_path == @promotion_route do
      with :ok <- application_json?(conn),
           {:ok, authority_now} <- authority_now,
           {:ok, body} <- FrontendReleaseRequestBody.raw_body(conn),
           {:ok, document} <- decode_promotion_request(body),
           {:ok, idempotency_key} <- idempotency_key(conn),
           {:ok, publisher_identity} <- publisher_identity(conn),
           {:ok, response} <-
             activate_catalog(document, idempotency_key, publisher_identity, conn, authority_now) do
        send_exact_response(conn, response)
      else
        {:error, :unsupported_media_type} ->
          error_response(conn, 415, "unsupported_media_type")

        {:error, :malformed_json} ->
          error_response(conn, 400, "malformed_json")

        {:error, :malformed_body} ->
          error_response(conn, 400, "malformed_body")

        {:error, :invalid_authority_now} ->
          error_response(conn, 422, "admission_rejected")

        {:error, :malformed_idempotency_key} ->
          error_response(conn, 400, "malformed_idempotency_key")

        {:error, %{status: status, body: body}} ->
          send_exact_response(conn, %{status: status, body: body})

        {:error, status, code} ->
          error_response(conn, status, code)
      end
    else
      send_resp(conn, 404, "")
    end
  end

  @spec upload(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def upload(conn, %{"digest" => digest}) do
    case FrontendReleaseRequestBody.staged_artifact_path(conn) do
      {:ok, file_path} ->
        try do
          result = FrontendReleasePublication.stage_artifact(digest, file_path)

          case result do
            {:ok, %{status: :stored} = stored} ->
              upload_response(conn, 201, stored)

            {:ok, %{status: :existing} = stored} ->
              upload_response(conn, 200, stored)

            {:error, reason} ->
              artifact_error_response(conn, reason)
          end
        rescue
          error in [DBConnection.ConnectionError, Postgrex.Error] ->
            if transient_database_failure?(error) do
              error_response(conn, 503, "transient_persistence_failure")
            else
              reraise(error, __STACKTRACE__)
            end
        after
          _ = FrontendReleaseRequestBody.cleanup_staged_artifact(conn)
        end

      {:error, reason} ->
        artifact_error_response(conn, reason)
    end
  end

  defp application_json?(conn) do
    FrontendReleasePublisher.application_json?(conn)
  end

  defp decode_request(body) when is_binary(body) do
    case strict_decode(body) do
      {:ok, value} -> strict_request(value)
      {:error, :malformed_json} -> {:error, :malformed_json}
    end
  end

  defp decode_promotion_request(body) when is_binary(body) do
    case strict_decode(body) do
      {:ok, %Jason.OrderedObject{values: values}} ->
        with {:ok, request} <- strict_object(values),
             ["document"] <- Map.keys(request) |> Enum.sort(),
             {:ok, document} <- required_string(request, "document") do
          {:ok, document}
        else
          _ -> {:error, :malformed_body}
        end

      {:ok, _value} ->
        {:error, :malformed_body}

      {:error, :malformed_json} ->
        {:error, :malformed_json}
    end
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, @idempotency_key_header) do
      [value] when is_binary(value) and byte_size(value) in 1..128 ->
        {:ok, value}

      _invalid ->
        {:error, :malformed_idempotency_key}
    end
  end

  defp activate_catalog(document, idempotency_key, publisher_identity, conn, authority_now) do
    opts =
      []
      |> maybe_put(:publisher_identity, publisher_identity)
      |> maybe_put(:publication_config, Map.get(conn.private, @publication_config_key))
      |> Keyword.put(:now, authority_now)

    case FrontendReleaseActivation.activate_catalog(document, idempotency_key, opts) do
      {:ok, response} -> {:ok, response}
      {:error, %{status: _status, body: _body} = response} -> {:error, response}
      {:error, _failure} -> {:error, 500, "integrity_failure"}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, :undefined), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp send_exact_response(conn, %{status: status, body: body}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp strict_decode(body) do
    case Jason.decode(body, objects: :ordered_objects, strings: :copy) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, :malformed_json}
    end
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
      {:ok, path, value} -> add_artifact(path, value, paths, values)
      {:error, _reason} -> {:halt, {:error, :malformed_body}}
    end
  end

  defp add_artifact(path, value, paths, values) do
    case MapSet.member?(paths, path) do
      true ->
        {:halt, {:error, :malformed_body}}

      false ->
        {:cont, {:ok, MapSet.put(paths, path), [value | values]}}
    end
  end

  defp strict_artifact(%Jason.OrderedObject{values: values}) do
    with {:ok, artifact} <- strict_object(values),
         {:ok, path, value} <- strict_artifact_value(artifact) do
      {:ok, path, value}
    else
      _invalid -> {:error, :malformed_body}
    end
  end

  defp strict_artifact(_invalid), do: {:error, :malformed_body}

  defp strict_artifact_value(artifact) do
    case Map.keys(artifact) |> Enum.sort() do
      ["bytesBase64", "path"] ->
        with {:ok, path} <- required_string(artifact, "path"),
             {:ok, encoded} <- required_string(artifact, "bytesBase64"),
             {:ok, bytes} <- strict_base64(encoded) do
          {:ok, path, %{"path" => path, "bytes" => bytes}}
        end

      ["path", "sha256", "size"] ->
        with {:ok, path} <- required_string(artifact, "path"),
             {:ok, digest} <- required_digest(artifact, "sha256"),
             {:ok, size} <- required_size(artifact, "size") do
          {:ok, path, %{"path" => path, "sha256" => digest, "size" => size}}
        end

      _invalid ->
        {:error, :malformed_body}
    end
  end

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

  defp required_digest(object, key) do
    case Map.fetch(object, key) do
      {:ok, value} when is_binary(value) ->
        if Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value),
          do: {:ok, value},
          else: {:error, :malformed_body}

      _invalid ->
        {:error, :malformed_body}
    end
  end

  defp required_size(object, key) do
    case Map.fetch(object, key) do
      {:ok, value} when is_integer(value) and value >= 0 -> {:ok, value}
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

  defp publish(
         %{document: document, artifacts: artifacts},
         publisher_identity,
         conn,
         authority_now
       ) do
    opts = if publisher_identity, do: [publisher_identity: publisher_identity], else: []
    opts = Keyword.put(opts, :now, authority_now)

    opts =
      case Map.get(conn.private, @publication_config_key) do
        config when is_list(config) -> Keyword.put(opts, :publication_config, config)
        _missing_or_invalid -> opts
      end

    FrontendReleasePublication.publish_release_with_outcome(document, artifacts, opts)
    |> classify_publish_result()
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      if transient_database_failure?(error) do
        {:error, 503, "transient_persistence_failure"}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp authority_now(conn) do
    candidate = Map.get_lazy(conn.private, @authority_now_key, &request_boundary_now/0)

    case ApplicationReleaseRegistry.normalize_now(candidate) do
      {:ok, _milliseconds} -> {:ok, candidate}
      {:error, _reason} -> {:error, :invalid_authority_now}
    end
  end

  defp request_boundary_now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp classify_publish_result({:ok, publication, outcome}),
    do: {:ok, outcome, publication}

  defp classify_publish_result({:error, %DBConnection.ConnectionError{}}),
    do: {:error, 503, "transient_persistence_failure"}

  defp classify_publish_result({:error, %Postgrex.Error{postgres: %{code: :admin_shutdown}}}),
    do: {:error, 503, "transient_persistence_failure"}

  defp classify_publish_result({:error, {_operation, %DBConnection.ConnectionError{}}}),
    do: {:error, 503, "transient_persistence_failure"}

  defp classify_publish_result(
         {:error, {_operation, %Postgrex.Error{postgres: %{code: :admin_shutdown}}}}
       ),
       do: {:error, 503, "transient_persistence_failure"}

  defp classify_publish_result({:error, %{code: code}})
       when code in [
              :release_identity_fork,
              :release_digest_conflict,
              :release_document_conflict,
              :artifact_conflict
            ],
       do: {:error, 409, "conflict"}

  defp classify_publish_result({:error, %{code: _code}}),
    do: {:error, 422, "admission_rejected"}

  defp classify_publish_result(other), do: other

  defp artifact_error_response(conn, %DBConnection.ConnectionError{}),
    do: error_response(conn, 503, "transient_persistence_failure")

  defp artifact_error_response(conn, %Postgrex.Error{postgres: %{code: :admin_shutdown}}),
    do: error_response(conn, 503, "transient_persistence_failure")

  defp artifact_error_response(conn, {_operation, %DBConnection.ConnectionError{}}),
    do: error_response(conn, 503, "transient_persistence_failure")

  defp artifact_error_response(
         conn,
         {_operation, %Postgrex.Error{postgres: %{code: :admin_shutdown}}}
       ),
       do: error_response(conn, 503, "transient_persistence_failure")

  defp artifact_error_response(conn, %{code: code})
       when code in [:artifact_conflict, :artifact_bytes_mismatch],
       do: error_response(conn, 409, "conflict")

  defp artifact_error_response(conn, %{code: _code}),
    do: error_response(conn, 422, "admission_rejected")

  defp artifact_error_response(conn, _reason),
    do: error_response(conn, 422, "admission_rejected")

  defp upload_response(conn, status, stored) do
    json(conn |> put_status(status), %{
      data: %{digest: stored.digest, size: stored.size, status: Atom.to_string(stored.status)}
    })
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

  defp transient_database_failure?(%DBConnection.ConnectionError{}), do: true

  defp transient_database_failure?(%Postgrex.Error{postgres: %{code: :admin_shutdown}}),
    do: true

  defp transient_database_failure?(_error), do: false

  defp error_response(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code}})
  end
end
