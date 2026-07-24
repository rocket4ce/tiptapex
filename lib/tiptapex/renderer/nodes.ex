defmodule Tiptapex.Renderer.Nodes do
  @moduledoc """
  Built-in node renderers for `Tiptapex.Renderer`.

  Covers every node type the Tiptapex editor produces. Output shape (tags,
  classes, data attributes) deliberately mirrors what the Tiptap JS
  extensions render client-side, so server HTML and hydrated HTML look
  identical under the shipped stylesheet.
  """

  alias Tiptapex.Renderer.{HTML, URL}

  @doc """
  Renders one node. `children` is the already-rendered iodata of its
  content. Returns `{:ok, iodata}` or `:unknown` for unhandled types.
  """
  @spec render(binary(), map(), iodata(), map()) :: {:ok, iodata()} | :unknown
  def render(type, node, children, opts)

  def render("doc", _node, children, _opts), do: {:ok, children}

  def render("paragraph", node, children, _opts) do
    {:ok, HTML.tag("p", block_attrs(node), children)}
  end

  def render("heading", node, children, opts) do
    level = heading_level(attrs(node)["level"])
    id = if Map.get(opts, :ids, true), do: safe_id(attrs(node)["id"])

    {:ok, HTML.tag("h#{level}", [{"id", id} | block_attrs(node)], children)}
  end

  def render("blockquote", _node, children, _opts) do
    {:ok, HTML.tag("blockquote", [], children)}
  end

  def render("codeBlock", node, children, _opts) do
    class =
      case attrs(node)["language"] do
        lang when is_binary(lang) ->
          if lang =~ ~r/^[A-Za-z0-9+#._-]{1,30}$/, do: "language-#{lang}"

        _ ->
          nil
      end

    {:ok, HTML.tag("pre", [], HTML.tag("code", [{"class", class}], children))}
  end

  def render("bulletList", _node, children, _opts), do: {:ok, HTML.tag("ul", [], children)}

  def render("orderedList", node, children, _opts) do
    start =
      case attrs(node)["start"] do
        n when is_integer(n) and n > 1 -> n
        _ -> nil
      end

    {:ok, HTML.tag("ol", [{"start", start}], children)}
  end

  def render("listItem", _node, children, _opts), do: {:ok, HTML.tag("li", [], children)}

  def render("taskList", _node, children, _opts) do
    {:ok, HTML.tag("ul", [{"data-type", "taskList"}], children)}
  end

  def render("taskItem", node, children, _opts) do
    checked = attrs(node)["checked"] == true

    checkbox =
      HTML.tag(
        "label",
        [],
        [
          HTML.void_tag("input", [
            {"type", "checkbox"},
            {"disabled", true},
            {"checked", checked}
          ]),
          HTML.tag("span", [], [])
        ]
      )

    {:ok,
     HTML.tag(
       "li",
       [{"data-type", "taskItem"}, {"data-checked", to_string(checked)}],
       [checkbox, HTML.tag("div", [], children)]
     )}
  end

  def render("table", _node, children, _opts) do
    {:ok, HTML.tag("table", [], HTML.tag("tbody", [], children))}
  end

  def render("tableRow", _node, children, _opts), do: {:ok, HTML.tag("tr", [], children)}

  def render("tableHeader", node, children, _opts),
    do: {:ok, HTML.tag("th", cell_attrs(node), children)}

  def render("tableCell", node, children, _opts),
    do: {:ok, HTML.tag("td", cell_attrs(node), children)}

  def render("image", node, _children, _opts) do
    a = attrs(node)

    case URL.safe_url(a["src"]) do
      {:ok, src} ->
        {width, style} =
          case URL.int_width(a["width"]) do
            {:ok, w} -> {w, "width: #{w}px; height: auto;"}
            :error -> {nil, nil}
          end

        {:ok,
         HTML.void_tag("img", [
           {"src", src},
           {"alt", string_or_nil(a["alt"])},
           {"title", string_or_nil(a["title"])},
           {"width", width},
           {"style", style}
         ])}

      :error ->
        {:ok, ""}
    end
  end

  def render("video", node, _children, _opts) do
    a = attrs(node)

    style =
      case URL.int_width(a["width"]) do
        {:ok, w} -> "width: #{w}px;"
        :error -> nil
      end

    case a["kind"] do
      "youtube" -> youtube_video(a, style)
      _ -> file_video(a, style)
    end
  end

  def render("horizontalRule", _node, _children, _opts), do: {:ok, HTML.void_tag("hr", [])}

  # A forced page break. The inline style keeps it working in bare HTML
  # (browser print, a PDF engine with no stylesheet); the class is what the
  # packaged stylesheet and `Tiptapex.Export.PDF` style.
  def render("pageBreak", _node, _children, _opts) do
    {:ok,
     HTML.tag(
       "div",
       [
         {"data-page-break", "true"},
         {"class", "ttx-page-break"},
         {"style", "break-after: page; page-break-after: always;"}
       ],
       []
     )}
  end

  def render("hardBreak", _node, _children, _opts), do: {:ok, HTML.void_tag("br", [])}

  def render(_type, _node, _children, _opts), do: :unknown

  # An iframe is emitted ONLY for a canonical embed URL rebuilt from a
  # validated YouTube video id; any other src drops the whole node.
  defp youtube_video(a, style) do
    case URL.youtube_embed(a["src"]) do
      {:ok, embed} ->
        {:ok,
         HTML.tag(
           "div",
           [
             {"data-video", "youtube"},
             {"class", "ttx-video ttx-video-youtube"},
             {"style", style}
           ],
           HTML.tag(
             "iframe",
             [
               {"src", embed},
               {"frameborder", "0"},
               {"allowfullscreen", "true"},
               {"allow",
                "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"},
               {"referrerpolicy", "strict-origin-when-cross-origin"}
             ],
             []
           )
         )}

      :error ->
        {:ok, ""}
    end
  end

  defp file_video(a, style) do
    case URL.safe_url(a["src"]) do
      {:ok, src} ->
        {:ok,
         HTML.tag(
           "div",
           [{"data-video", "file"}, {"class", "ttx-video ttx-video-file"}, {"style", style}],
           HTML.tag(
             "video",
             [
               {"src", src},
               {"controls", "true"},
               {"playsinline", "true"},
               {"title", string_or_nil(a["title"])},
               {"preload", "metadata"}
             ],
             []
           )
         )}

      :error ->
        {:ok, ""}
    end
  end

  # textAlign and lineHeight live as NODE attributes on paragraph/heading
  # (set by the TextAlign and LineHeight extensions), not as marks.
  defp block_attrs(node) do
    a = attrs(node)

    align =
      case URL.text_align(a["textAlign"]) do
        {:ok, v} -> v
        :error -> nil
      end

    line_height =
      case URL.safe_css_value(a["lineHeight"]) do
        {:ok, v} -> v
        :error -> nil
      end

    [{"style", HTML.style([{"text-align", align}, {"line-height", line_height}])}]
  end

  defp cell_attrs(node) do
    a = attrs(node)

    colwidth =
      case a["colwidth"] do
        widths when is_list(widths) ->
          if Enum.all?(widths, &is_integer/1), do: Enum.join(widths, ",")

        _ ->
          nil
      end

    [
      {"colspan", span(a["colspan"])},
      {"rowspan", span(a["rowspan"])},
      {"data-colwidth", colwidth}
    ]
  end

  defp span(n) when is_integer(n) and n > 1, do: n
  defp span(_), do: nil

  defp heading_level(level) when is_integer(level) and level in 1..6, do: level
  defp heading_level(_), do: 1

  defp safe_id(id) when is_binary(id) do
    if id =~ ~r/^[A-Za-z0-9_-]{1,64}$/, do: id
  end

  defp safe_id(_), do: nil

  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(_), do: nil

  defp attrs(%{"attrs" => %{} = attrs}), do: attrs
  defp attrs(_), do: %{}
end
