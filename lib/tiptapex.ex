defmodule Tiptapex do
  @moduledoc """
  Tiptap v3 rich-text editing for Phoenix LiveView.

  Tiptapex packages a full editor integration:

    * `Tiptapex.Components` — `tiptapex_editor/1` and `tiptapex_viewer/1`
      HEEx function components backed by the `TiptapexEditor` /
      `TiptapexViewer` JS hooks shipped inside this package.
    * `Tiptapex.Renderer` — converts ProseMirror/Tiptap JSON documents to
      safe, escaped HTML on the server, so you never have to trust
      client-generated HTML.
    * `Tiptapex.Upload` — a behaviour plus `Tiptapex.Upload.Controller`
      macro for handling editor file uploads with server-side validation.
    * `Tiptapex.Collab` — optional realtime collaboration (Yjs) over
      Phoenix Channels via the `Tiptapex.Collab.Channel` macro.

  ## JavaScript setup

  The JS ships as raw ESM inside the Hex package. Your app bundles it with
  its own copy of the `@tiptap/*` packages (peer dependencies — install
  them with npm in `assets/`). Point esbuild's `NODE_PATH` at both `deps`
  and `assets/node_modules`, then:

      import { hooks as tiptapex } from "tiptapex"

      const liveSocket = new LiveSocket("/live", Socket, {
        hooks: { ...otherHooks, ...tiptapex },
      })

  See the README for the full installation walkthrough.
  """

  @doc """
  Returns an empty Tiptap document.

  Useful as a default value for new records:

      schema "articles" do
        field :body, :map, default: Tiptapex.empty_doc()
      end
  """
  @spec empty_doc() :: map()
  def empty_doc do
    %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
  end

  @doc """
  Returns true when the given document is `nil`, empty, or contains no text,
  media, or horizontal rules.
  """
  @spec blank_doc?(map() | nil) :: boolean()
  def blank_doc?(nil), do: true
  def blank_doc?(doc) when doc == %{}, do: true

  def blank_doc?(%{} = doc) do
    Tiptapex.Renderer.to_plain_text(doc) == "" and not has_content_node?(doc)
  end

  def blank_doc?(_), do: true

  defp has_content_node?(%{"content" => content}) when is_list(content),
    do: Enum.any?(content, &content_node?/1)

  defp has_content_node?(_), do: false

  defp content_node?(%{"type" => type}) when type in ~w(image video horizontalRule), do: true
  defp content_node?(%{"content" => _} = node), do: has_content_node?(node)
  defp content_node?(_), do: false

  @doc "Delegates to `Tiptapex.Renderer.to_html/2`."
  defdelegate to_html(doc, opts \\ []), to: Tiptapex.Renderer

  @doc "Delegates to `Tiptapex.Renderer.to_plain_text/1`."
  defdelegate to_plain_text(doc), to: Tiptapex.Renderer
end
