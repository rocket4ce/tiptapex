defmodule Tiptapex.Export.PDF do
  @moduledoc """
  Print-ready HTML and PDF engine options for Tiptapex documents.

  This module never shells out and never adds a dependency: it turns a
  document plus its `Tiptapex.Page` setup into (a) a standalone HTML page
  with the right `@page` geometry and (b) the exact options the two common
  Elixir PDF engines need. You call the engine.

  ## ChromicPDF

      {source, opts} = Tiptapex.Export.PDF.chromic_pdf(article.body)
      ChromicPDF.print_to_pdf(source, opts ++ [output: "article.pdf"])

  ## pdf_generator (wkhtmltopdf)

      {html, opts} = Tiptapex.Export.PDF.pdf_generator(article.body)
      {:ok, path} = PdfGenerator.generate(html, opts)

  ## Anything else (browser print, WeasyPrint, Gotenberg…)

      html = Tiptapex.Export.PDF.to_html(article.body)

  ## Headers, footers and page numbers

  Both engines draw running headers/footers themselves, which is the only
  way to get a correct `{pages}` total and per-page numbering. The three
  slots of `Tiptapex.Page` map straight onto each engine's native feature:

  | Token      | ChromicPDF (Chrome)                | pdf_generator (wkhtmltopdf) |
  | ---------- | ---------------------------------- | --------------------------- |
  | `{page}`   | `<span class="pageNumber">`        | `[page]`                    |
  | `{pages}`  | `<span class="totalPages">`        | `[topage]`                  |
  | `{date}`   | `<span class="date">`              | `[date]`                    |
  | `{time}`   | *(not supported — pass `:tokens`)* | `[time]`                    |
  | `{title}`  | `<span class="title">`             | `[title]`                   |

  Substitute a token yourself with `:tokens` when you want a fixed value or
  a specific format:

      Tiptapex.Export.PDF.chromic_pdf(doc, tokens: %{"date" => "24/07/2026"})

  ## Logos and formatting

  A header/footer slot can carry an image (see `Tiptapex.Page`) and a small
  allow-listed HTML subset (see `Tiptapex.Renderer.Markup`) — `<b>`, `<span
  style="color: …">`, `<h1>`, `<img>` and friends. Chrome draws both straight
  from the template.

  wkhtmltopdf's text flags can do neither: they render literally. A region
  with a logo or markup therefore needs `--header-html`/`--footer-html` — use
  `with_pdf_generator/3`, which writes and cleans up those files for you.

  Chrome renders the running header with no base URL, so a relative logo src
  will not load. Pass `:asset_url` to rewrite it — most usefully into a
  `data:` URI:

      Tiptapex.Export.PDF.chromic_pdf(doc, asset_url: &MyApp.inline_asset/1)

  Because the engines own the margin boxes, `to_html/2` emits `@page
  { margin: 0 }` on the engine paths — the margins travel as engine options
  instead, so the header/footer land inside them.
  """

  require Logger

  alias Tiptapex.{Page, Renderer}
  alias Tiptapex.Renderer.Markup

  @stylesheet_path Path.expand("../../../assets/css/tiptapex.css", __DIR__)
  @external_resource @stylesheet_path
  @stylesheet File.read!(@stylesheet_path)

  # Neither `.ttx-prose` nor `.ttx-content` declares a family — in an app the
  # host's stylesheet supplies it. A standalone PDF has no host, so it would
  # otherwise render in the engine's default serif.
  @print_font_family ~s(-apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif)

  @chrome_tokens %{
    "page" => ~s(<span class="pageNumber"></span>),
    "pages" => ~s(<span class="totalPages"></span>),
    "date" => ~s(<span class="date"></span>),
    "time" => "",
    "title" => ~s(<span class="title"></span>)
  }

  @wkhtmltopdf_tokens %{
    "page" => "[page]",
    "pages" => "[topage]",
    "date" => "[date]",
    "time" => "[time]",
    "title" => "[title]"
  }

  # wkhtmltopdf's own names for the paper sizes we ship presets for.
  @wkhtmltopdf_sizes %{
    letter: "Letter",
    legal: "Legal",
    tabloid: "Tabloid",
    executive: "Executive",
    a3: "A3",
    a4: "A4",
    a5: "A5"
  }

  @doc "The stylesheet embedded in exported HTML (the package's own CSS)."
  @spec stylesheet() :: String.t()
  def stylesheet, do: @stylesheet

  @doc """
  Renders a complete, standalone HTML document ready to print.

  ## Options

    * `:page` — page setup override, as in `Tiptapex.Page.from_doc/2`.
      Defaults to whatever the document carries; pass `true` to force
      defaults onto a document with no page setup.
    * `:margins` — `:css` (default) writes the margins into the `@page`
      rule; `:none` writes `margin: 0` because the PDF engine supplies
      them. The engine helpers below use `:none`.
    * `:title` — `<title>` of the page, and the value Chrome/wkhtmltopdf
      substitute for `{title}`. Defaults to the page setup's `:title`.
    * `:lang` — `<html lang>`, default `"en"`.
    * `:stylesheet` — `:bundled` (default) inlines the package stylesheet
      so the PDF matches the editor; `:none` omits it.
    * `:css` — extra CSS appended after the stylesheet.
    * `:renderer` — options forwarded to `Tiptapex.Renderer.to_html/2`.
    * `:body_class` — extra classes on `<body>`.
  """
  @spec to_html(map() | nil, keyword()) :: String.t()
  def to_html(doc, opts \\ []) do
    page = Page.from_doc(doc, Keyword.get(opts, :page))
    title = title_for(page, opts)

    body =
      doc
      |> Renderer.to_html(Keyword.get(opts, :renderer, []))
      |> safe_to_string()

    """
    <!DOCTYPE html>
    <html lang="#{escape(Keyword.get(opts, :lang, "en"))}">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{escape(title)}</title>
    <style>
    #{bundled_css(opts)}
    #{print_css(page, opts)}
    #{Keyword.get(opts, :css, "")}
    </style>
    </head>
    <body class="#{escape(body_class(opts))}">
    <div class="ttx-prose">
    #{body}
    </div>
    </body>
    </html>
    """
  end

  @doc """
  Options for `ChromicPDF.print_to_pdf/2`, as `{source, opts}`.

      {source, opts} = Tiptapex.Export.PDF.chromic_pdf(doc)
      ChromicPDF.print_to_pdf(source, opts ++ [output: path])

  Paper size and margins become `printToPDF` parameters (in inches, the
  unit Chrome speaks) and the header/footer slots become Chrome's
  `headerTemplate`/`footerTemplate`.

  Accepts every `to_html/2` option, plus:

    * `:tokens` — token replacements applied before Chrome's own, e.g.
      `%{"date" => "24/07/2026"}`.
    * `:print_to_pdf` — a map merged over the computed parameters, for
      anything else Chrome supports (`"scale"`, `"pageRanges"`, …).
    * `:font_size` — header/footer font size in CSS units, default `"9pt"`.
    * `:asset_url` — 1-arity function rewriting logo `src` values, e.g. to
      absolutise them or inline them as `data:` URIs. Chrome cannot resolve
      relative URLs in a running header.
  """
  @spec chromic_pdf(map() | nil, keyword()) :: {{:html, String.t()}, keyword()}
  def chromic_pdf(doc, opts \\ []) do
    page = Page.from_doc(doc, Keyword.get(opts, :page)) || Page.new()
    # A CSS `@page { margin }` overrides Chrome's printToPDF margin
    # parameters rather than adding to them, so the two must carry the same
    # values — with `margin: 0` the body would print edge to edge while the
    # running header still honoured the margin box.
    html = to_html(doc, Keyword.merge(opts, page: page, margins: :css))

    %{width: width, height: height} = Page.dimensions(page)
    m = page.margins

    header = chrome_template(page, :header, opts)
    footer = chrome_template(page, :footer, opts)

    print_to_pdf =
      %{
        "paperWidth" => Page.to_inches(width),
        "paperHeight" => Page.to_inches(height),
        "marginTop" => Page.to_inches(m.top),
        "marginRight" => Page.to_inches(m.right),
        "marginBottom" => Page.to_inches(m.bottom),
        "marginLeft" => Page.to_inches(m.left),
        "printBackground" => true,
        # Chrome would otherwise ignore paperWidth/paperHeight in favour of
        # the @page rule; we already wrote the same size into both.
        "preferCSSPageSize" => false,
        "displayHeaderFooter" => header != nil or footer != nil,
        # An empty template makes Chrome fall back to its built-in
        # date/title/url furniture, which is never what you want.
        "headerTemplate" => header || "<span></span>",
        "footerTemplate" => footer || "<span></span>"
      }
      |> Map.merge(stringify_keys(Keyword.get(opts, :print_to_pdf, %{})))

    {{:html, html}, [print_to_pdf: print_to_pdf]}
  end

  @doc """
  Options for `PdfGenerator.generate/2` (wkhtmltopdf), as `{html, opts}`.

      {html, opts} = Tiptapex.Export.PDF.pdf_generator(doc)
      {:ok, path} = PdfGenerator.generate(html, opts)

  Paper size, orientation, margins and the header/footer slots all become
  wkhtmltopdf shell parameters, so page numbering is produced by the engine
  (`[page]` / `[topage]`).

  Accepts every `to_html/2` option, plus:

    * `:tokens` — token replacements applied before wkhtmltopdf's own.
    * `:font_size` — header/footer font size in points, default `9`.
    * `:header_spacing` / `:footer_spacing` — millimetres between the
      running element and the content.
    * `:header_html` / `:footer_html` — a path or URL for wkhtmltopdf's
      `--header-html` / `--footer-html`, used instead of the text flags.
      Required for a region carrying a logo — see `with_pdf_generator/3`.
    * `:shell_params` — extra parameters appended last (wkhtmltopdf lets
      later flags win, so this can override anything computed here,
      including the `--dpi 96 --disable-smart-shrinking` pair that keeps
      wkhtmltopdf on CSS reference pixels).
  """
  @spec pdf_generator(map() | nil, keyword()) :: {String.t(), keyword()}
  def pdf_generator(doc, opts \\ []) do
    page = Page.from_doc(doc, Keyword.get(opts, :page)) || Page.new()
    html = to_html(doc, Keyword.merge(opts, page: page, margins: :none))

    m = page.margins

    margin_params =
      Enum.flat_map([top: m.top, right: m.right, bottom: m.bottom, left: m.left], fn
        {side, value} -> ["--margin-#{side}", "#{round_mm(value)}mm"]
      end)

    # wkhtmltopdf lays out at 75 DPI and then "smart shrinks" the result to
    # fit, so the same CSS comes out about 25% smaller than in a browser —
    # and the PDF paginates nowhere near where the editor said it would.
    # These put it back on CSS reference pixels.
    params =
      ["--dpi", "96", "--disable-smart-shrinking"] ++
        size_params(page) ++
        orientation_params(page) ++
        margin_params ++
        running_params(page, :header, opts) ++
        running_params(page, :footer, opts) ++
        title_params(page, opts) ++
        List.wrap(Keyword.get(opts, :shell_params, []))

    {html, [page_size: wkhtmltopdf_page_size(page), shell_params: params]}
  end

  @doc """
  Runs `fun` with the `{html, opts}` `pdf_generator/2` would return, having
  first written any header/footer that carries a logo to a temporary HTML
  file (wkhtmltopdf's `--header-html` / `--footer-html`). The files are
  removed afterwards, whatever `fun` does.

      Tiptapex.Export.PDF.with_pdf_generator(doc, [], &PdfGenerator.generate/2)

  This is the path to use when headers or footers have images; without it
  wkhtmltopdf can only draw their text (see `pdf_generator/2`). Passing
  `:header_html` / `:footer_html` yourself — a path or a URL you serve —
  takes precedence and writes nothing.
  """
  @spec with_pdf_generator(map() | nil, keyword(), (String.t(), keyword() -> result)) :: result
        when result: term()
  def with_pdf_generator(doc, opts \\ [], fun) when is_function(fun, 2) do
    page = Page.from_doc(doc, Keyword.get(opts, :page)) || Page.new()
    opts = Keyword.put(opts, :page, page)

    needed =
      Enum.filter([:header, :footer], fn region ->
        region_rich?(page, region) and is_nil(Keyword.get(opts, :"#{region}_html"))
      end)

    dir = Path.join(System.tmp_dir!(), "tiptapex-pdf-#{System.unique_integer([:positive])}")

    try do
      opts =
        Enum.reduce(needed, opts, fn region, acc ->
          File.mkdir_p!(dir)
          path = Path.join(dir, "#{region}.html")
          File.write!(path, running_html(doc, region, opts))
          Keyword.put(acc, :"#{region}_html", path)
        end)

      {html, generator_opts} = pdf_generator(doc, opts)
      fun.(html, generator_opts)
    after
      File.rm_rf(dir)
    end
  end

  @doc """
  A standalone HTML document for one running region — what wkhtmltopdf's
  `--header-html` / `--footer-html` expects, and the only way to get a logo
  into a wkhtmltopdf header.

  wkhtmltopdf appends `page`, `topage`, `date` and `time` to the URL as query
  parameters; the returned document reads them back, so `{page}` and
  `{pages}` resolve per page exactly as the native flags would.

  Accepts `:page`, `:tokens`, `:font_size` and `:asset_url`.
  """
  @spec running_html(map() | nil, :header | :footer, keyword()) :: String.t()
  def running_html(doc, region, opts \\ []) when region in [:header, :footer] do
    page = Page.from_doc(doc, Keyword.get(opts, :page)) || Page.new()
    custom = custom_tokens(opts)

    # {title} has no query parameter — resolve it here. The rest become
    # placeholders the script fills in.
    tokens =
      Map.merge(
        %{
          "page" => token_span("page"),
          "pages" => token_span("topage"),
          "date" => token_span("date"),
          "time" => token_span("time"),
          "title" => escape(title_for(page, opts))
        },
        Map.new(custom, fn {key, value} -> {key, escape(value)} end)
      )

    cells =
      page
      |> Page.slots(region)
      |> Enum.map_join("", &slot_cell(&1, tokens, opts))

    """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><style>
    html, body { margin: 0; padding: 0; }
    body {
      font-family: #{@print_font_family};
      font-size: #{escape(Keyword.get(opts, :font_size, 9))}pt;
      color: #374151;
    }
    /* wkhtmltopdf already lays this out inside the page margins — repeating
       them here would indent the header twice. */
    .ttx-running { display: flex; width: 100%; box-sizing: border-box; }
    </style></head>
    <body>
    <div class="ttx-running">#{cells}</div>
    <script>
    // wkhtmltopdf passes the page counters on the query string.
    (function () {
      var q = {};
      location.search.replace(/^\\?/, "").split("&").forEach(function (pair) {
        var kv = pair.split("=");
        if (kv[0]) q[kv[0]] = decodeURIComponent(kv[1] || "");
      });
      Array.prototype.forEach.call(document.querySelectorAll("[data-ttx-token]"), function (el) {
        el.textContent = q[el.getAttribute("data-ttx-token")] || "";
      });
    })();
    </script>
    </body></html>
    """
  end

  defp token_span(name), do: ~s(<span data-ttx-token="#{name}"></span>)

  # ---------------------------------------------------------------------
  # HTML
  # ---------------------------------------------------------------------

  defp bundled_css(opts) do
    case Keyword.get(opts, :stylesheet, :bundled) do
      :none -> ""
      _ -> @stylesheet
    end
  end

  # The paged editor lays blocks out with top margins collapsed away (see
  # `.ttx-paged` in the stylesheet); mirroring that here is what keeps the
  # editor's page breaks and the PDF's in step.
  defp print_css(nil, _opts) do
    """
    html, body { margin: 0; padding: 0; background: #fff; }
    body { font-family: #{@print_font_family}; }
    .ttx-page-break { break-after: page; page-break-after: always; height: 0; }
    """
  end

  defp print_css(page, opts) do
    margin =
      case Keyword.get(opts, :margins, :css) do
        :none -> "0"
        _ -> Page.css_margin(page)
      end

    """
    @page { size: #{Page.css_size(page)}; margin: #{margin}; }
    html, body { margin: 0; padding: 0; background: #fff; }
    body {
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
      font-family: #{@print_font_family};
    }
    /* The paged editor measures with these metrics, and mirrors this margin
       model (`.ttx-paged` in the stylesheet) — matching both is what keeps
       its page breaks and the engine's in step. The `.ttx-print` prefix is
       load-bearing: `.ttx-prose > *` alone loses to the packaged
       `.ttx-prose h1`, which would leave heading margins in and push every
       page out of step. Override with :css to match your typography. */
    .ttx-print .ttx-prose { font-size: 0.95rem; line-height: 1.65; }
    .ttx-print .ttx-prose > * { margin-top: 0; }
    .ttx-print .ttx-prose > h1,
    .ttx-print .ttx-prose > h2 { padding-top: 1.25em; }
    .ttx-print .ttx-prose > h3 { padding-top: 1em; }
    .ttx-print .ttx-prose > *:first-child { padding-top: 0; }
    .ttx-page-break { break-after: page; page-break-after: always; height: 0; }
    .ttx-prose table, .ttx-prose img, .ttx-prose pre, .ttx-prose blockquote {
      break-inside: avoid; page-break-inside: avoid;
    }
    .ttx-prose h1, .ttx-prose h2, .ttx-prose h3 {
      break-after: avoid; page-break-after: avoid;
    }
    """
  end

  defp body_class(opts) do
    ["ttx-print", Keyword.get(opts, :body_class)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp title_for(page, opts) do
    Keyword.get(opts, :title) || (page && page.title) || ""
  end

  # ---------------------------------------------------------------------
  # Chrome header/footer templates
  # ---------------------------------------------------------------------

  defp chrome_template(page, region, opts) do
    if Page.region_used?(page, region) do
      tokens = Map.merge(@chrome_tokens, custom_tokens(opts))
      font_size = Keyword.get(opts, :font_size, "9pt")

      cells =
        page
        |> Page.slots(region)
        |> Enum.map_join("", &slot_cell(&1, tokens, opts))

      m = page.margins

      ~s(<div style="display:flex;width:100%;box-sizing:border-box;margin:0;) <>
        ~s(padding:0 #{round_mm(m.right)}mm 0 #{round_mm(m.left)}mm;) <>
        ~s(font-family:ui-sans-serif,system-ui,sans-serif;font-size:#{escape(font_size)};) <>
        ~s(color:#374151;-webkit-print-color-adjust:exact;">#{cells}</div>)
    end
  end

  # One header/footer slot: an optional logo, then the tokenised text. The
  # text may carry the small HTML subset `Tiptapex.Renderer.Markup` allows —
  # sanitised and rebuilt, never passed through.
  defp slot_cell({slot, %{text: text, image: image}}, tokens, opts) do
    rendered = text |> Markup.to_html() |> IO.iodata_to_binary()

    content =
      [image_tag(image, opts), Page.replace_tokens(rendered, tokens)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    ~s(<div style="flex:1 1 0;min-width:0;display:flex;align-items:center;gap:2mm;) <>
      ~s(overflow:hidden;justify-content:#{justify_css(slot)};text-align:#{align_css(slot)};">) <>
      content <> "</div>"
  end

  defp image_tag(nil, _opts), do: nil

  defp image_tag(image, opts) do
    src = Keyword.get(opts, :asset_url, & &1).(image.src)

    ~s(<img src="#{escape(src)}" alt="#{escape(image.alt)}" ) <>
      ~s(style="height:#{round_mm(image.height)}mm;width:auto;flex:none;">)
  end

  defp align_css(:left), do: "left"
  defp align_css(:center), do: "center"
  defp align_css(:right), do: "right"

  defp justify_css(:left), do: "flex-start"
  defp justify_css(:center), do: "center"
  defp justify_css(:right), do: "flex-end"

  # ---------------------------------------------------------------------
  # wkhtmltopdf shell parameters
  # ---------------------------------------------------------------------

  defp size_params(page) do
    case page.size do
      %{} ->
        %{width: w, height: h} = Page.dimensions(page)
        ["--page-width", "#{round_mm(w)}mm", "--page-height", "#{round_mm(h)}mm"]

      _preset ->
        []
    end
  end

  defp orientation_params(%{orientation: :landscape}), do: ["--orientation", "Landscape"]
  defp orientation_params(_page), do: []

  defp running_params(page, region, opts) do
    cond do
      not Page.region_used?(page, region) ->
        []

      # wkhtmltopdf's --header-left/center/right take plain text: they cannot
      # carry an image, and markup would come out as literal angle brackets.
      # Such a region has to be a whole HTML document instead;
      # `with_pdf_generator/3` writes it for you.
      source = Keyword.get(opts, :"#{region}_html") ->
        ["--#{region}-html", to_string(source)] ++ spacing_params(region, opts)

      region_rich?(page, region) ->
        Logger.warning(
          "[Tiptapex] the #{region} has an image or markup, which wkhtmltopdf cannot draw " <>
            "from --#{region}-left/center/right. Only its plain text is exported. Use " <>
            "Tiptapex.Export.PDF.with_pdf_generator/3, or pass #{region}_html: <path or URL>."
        )

        text_params(page, region, opts)

      true ->
        text_params(page, region, opts)
    end
  end

  defp text_params(page, region, opts) do
    tokens = Map.merge(@wkhtmltopdf_tokens, custom_tokens(opts))
    prefix = "--#{region}"

    slots =
      page
      |> Page.slots(region)
      |> Enum.map(fn {slot, %{text: text}} -> {slot, plain_text(text)} end)
      |> Enum.reject(fn {_slot, text} -> text == "" end)
      |> Enum.flat_map(fn {slot, text} ->
        ["#{prefix}-#{align_css(slot)}", Page.replace_tokens(text, tokens)]
      end)

    slots ++
      ["#{prefix}-font-size", to_string(Keyword.get(opts, :font_size, 9))] ++
      spacing_params(region, opts)
  end

  # wkhtmltopdf's text flags render literally, so markup is reduced to the
  # text it wraps rather than shown as angle brackets.
  defp plain_text(text) do
    if Markup.markup?(text) do
      text
      |> String.replace(~r/<[^<>]*>/, "")
      |> String.trim()
    else
      text
    end
  end

  defp spacing_params(region, opts) do
    case Keyword.get(opts, :"#{region}_spacing") do
      value when is_number(value) -> ["--#{region}-spacing", to_string(round_mm(value))]
      _ -> []
    end
  end

  # True when the region needs a real HTML document rather than text flags.
  defp region_rich?(page, region) do
    page
    |> Page.slots(region)
    |> Enum.any?(fn {_slot, slot} -> slot.image != nil or Markup.markup?(slot.text) end)
  end

  defp title_params(page, opts) do
    case title_for(page, opts) do
      "" -> []
      title -> ["--title", title]
    end
  end

  defp wkhtmltopdf_page_size(page) do
    case page.size do
      %{} -> "A4"
      preset -> Map.get(@wkhtmltopdf_sizes, preset, "A4")
    end
  end

  # ---------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------

  defp custom_tokens(opts) do
    opts
    |> Keyword.get(:tokens, %{})
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp round_mm(value) do
    rounded = Float.round(value * 1.0, 3)
    if rounded == Float.round(rounded), do: trunc(rounded), else: rounded
  end

  defp escape(value) do
    {:safe, io} = Phoenix.HTML.html_escape(to_string(value))
    IO.iodata_to_binary(io)
  end

  defp safe_to_string({:safe, io}), do: IO.iodata_to_binary(io)

  defp stringify_keys(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
