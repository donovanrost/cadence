defmodule CadenceSimulator.CadenceRuntimeBootstrap.ReqClient do
  @moduledoc false

  @spec get_json(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_json(url, opts) when is_binary(url) and is_list(opts) do
    request_opts = [
      url: url,
      headers: Keyword.get(opts, :headers, []),
      receive_timeout: Keyword.get(opts, :receive_timeout, 5_000)
    ]

    case Req.get(request_opts) do
      {:ok, %Req.Response{status: status, body: %{"data" => data}}}
      when status >= 200 and status < 300 ->
        {:ok, data}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:cadence_runtime_bootstrap_http_error, status, body}}

      {:error, reason} ->
        {:error, {:cadence_runtime_bootstrap_request_failed, reason}}
    end
  end
end
