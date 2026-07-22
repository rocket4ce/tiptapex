defmodule Tiptapex.DevWeb.ViewerDemoLive do
  @moduledoc false
  use Phoenix.LiveView

  import Tiptapex.Components

  @impl true
  def mount(_params, _session, socket) do
    doc = Agent.get(Tiptapex.DevDoc, & &1) || Tiptapex.empty_doc()
    {:ok, assign(socket, :doc, doc)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dev-panel">
      <div class="dev-panel-title">Hydrated viewer (SSR fallback + client Tiptap)</div>
      <div class="dev-panel-body">
        <.tiptapex_viewer id="viewer" value={@doc} />
      </div>
    </div>

    <div class="dev-panel">
      <div class="dev-panel-title">Static viewer (server HTML only, no JS)</div>
      <div class="dev-panel-body">
        <.tiptapex_viewer value={@doc} hydrate={false} />
      </div>
    </div>

    <p style="font-size: 0.85rem; color: #6b7280;">
      Edit the doc on <a href="/">the editor page</a> and reload — both panels
      should look identical.
    </p>
    """
  end
end
