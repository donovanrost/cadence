defmodule CadenceSimulator.TestSupport.FakeCadenceRuntimeBootstrapClient do
  @moduledoc false

  @spec put_response({:ok, map()} | {:error, term()}) :: :ok
  def put_response(response) do
    Process.put({__MODULE__, :response}, response)
    :ok
  end

  @spec get_json(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_json(_url, _opts) do
    Process.get({__MODULE__, :response}, {:error, :missing_fake_bootstrap_response})
  end
end
