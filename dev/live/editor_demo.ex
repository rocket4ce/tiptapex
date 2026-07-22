defmodule Tiptapex.DevWeb.EditorDemoLive do
  @moduledoc false
  use Phoenix.LiveView

  import Tiptapex.Components

  @sample %{
    "type" => "doc",
    "content" => [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 1},
        "content" => [%{"type" => "text", "text" => "Tiptapex playground"}]
      },
      %{
        "type" => "paragraph",
        "content" => [
          %{
            "type" => "text",
            "text" => "Try the toolbar, drop an image, insert a table, or open "
          },
          %{
            "type" => "text",
            "text" => "this page in two tabs",
            "marks" => [%{"type" => "bold"}]
          },
          %{"type" => "text", "text" => " to see collaboration in action."}
        ]
      }
    ]
  }

  @impl true
  def mount(_params, _session, socket) do
    doc = Agent.get(Tiptapex.DevDoc, & &1) || @sample
    n = System.unique_integer([:positive])

    {:ok,
     socket
     |> assign(:doc, doc)
     |> assign(:characters, nil)
     |> assign(:collab_user, Tiptapex.Collab.user(%{id: n, name: "user-#{rem(n, 1000)}"}))}
  end

  @impl true
  def handle_event("editor_update", %{"json" => json, "characters" => chars}, socket) do
    Agent.update(Tiptapex.DevDoc, fn _ -> json end)
    {:noreply, socket |> assign(:doc, json) |> assign(:characters, chars)}
  end

  def handle_event("uploaded", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    Agent.update(Tiptapex.DevDoc, fn _ -> @sample end)

    {:noreply,
     socket
     |> assign(:doc, @sample)
     |> Tiptapex.Components.set_content("demo", @sample)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dev-panel">
      <div class="dev-panel-title">Editor — collab on, uploads to local disk</div>
      <div class="dev-panel-body">
        <.tiptapex_editor
          id="demo"
          value={@doc}
          upload_url="/uploads"
          collab={%{topic: "doc:demo", socket_path: "/socket", user: @collab_user}}
          on_change="editor_update"
          on_uploaded="uploaded"
        >
          <:actions>
            <button phx-click="reset" style="cursor: pointer;">Reset content</button>
          </:actions>
        </.tiptapex_editor>
      </div>
    </div>

    <div class="dev-panel">
      <div class="dev-panel-title">
        Server-rendered preview (Tiptapex.Renderer) {if @characters, do: "— #{@characters} chars"}
      </div>
      <%!-- ids: false is REQUIRED here: this panel shows the same doc as the
      live editor above, and duplicate DOM ids would let LiveView's patcher
      steal nodes out of the editor. See Tiptapex.Renderer docs. --%>
      <div class="dev-panel-body ttx-prose">
        {Tiptapex.Renderer.to_html(@doc, ids: false)}
      </div>
    </div>
    """
  end
end
