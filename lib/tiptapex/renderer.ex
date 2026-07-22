defmodule Tiptapex.Renderer do
  @moduledoc """
  Renders Tiptap/ProseMirror JSON documents to safe HTML on the server.

      {:safe, _} = Tiptapex.Renderer.to_html(article.body)

  In HEEx just interpolate it — no `raw/1` needed, and none should ever be
  used with client-provided HTML:

      <div class="ttx-prose">{Tiptapex.Renderer.to_html(@article.body)}</div>

  All text is escaped, attributes go through an allow-list per node, URLs
  must be http(s)/mailto/relative, iframes are restricted to rebuilt
  YouTube embed URLs, and inline CSS values must match a strict grammar
  (see `Tiptapex.Renderer.URL`). Unknown node/mark types are dropped by
  default.

  ## Options

    * `:nodes` — map of `"type" => renderer` merged over the built-ins,
      where renderer is a `(node, children_iodata, opts) -> iodata` fun or
      a module implementing `Tiptapex.Renderer.Node`.
    * `:marks` — same for marks: `(mark, children_iodata, opts) -> iodata`.
    * `:on_unknown` — what to do with unknown node/mark types: `:drop`
      (default), `:keep_children`, or `:raise`.
    * `:ids` — whether to emit heading `id` attributes (default `true`).
      **Pass `false` whenever the rendered HTML appears on the same page
      as a live editor showing the same document** (e.g. a preview panel):
      the editor's DOM carries the same ids, and LiveView's DOM patcher
      matches elements by id globally — it will steal nodes out of the
      editor (even inside `phx-update="ignore"`), deleting them from the
      document.

  ## Custom nodes

      defmodule MyApp.CalloutNode do
        @behaviour Tiptapex.Renderer.Node
        alias Tiptapex.Renderer.HTML

        @impl true
        def render(_node, children, _opts) do
          HTML.tag("aside", [{"class", "callout"}], children)
        end
      end

      Tiptapex.Renderer.to_html(doc, nodes: %{"callout" => MyApp.CalloutNode})
  """

  alias Tiptapex.Renderer.{HTML, Marks, Nodes}

  defmodule Node do
    @moduledoc """
    Behaviour for custom node (or mark) renderers passed to
    `Tiptapex.Renderer.to_html/2` via the `:nodes` / `:marks` options.

    `children` is the already-rendered, already-escaped iodata of the
    node's content. Return iodata; use `Tiptapex.Renderer.HTML` to build
    tags so attribute values stay escaped.
    """

    @callback render(node :: map(), children :: iodata(), opts :: map()) :: iodata()
  end

  @doc """
  Converts a Tiptap JSON document (map, string or atom keys) to
  `{:safe, iodata}`.
  """
  @spec to_html(map() | nil, keyword()) :: Phoenix.HTML.safe()
  def to_html(doc, opts \\ [])

  def to_html(nil, _opts), do: {:safe, ""}
  def to_html(doc, _opts) when doc == %{}, do: {:safe, ""}

  def to_html(doc, opts) when is_map(doc) do
    opts = %{
      nodes: opts |> Keyword.get(:nodes, %{}) |> stringify_keys(),
      marks: opts |> Keyword.get(:marks, %{}) |> stringify_keys(),
      on_unknown: Keyword.get(opts, :on_unknown, :drop),
      ids: Keyword.get(opts, :ids, true)
    }

    {:safe, doc |> normalize() |> render_node(opts)}
  end

  @doc """
  Extracts the document's plain text — for excerpts, search indexing, or
  emptiness checks. Blocks are separated by newlines; media nodes are
  skipped.
  """
  @spec to_plain_text(map() | nil) :: String.t()
  def to_plain_text(nil), do: ""

  def to_plain_text(doc) when is_map(doc) do
    doc
    |> normalize()
    |> plain_text()
    |> IO.iodata_to_binary()
    |> String.replace(~r/\n{2,}/, "\n")
    |> String.trim()
  end

  def to_plain_text(_), do: ""

  @doc """
  Lists the document's headings as `%{level: 1..6, id: binary | nil,
  text: binary}` — ready to build a table of contents. Ids come from the
  UniqueID extension when present.
  """
  @spec headings(map() | nil) :: [%{level: 1..6, id: binary() | nil, text: binary()}]
  def headings(nil), do: []

  def headings(doc) when is_map(doc) do
    doc |> normalize() |> collect_headings() |> Enum.reverse()
  end

  def headings(_), do: []

  # ---------------------------------------------------------------------
  # Node walking
  # ---------------------------------------------------------------------

  defp render_node(%{"type" => "text"} = node, opts) do
    io = HTML.escape(node["text"])
    wrap_marks(io, marks_of(node), opts)
  end

  defp render_node(%{"type" => type} = node, opts) do
    children = render_children(node, opts)

    case Map.fetch(opts.nodes, type) do
      {:ok, renderer} ->
        apply_renderer(renderer, node, children, opts)

      :error ->
        case Nodes.render(type, node, children, opts) do
          {:ok, io} -> io
          :unknown -> unknown(:node, type, children, opts)
        end
    end
  end

  defp render_node(_node, _opts), do: ""

  defp render_children(%{"content" => content}, opts) when is_list(content) do
    Enum.map(content, &render_node(&1, opts))
  end

  defp render_children(_node, _opts), do: ""

  # ---------------------------------------------------------------------
  # Marks
  # ---------------------------------------------------------------------

  defp wrap_marks(io, [], _opts), do: io

  defp wrap_marks(io, marks, opts) do
    order = Marks.order()

    marks
    # Outermost-first order; unknown/custom marks wrap outside the rest.
    |> Enum.sort_by(fn mark -> Enum.find_index(order, &(&1 == mark_type(mark))) || -1 end)
    # Apply innermost first.
    |> Enum.reverse()
    |> Enum.reduce(io, fn mark, acc -> wrap_mark(acc, mark, opts) end)
  end

  defp wrap_mark(io, mark, opts) do
    type = mark_type(mark)

    case Map.fetch(opts.marks, type) do
      {:ok, renderer} ->
        apply_renderer(renderer, mark, io, opts)

      :error ->
        case Marks.render(type, mark, io, opts) do
          {:ok, wrapped} -> wrapped
          :unknown -> unknown(:mark, type, io, opts)
        end
    end
  end

  defp mark_type(%{"type" => type}), do: type
  defp mark_type(_), do: nil

  defp marks_of(%{"marks" => marks}) when is_list(marks), do: marks
  defp marks_of(_), do: []

  defp apply_renderer(module, node, children, opts) when is_atom(module),
    do: module.render(node, children, opts)

  defp apply_renderer(fun, node, children, opts) when is_function(fun, 3),
    do: fun.(node, children, opts)

  # An unknown NODE is dropped whole (children included) — we can't know if
  # its content is safe to show detached. An unknown MARK only loses its
  # wrapper: the children are the text itself, already escaped.
  defp unknown(:node, _type, _children, %{on_unknown: :drop}), do: ""
  defp unknown(:mark, _type, children, %{on_unknown: :drop}), do: children
  defp unknown(_kind, _type, children, %{on_unknown: :keep_children}), do: children

  defp unknown(kind, type, _children, %{on_unknown: :raise}) do
    raise ArgumentError, "unknown Tiptap #{kind} type: #{inspect(type)}"
  end

  # ---------------------------------------------------------------------
  # Plain text
  # ---------------------------------------------------------------------

  # Leaf blocks join their inline children directly; containers separate
  # child blocks with newlines.
  @leaf_blocks ~w(paragraph heading codeBlock)

  defp plain_text(%{"type" => "text"} = node), do: node["text"] || ""
  defp plain_text(%{"type" => "hardBreak"}), do: "\n"

  defp plain_text(%{"type" => type, "content" => content}) when is_list(content) do
    parts = Enum.map(content, &plain_text/1)

    if type in @leaf_blocks do
      parts
    else
      Enum.map(parts, &[&1, "\n"])
    end
  end

  defp plain_text(_node), do: ""

  # ---------------------------------------------------------------------
  # Headings
  # ---------------------------------------------------------------------

  defp collect_headings(node, acc \\ [])

  defp collect_headings(%{"type" => "heading"} = node, acc) do
    attrs = node["attrs"] || %{}

    level =
      case attrs["level"] do
        l when is_integer(l) and l in 1..6 -> l
        _ -> 1
      end

    id = if is_binary(attrs["id"]), do: attrs["id"]

    text =
      node
      |> plain_text()
      |> IO.iodata_to_binary()
      |> String.trim()

    [%{level: level, id: id, text: text} | acc]
  end

  defp collect_headings(%{"content" => content}, acc) when is_list(content) do
    Enum.reduce(content, acc, &collect_headings/2)
  end

  defp collect_headings(_node, acc), do: acc

  # ---------------------------------------------------------------------
  # Normalization — accept string- or atom-keyed documents.
  # ---------------------------------------------------------------------

  defp normalize(%{} = map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(other), do: other

  defp stringify_keys(%{} = map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
