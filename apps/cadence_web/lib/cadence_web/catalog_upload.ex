defmodule CadenceWeb.CatalogUpload do
  @moduledoc "Path-bound Phoenix upload lifecycle for the host's Catalog database feature."

  import Phoenix.Component
  import Phoenix.LiveView

  alias Cadence.Catalog.{Registry, Upload}

  @pages ["catalog_database_new", "catalog_database_show"]

  def prepare(socket, info, path) do
    available? =
      match?(%{status: "ready", page: page} when page in @pages, socket.assigns.catalog)

    previous = socket.assigns[:catalog_upload_session]

    cond do
      (available? and previous) && previous.path == path ->
        if previous.phase == :ready, do: socket, else: activate(socket)

      available? ->
        socket
        |> reset()
        |> assign(:catalog_upload_session, %{
          path: path,
          token: Ecto.UUID.generate(),
          mission_id: info.params["mission_id"],
          database_id: info.params["catalog_database_id"],
          values: %{},
          errors: %{},
          error: nil,
          attempt: 0,
          phase: :waiting
        })
        |> activate()

      true ->
        reset(socket)
    end
  end

  defp activate(socket) do
    case uploaded_entries(socket, :catalog_artifact) do
      {[], []} ->
        # Retire the old upload ref as well as the application session token.
        # Otherwise delayed preflight messages could resolve to the new slot.
        socket =
          if get_in(socket.assigns, [:uploads, :catalog_artifact]),
            do: disallow_upload(socket, :catalog_artifact),
            else: socket

        socket
        |> allow_upload(:catalog_artifact,
          accept: :any,
          max_entries: 1,
          max_file_size: Upload.max_bytes()
        )
        |> assign(:catalog_upload_session, %{
          socket.assigns.catalog_upload_session
          | phase: :ready
        })

      _draining ->
        Process.send_after(self(), :catalog_upload_drain, 10)
        socket
    end
  end

  def matches?(socket, %{"catalog_upload" => %{"path" => path, "token" => token}}) do
    case socket.assigns[:catalog_upload_session] do
      %{path: ^path, token: ^token, phase: :ready} -> path == socket.assigns.host_path
      _ -> false
    end
  end

  def matches?(_socket, _params), do: false

  def handle_event("catalog:upload:validate", %{"catalog_upload" => params}, socket),
    do: {:noreply, validate(socket, params)}

  def handle_event("catalog:upload:cancel", %{"ref" => ref}, socket) when is_binary(ref) do
    socket =
      if Enum.any?(
           socket.assigns.uploads.catalog_artifact.entries,
           &(&1.ref == ref and not &1.cancelled?)
         ),
         do: cancel_upload(socket, :catalog_artifact, ref),
         else: socket

    {:noreply,
     assign(socket, :catalog_upload_session, %{socket.assigns.catalog_upload_session | error: nil})}
  end

  def handle_event("catalog:upload:save", %{"catalog_upload" => params}, socket) do
    socket = validate(socket, params)
    session = socket.assigns.catalog_upload_session

    result =
      with {:ok, _values} <- Upload.validate(session.database_id, params),
           {[entry], []} when entry.valid? and not entry.cancelled? <-
             uploaded_entries(socket, :catalog_artifact) do
        consume(socket, entry, session, params)
      else
        _ -> {:error, :incomplete_upload}
      end

    finish(socket, result)
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp consume(socket, entry, session, params) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      result =
        with {:ok, bytes} <- read_bounded(path) do
          Upload.import_revision(
            socket.assigns.current_scope,
            session.mission_id,
            session.database_id,
            params,
            %{filename: entry.client_name, client_type: entry.client_type, bytes: bytes}
          )
        end

      case result do
        {:ok, run} -> {:ok, {:ok, run}}
        {:error, reason} -> {:postpone, {:error, reason}}
      end
    end)
  end

  def presentation(assigns) do
    case {assigns[:catalog], assigns[:catalog_upload_session]} do
      {%{status: "ready", data: data} = catalog, %{phase: :ready} = session} ->
        config = assigns.uploads.catalog_artifact

        errors =
          Enum.map(config.errors, fn {ref, error} ->
            %{
              ref: ref,
              error: to_string(error),
              code: to_string(error),
              message: upload_error(error)
            }
          end)

        entries = Enum.map(config.entries, &present_entry(&1, errors))

        detected = detect(config.entries)
        key = if catalog.page == "catalog_database_new", do: "form", else: "revision_form"
        form = present_fields(data[key], session)

        upload = %{
          ref: config.ref,
          name: "catalog_artifact",
          accept: false,
          max_entries: 1,
          max_file_size: Upload.max_bytes(),
          auto_upload: false,
          entries: entries,
          errors: errors
        }

        disabled? =
          length(entries) != 1 or errors != [] or detected.status != "detected" or
            not match?({:ok, _}, Upload.validate(session.database_id, session.values))

        catalog
        |> Map.put(
          :data,
          data
          |> Map.put(key, form)
          |> Map.put("upload", upload)
          |> Map.put("detected_importer", detected)
          |> Map.put("submit_disabled", disabled?)
        )
        |> Map.put(:upload_session, Map.take(session, [:path, :token, :error, :attempt]))

      {catalog, _} ->
        catalog
    end
  end

  def form(assigns) do
    case assigns[:catalog_upload_session] do
      session when is_nil(session) or session.phase != :ready ->
        nil

      session ->
        session.values
        |> Map.merge(%{"path" => session.path, "token" => session.token})
        |> to_form(as: :catalog_upload)
    end
  end

  defp present_entry(entry, errors) do
    %{
      ref: entry.ref,
      client_name: entry.client_name,
      client_size: entry.client_size,
      client_type: entry.client_type || "",
      progress: entry.progress,
      done: entry.done?,
      valid: entry.valid?,
      preflighted: entry.preflighted?,
      errors: for(error <- errors, error.ref == entry.ref, do: error.message)
    }
  end

  defp present_fields(form, session) do
    Enum.reduce(~w(primary_fields secondary_fields), form, fn fields, acc ->
      Map.update!(acc, fields, fn rows -> Enum.map(rows, &field(&1, session)) end)
    end)
  end

  defp validate(socket, params) do
    session = socket.assigns.catalog_upload_session
    values = Map.take(params, Upload.fields(session.database_id))

    errors =
      case Upload.validate(session.database_id, values) do
        {:ok, _} -> %{}
        {:error, errors} -> errors
      end

    # Never reflect nested or oversized values back to HTML/JSON.
    values =
      Map.reject(values, fn {_key, value} ->
        not is_binary(value) or byte_size(value) > 4096 or not String.valid?(value)
      end)

    assign(socket, :catalog_upload_session, %{
      session
      | values: values,
        errors: errors,
        error: nil
    })
  end

  defp finish(socket, {:ok, run}) do
    session = socket.assigns.catalog_upload_session

    socket =
      assign(socket, :catalog_upload_session, %{
        session
        | attempt: session.attempt + 1,
          error: nil
      })

    {:noreply,
     push_event(socket, "catalog:uploaded", %{
       path: session.path,
       token: session.token,
       href: "/missions/#{session.mission_id}/catalog/imports/#{run.import_run_id}"
     })}
  end

  defp finish(socket, {:error, _reason}) do
    session = socket.assigns.catalog_upload_session

    {:noreply,
     assign(socket, :catalog_upload_session, %{
       session
       | attempt: session.attempt + 1,
         error: "The revision could not be imported. Check the fields and file, then try again."
     })}
  end

  defp reset(socket) do
    socket =
      if get_in(socket.assigns, [:uploads, :catalog_artifact]) do
        socket = cancel_entries(socket)

        # Upload channels remove cancelled entries asynchronously. Revoking the
        # slot in the same callback would raise while those entries are draining.
        case uploaded_entries(socket, :catalog_artifact) do
          {[], []} -> disallow_upload(socket, :catalog_artifact)
          _ -> socket
        end
      else
        socket
      end

    assign(socket, :catalog_upload_session, nil)
  end

  defp cancel_entries(socket) do
    Enum.reduce(socket.assigns.uploads.catalog_artifact.entries, socket, fn entry, acc ->
      if entry.cancelled?, do: acc, else: cancel_upload(acc, :catalog_artifact, entry.ref)
    end)
  end

  defp read_bounded(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, Upload.max_bytes() + 1) do
          bytes when is_binary(bytes) -> {:ok, bytes}
          _ -> {:error, :invalid_catalog_upload}
        end
      after
        File.close(file)
      end
    end
  end

  defp field(row, session),
    do:
      row
      |> Map.put("value", Map.get(session.values, row["key"], ""))
      |> Map.put("errors", List.wrap(session.errors[row["key"]]))

  defp detect([entry]) do
    case Registry.detect_importer(entry.client_name, entry.client_type) do
      {:ok, %{descriptor: descriptor}} ->
        %{status: "detected", display_name: descriptor.display_name}

      _ ->
        %{status: "unsupported", display_name: nil}
    end
  end

  defp detect(_entries), do: %{status: "empty", display_name: nil}
  defp upload_error(:too_large), do: "The file exceeds the 50 MiB limit."
  defp upload_error(:too_many_files), do: "Select one file at a time."
  defp upload_error(_error), do: "The file could not be uploaded. Remove it and try again."
end
