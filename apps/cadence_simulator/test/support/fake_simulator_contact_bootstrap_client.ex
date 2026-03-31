defmodule CadenceSimulator.TestSupport.FakeSimulatorContactBootstrapClient do
  @moduledoc false

  @spec put_responses([map()]) :: :ok
  def put_responses(responses) when is_list(responses) do
    Process.put({__MODULE__, :responses}, responses)
    Process.put({__MODULE__, :requests}, [])
    :ok
  end

  @spec requests() :: [map()]
  def requests do
    Process.get({__MODULE__, :requests}, [])
    |> Enum.reverse()
  end

  @spec new(keyword()) :: keyword()
  def new(opts) when is_list(opts), do: opts

  @spec post!(keyword(), keyword()) :: map()
  def post!(request, opts) when is_list(request) and is_list(opts) do
    record_request(:post, request, opts)
    next_response()
  end

  @spec get!(keyword(), keyword()) :: map()
  def get!(request, opts) when is_list(request) and is_list(opts) do
    record_request(:get, request, opts)
    next_response()
  end

  defp record_request(method, request, opts) do
    requests = Process.get({__MODULE__, :requests}, [])

    Process.put({__MODULE__, :requests}, [
      %{method: method, request: request, opts: opts} | requests
    ])
  end

  defp next_response do
    case Process.get({__MODULE__, :responses}, []) do
      [response | rest] ->
        Process.put({__MODULE__, :responses}, rest)
        response

      [] ->
        raise "missing fake simulator contact bootstrap response"
    end
  end
end
