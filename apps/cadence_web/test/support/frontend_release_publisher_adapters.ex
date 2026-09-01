defmodule CadenceWeb.FrontendReleasePublisherTestAdapter do
  @moduledoc false

  def body(body, owner), do: %{mode: :body, body: body, owner: owner, reads: 0}

  def responses(responses, owner),
    do: %{mode: :responses, responses: responses, owner: owner, reads: 0}

  def read_req_body(%{mode: :body, body: body} = state, opts) do
    notify_read(state.owner, state.reads, opts)
    length = Keyword.fetch!(opts, :length)
    size = min(byte_size(body), length)
    chunk = :binary.part(body, 0, size)
    rest = :binary.part(body, size, byte_size(body) - size)
    tag = if rest == "", do: :ok, else: :more

    {tag, chunk, %{state | body: rest, reads: state.reads + 1}}
  end

  def read_req_body(%{mode: :responses, responses: [response | rest]} = state, opts) do
    notify_read(state.owner, state.reads, opts)

    case response do
      {:ok, body} when is_binary(body) ->
        {:ok, body, %{state | responses: rest, reads: state.reads + 1}}

      {:more, body} when is_binary(body) ->
        {:more, body, %{state | responses: rest, reads: state.reads + 1}}

      {:error, reason} ->
        {:error, reason}

      {:raise, exception} when is_atom(exception) ->
        raise exception

      {:exit, reason} ->
        exit(reason)

      {:throw, value} ->
        throw(value)
    end
  end

  def read_req_body(%{mode: :responses} = state, opts) do
    notify_read(state.owner, state.reads, opts)
    {:error, :closed}
  end

  def send_resp(state, status, headers, body) do
    body = IO.iodata_to_binary(body)
    send(state.owner, {:frontend_release_publisher_response, status, headers, body})
    {:ok, body, state}
  end

  defp notify_read(owner, reads, opts),
    do: send(owner, {:frontend_release_publisher_read, reads, opts})
end
