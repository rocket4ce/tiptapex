defmodule Tiptapex.DevWeb.EditorDemoLive do
  @moduledoc false
  use Phoenix.LiveView

  import Tiptapex.Components

  # Page setup lives in the document itself, so the demo doc opens paginated
  # and `/print` exports it without being told anything else.
  # A data: URI so the demo needs no asset on disk — and so it exercises the
  # one src shape Chrome can always resolve in a running header. Upload a real
  # logo through the page dialog to replace it.
  @logo "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMzIiIGhlaWdodD0iMzYiIHZpZXdCb3g9IjAgMCAxMzIgMzYiPjxyZWN0IHdpZHRoPSIxMzIiIGhlaWdodD0iMzYiIHJ4PSI2IiBmaWxsPSIjN2MzYWVkIi8+PHRleHQgeD0iNjYiIHk9IjI0IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLEFyaWFsLHNhbnMtc2VyaWYiIGZvbnQtc2l6ZT0iMTYiIGZvbnQtd2VpZ2h0PSI3MDAiIGZpbGw9IiNmZmZmZmYiIHRleHQtYW5jaG9yPSJtaWRkbGUiPlRpcHRhcGV4PC90ZXh0Pjwvc3ZnPg=="

  @page %{
    size: :letter,
    margins: %{top: 20, right: 20, bottom: 20, left: 20},
    header: %{
      left: %{text: "", image: %{src: @logo, height: 9}},
      center: "",
      right: ~s(<span style="color: #6b7280">{date}</span>)
    },
    numbering: %{enabled: true, region: :footer, align: :center, format: "{page} / {pages}"}
  }

  @sample %{
    "type" => "doc",
    "attrs" => %{"page" => Tiptapex.Page.to_map(Tiptapex.Page.new(@page))},
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

  @doc false
  def sample_doc, do: @sample

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

  def handle_event("landscape", _params, socket) do
    page = Tiptapex.Page.from_doc(socket.assigns.doc, true)
    flipped = if page.orientation == :landscape, do: :portrait, else: :landscape

    {:noreply, Tiptapex.Components.set_page(socket, "demo", %{page | orientation: flipped})}
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
          count_template="{chars} characters · {words} words · {pages} pages"
        >
          <:actions>
            <button phx-click="reset" style="cursor: pointer;">Reset content</button>
            <button phx-click="landscape" style="cursor: pointer;">Toggle orientation</button>
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
