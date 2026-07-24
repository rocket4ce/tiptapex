defmodule Tiptapex.Renderer.Markup do
  @moduledoc """
  A small allow-listed HTML subset, for the one place the document's own
  JSON→HTML pipeline does not reach: header and footer slots, which are typed
  as text rather than edited as a Tiptap document.

      iex> Tiptapex.Renderer.Markup.to_html("<b>Acme</b> S.A.") |> IO.iodata_to_binary()
      "<b>Acme</b> S.A."

  It follows the same rule as the rest of `Tiptapex.Renderer`: **nothing from
  the input is ever emitted verbatim.** The string is tokenised, each tag is
  matched against a closed allow-list, and the output is rebuilt with
  `Tiptapex.Renderer.HTML`. Anything unrecognised — an unknown tag, a
  malformed one, a stray attribute — becomes escaped text, so the worst a
  mis-parse can do is show the user their own markup:

      iex> Tiptapex.Renderer.Markup.to_html("<script>alert(1)</script>") |> IO.iodata_to_binary()
      "&lt;script&gt;alert(1)&lt;/script&gt;"

  ## What is allowed

    * inline — `b`, `strong`, `i`, `em`, `u`, `s`, `small`, `sub`, `sup`,
      `span`, `a`, `br`, `img`
    * block — `p`, `div`, `h1`…`h6`

  Attributes: `style` (each declaration's property must be in the allow-list
  and its value must pass `Tiptapex.Renderer.URL.safe_css_value/1`), `href`
  on `a`, `src`/`alt`/`width`/`height` on `img`, and `title`. Everything else
  is dropped.

  Unclosed tags are closed at the end; a closing tag that doesn't match the
  innermost open one is dropped.
  """

  alias Tiptapex.Renderer.{HTML, URL}

  @inline ~w(b strong i em u s small sub sup span a br img)
  @block ~w(p div h1 h2 h3 h4 h5 h6)
  @void ~w(br img)
  @allowed @inline ++ @block

  @style_properties ~w(
    color background-color font-size font-weight font-style font-family
    text-decoration text-transform letter-spacing line-height opacity
    vertical-align padding margin
  )

  # A tag is only a tag if it matches exactly this shape: a known-safe name
  # and double-quoted attribute values containing no angle brackets. Anything
  # else falls through to text.
  @tag ~r/^<(\/?)([a-zA-Z][a-zA-Z0-9]{0,9})((?:\s+[a-zA-Z-]{1,20}\s*=\s*"[^"<>]*")*)\s*(\/?)>$/
  @attribute ~r/([a-zA-Z-]{1,20})\s*=\s*"([^"<>]*)"/

  @doc """
  Renders the allow-listed subset of `text` as escaped, rebuilt iodata.

  Non-binaries render as `""`.
  """
  @spec to_html(term()) :: iodata()
  def to_html(text) when is_binary(text), do: text |> tokenize() |> walk([], "")
  def to_html(_), do: ""

  @doc """
  True when `text` contains at least one tag this module would render.

  Callers use it to decide whether a plain-text channel is enough —
  wkhtmltopdf's `--header-left` takes text, not markup, so a slot with
  markup has to go through `--header-html` instead.

      iex> Tiptapex.Renderer.Markup.markup?("Page {page}")
      false
      iex> Tiptapex.Renderer.Markup.markup?("Page <b>{page}</b>")
      true
  """
  @spec markup?(term()) :: boolean()
  def markup?(text) when is_binary(text) do
    text
    |> tokenize()
    |> Enum.any?(fn token ->
      case classify(token) do
        {:text, _} -> false
        _ -> true
      end
    end)
  end

  def markup?(_), do: false

  @doc "The tag names this module renders."
  @spec allowed_tags() :: [binary()]
  def allowed_tags, do: @allowed

  # ---------------------------------------------------------------------
  # Tokenizing and walking
  # ---------------------------------------------------------------------

  defp tokenize(text) do
    Regex.split(~r/(<[^<>]*>)/, text, include_captures: true, trim: true)
  end

  # `stack` holds the open elements, innermost first, each carrying the
  # iodata accumulated *before* it opened.
  defp walk([], [], acc), do: acc

  defp walk([], [{tag, attrs, parent} | stack], acc) do
    walk([], stack, [parent, HTML.tag(tag, attrs, acc)])
  end

  defp walk([token | rest], stack, acc) do
    case classify(token) do
      {:text, text} ->
        walk(rest, stack, [acc, HTML.escape(text)])

      {:void, tag, attrs} ->
        walk(rest, stack, [acc, HTML.void_tag(tag, attrs)])

      {:open, tag, attrs} ->
        walk(rest, [{tag, attrs, acc} | stack], "")

      {:close, tag} ->
        case stack do
          [{^tag, attrs, parent} | stack] ->
            walk(rest, stack, [parent, HTML.tag(tag, attrs, acc)])

          # A closer for something that isn't open (or is not the innermost
          # element) is simply dropped.
          _ ->
            walk(rest, stack, acc)
        end
    end
  end

  defp classify("<" <> _ = token) do
    with [_, closing, name, raw_attrs, self_closing] <- Regex.run(@tag, token),
         tag = String.downcase(name),
         true <- tag in @allowed do
      cond do
        closing == "/" -> {:close, tag}
        tag in @void or self_closing == "/" -> {:void, tag, attributes(tag, raw_attrs)}
        true -> {:open, tag, attributes(tag, raw_attrs)}
      end
    else
      _ -> {:text, token}
    end
  end

  defp classify(text), do: {:text, text}

  # ---------------------------------------------------------------------
  # Attributes
  # ---------------------------------------------------------------------

  defp attributes(tag, raw) do
    @attribute
    |> Regex.scan(raw)
    |> Enum.flat_map(fn [_, name, value] -> attribute(tag, String.downcase(name), value) end)
  end

  defp attribute(_tag, "style", value) do
    case safe_style(value) do
      nil -> []
      style -> [{"style", style}]
    end
  end

  defp attribute(_tag, "title", value), do: [{"title", value}]

  defp attribute("a", "href", value) do
    case URL.safe_url(value) do
      {:ok, href} -> [{"href", href}, {"rel", "noopener nofollow"}]
      :error -> []
    end
  end

  defp attribute("img", "src", value) do
    case URL.safe_image_url(value) do
      {:ok, src} -> [{"src", src}]
      :error -> []
    end
  end

  defp attribute("img", "alt", value), do: [{"alt", value}]

  defp attribute("img", dimension, value) when dimension in ["width", "height"] do
    case URL.int_width(value) do
      {:ok, pixels} -> [{dimension, pixels}]
      :error -> []
    end
  end

  defp attribute(_tag, _name, _value), do: []

  # Declarations are validated one at a time and rebuilt; the value grammar
  # admits no quotes, braces, `url(` or `;`, so nothing can escape the
  # attribute.
  defp safe_style(value) do
    value
    |> String.split(";")
    |> Enum.flat_map(fn declaration ->
      case String.split(declaration, ":", parts: 2) do
        [property, css_value] ->
          property = property |> String.trim() |> String.downcase()

          with true <- property in @style_properties,
               {:ok, css_value} <- URL.safe_css_value(String.trim(css_value)) do
            [{property, css_value}]
          else
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> HTML.style()
  end
end
