defmodule CadenceWeb.FrontendReleaseArtifactDisconnectAdapter do
  @moduledoc false

  def send_chunked(state, _status, _headers), do: {:ok, "", state}
  def chunk(_state, _body), do: {:error, :closed}
end
