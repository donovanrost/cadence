defmodule CadenceWeb.Layouts do
  @moduledoc "Host document and LiveVue shell transport. Presentation belongs to the frontend host."
  use CadenceWeb, :html
  embed_templates("layouts/*")
end
