defmodule Tiptapex.Export.PDFTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tiptapex.Export.PDF
  alias Tiptapex.Page

  @doc_json %{
    "type" => "doc",
    "attrs" => %{
      "page" => %{
        "size" => "legal",
        "margins" => %{"top" => 20, "right" => 15, "bottom" => 20, "left" => 15},
        "header" => %{"left" => "Acme S.A.", "center" => "", "right" => "{date}"},
        "numbering" => %{
          "enabled" => true,
          "region" => "footer",
          "align" => "center",
          "format" => "Page {page} of {pages}"
        },
        "title" => "Quarterly report"
      }
    },
    "content" => [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 1},
        "content" => [%{"type" => "text", "text" => "Hello"}]
      },
      %{"type" => "pageBreak"},
      %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Second page"}]}
    ]
  }

  @plain %{
    "type" => "doc",
    "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Plain"}]}]
  }

  describe "to_html/2" do
    test "emits a standalone document with the paper geometry" do
      html = PDF.to_html(@doc_json)

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "@page { size: 215.9mm 355.6mm; margin: 20mm 15mm 20mm 15mm; }"
      assert html =~ "<title>Quarterly report</title>"
      assert html =~ ~s(<div class="ttx-prose">)
      assert html =~ "<h1"
      assert html =~ "Hello"
    end

    test "renders forced page breaks as CSS breaks" do
      html = PDF.to_html(@doc_json)

      assert html =~ ~s(class="ttx-page-break")
      assert html =~ "break-after: page"
      assert html =~ ".ttx-page-break { break-after: page; page-break-after: always; height: 0; }"
    end

    test "mirrors the paged editor's margin model so both break in the same places" do
      assert PDF.to_html(@doc_json) =~ ".ttx-prose > * { margin-top: 0; }"
    end

    test "a document with no page setup still renders, without an @page rule" do
      html = PDF.to_html(@plain)

      refute html =~ "@page"
      assert html =~ "Plain"
    end

    test ":page true forces defaults onto an unpaginated document" do
      assert PDF.to_html(@plain, page: true) =~ "@page { size: 215.9mm 279.4mm;"
    end

    test ":margins :none leaves the margins to the PDF engine" do
      assert PDF.to_html(@doc_json, margins: :none) =~
               "@page { size: 215.9mm 355.6mm; margin: 0; }"
    end

    test "inlines the package stylesheet by default, and can be told not to" do
      assert PDF.to_html(@doc_json) =~ ".ttx-prose"
      refute PDF.to_html(@doc_json, stylesheet: :none) =~ "--ttx-primary"
    end

    test "appends :css and escapes the title" do
      html = PDF.to_html(@plain, css: ".x { color: red }", title: ~s(a "b" <c>))

      assert html =~ ".x { color: red }"
      assert html =~ "<title>a &quot;b&quot; &lt;c&gt;</title>"
    end

    test "forwards renderer options" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "heading",
            "attrs" => %{"level" => 2, "id" => "intro"},
            "content" => [%{"type" => "text", "text" => "Intro"}]
          }
        ]
      }

      assert PDF.to_html(doc) =~ ~s(id="intro")
      refute PDF.to_html(doc, renderer: [ids: false]) =~ ~s(id="intro")
    end

    test "escapes document text — the exporter is not a raw/1 in disguise" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "<script>x</script>"}]
          }
        ]
      }

      html = PDF.to_html(doc)
      refute html =~ "<script>x</script>"
      assert html =~ "&lt;script&gt;"
    end
  end

  describe "chromic_pdf/2" do
    test "returns an {:html, _} source and printToPDF parameters in inches" do
      {{:html, html}, opts} = PDF.chromic_pdf(@doc_json)
      params = opts[:print_to_pdf]

      assert html =~ "Hello"
      assert params["paperWidth"] == 8.5
      assert params["paperHeight"] == 14.0
      assert_in_delta params["marginTop"], 0.787402, 0.00001
      assert_in_delta params["marginLeft"], 0.590551, 0.00001
      assert params["preferCSSPageSize"] == false
    end

    test "the CSS and printToPDF margins agree" do
      # Chrome lets a CSS @page margin override the printToPDF parameters
      # rather than adding to them; if the two disagree the body prints to
      # one geometry and the running header to another.
      {{:html, html}, opts} = PDF.chromic_pdf(@doc_json)

      assert html =~ "@page { size: 215.9mm 355.6mm; margin: 20mm 15mm 20mm 15mm; }"
      assert_in_delta opts[:print_to_pdf]["marginTop"], 20 / 25.4, 0.00001
      assert_in_delta opts[:print_to_pdf]["marginLeft"], 15 / 25.4, 0.00001
    end

    test "the print CSS outranks the packaged stylesheet's heading margins" do
      # `.ttx-prose > *` alone loses to `.ttx-prose h1` on specificity, which
      # would leave heading top margins in and desync the PDF from the
      # paged editor.
      html = PDF.to_html(@doc_json)

      assert html =~ ".ttx-print .ttx-prose > * { margin-top: 0; }"
      assert html =~ ".ttx-print .ttx-prose > h1,"
    end

    test "translates the slots into Chrome's header/footer templates" do
      {_source, opts} = PDF.chromic_pdf(@doc_json)
      params = opts[:print_to_pdf]

      assert params["displayHeaderFooter"] == true
      assert params["headerTemplate"] =~ "Acme S.A."
      assert params["headerTemplate"] =~ ~s(<span class="date"></span>)
      assert params["headerTemplate"] =~ "text-align:left"
      assert params["footerTemplate"] =~ ~s(<span class="pageNumber"></span>)
      assert params["footerTemplate"] =~ ~s(<span class="totalPages"></span>)
      assert params["footerTemplate"] =~ "text-align:center"
    end

    test "an unused region gets a non-empty template — an empty one makes Chrome improvise" do
      {_source, opts} = PDF.chromic_pdf(@plain, page: %{header: %{center: "Only a header"}})
      params = opts[:print_to_pdf]

      assert params["headerTemplate"] =~ "Only a header"
      assert params["footerTemplate"] == "<span></span>"
    end

    test "no header and no footer means no header/footer furniture at all" do
      {_source, opts} = PDF.chromic_pdf(@plain, page: true)
      assert opts[:print_to_pdf]["displayHeaderFooter"] == false
    end

    test "escapes slot text before it reaches the template" do
      injection = "<img src=x onerror=alert(1)>"
      {_source, opts} = PDF.chromic_pdf(@plain, page: %{footer: %{left: injection}})
      template = opts[:print_to_pdf]["footerTemplate"]

      refute template =~ "<img"
      assert template =~ "&lt;img"
    end

    test ":tokens override the engine's native substitution" do
      {_source, opts} =
        PDF.chromic_pdf(@plain,
          page: %{footer: %{center: "{date} {page}"}},
          tokens: %{"date" => "24/07/2026"}
        )

      template = opts[:print_to_pdf]["footerTemplate"]
      assert template =~ "24/07/2026"
      refute template =~ ~s(<span class="date">)
      assert template =~ ~s(<span class="pageNumber"></span>)
    end

    test ":print_to_pdf is merged over the computed parameters" do
      {_source, opts} =
        PDF.chromic_pdf(@doc_json, print_to_pdf: %{"scale" => 0.8, "paperWidth" => 5})

      params = opts[:print_to_pdf]

      assert params["scale"] == 0.8
      assert params["paperWidth"] == 5
    end

    test "landscape swaps the paper, it does not set Chrome's landscape flag" do
      {_source, opts} = PDF.chromic_pdf(@plain, page: %{size: :letter, orientation: :landscape})
      params = opts[:print_to_pdf]

      assert params["paperWidth"] == 11.0
      assert params["paperHeight"] == 8.5
      refute Map.has_key?(params, "landscape")
    end
  end

  describe "pdf_generator/2" do
    test "maps the paper preset and margins onto wkhtmltopdf flags" do
      {html, opts} = PDF.pdf_generator(@doc_json)

      assert html =~ "Hello"
      assert opts[:page_size] == "Legal"
      assert params_pair(opts[:shell_params], "--margin-top") == "20mm"
      assert params_pair(opts[:shell_params], "--margin-left") == "15mm"
    end

    test "translates the slots into wkhtmltopdf's own tokens" do
      {_html, opts} = PDF.pdf_generator(@doc_json)
      params = opts[:shell_params]

      assert params_pair(params, "--header-left") == "Acme S.A."
      assert params_pair(params, "--header-right") == "[date]"
      assert params_pair(params, "--footer-center") == "Page [page] of [topage]"
      assert params_pair(params, "--footer-font-size") == "9"
      assert params_pair(params, "--title") == "Quarterly report"
    end

    test "skips empty slots rather than passing blank arguments" do
      {_html, opts} = PDF.pdf_generator(@doc_json)
      refute "--header-center" in opts[:shell_params]
      refute "--footer-left" in opts[:shell_params]
    end

    test "a custom paper size becomes explicit width/height flags" do
      {_html, opts} = PDF.pdf_generator(@plain, page: %{size: %{width: 200, height: 250}})

      assert params_pair(opts[:shell_params], "--page-width") == "200mm"
      assert params_pair(opts[:shell_params], "--page-height") == "250mm"
    end

    test "puts wkhtmltopdf on CSS reference pixels" do
      # Without these it lays out at 75 DPI and smart-shrinks the result, so
      # the PDF comes out ~25% smaller than the editor measured.
      {_html, opts} = PDF.pdf_generator(@plain, page: true)

      assert params_pair(opts[:shell_params], "--dpi") == "96"
      assert "--disable-smart-shrinking" in opts[:shell_params]
    end

    test "landscape is passed to the engine" do
      {_html, opts} = PDF.pdf_generator(@plain, page: %{orientation: :landscape})
      assert params_pair(opts[:shell_params], "--orientation") == "Landscape"
    end

    test ":shell_params are appended last so they can override" do
      {_html, opts} = PDF.pdf_generator(@doc_json, shell_params: ["--margin-top", "0mm"])
      assert List.last(opts[:shell_params]) == "0mm"
    end

    test "spacing options are optional" do
      {_html, without} = PDF.pdf_generator(@doc_json)
      {_html, with_spacing} = PDF.pdf_generator(@doc_json, header_spacing: 5)

      refute "--header-spacing" in without[:shell_params]
      assert params_pair(with_spacing[:shell_params], "--header-spacing") == "5"
    end
  end

  describe "logos in headers and footers" do
    @logo %{src: "https://cdn.example.com/logo.png", height: 12, alt: "Acme"}

    test "Chrome draws the image straight from the template" do
      {_source, opts} =
        PDF.chromic_pdf(@plain, page: %{header: %{left: %{text: "Acme", image: @logo}}})

      template = opts[:print_to_pdf]["headerTemplate"]

      assert template =~ ~s(<img src="https://cdn.example.com/logo.png")
      assert template =~ ~s(alt="Acme")
      assert template =~ "height:12mm"
      assert template =~ "Acme", "the text still renders next to the logo"
      assert opts[:print_to_pdf]["displayHeaderFooter"] == true
    end

    test ":asset_url rewrites the src — how a relative logo reaches Chrome" do
      {_source, opts} =
        PDF.chromic_pdf(@plain,
          page: %{header: %{left: %{image: %{src: "/uploads/logo.png"}}}},
          asset_url: fn src -> "https://example.com" <> src end
        )

      assert opts[:print_to_pdf]["headerTemplate"] =~
               ~s(<img src="https://example.com/uploads/logo.png")
    end

    test "a logo src is escaped on the way into the template" do
      src = "/logo.png\" onerror=\"alert(1)"
      {_source, opts} = PDF.chromic_pdf(@plain, page: %{header: %{left: %{image: %{src: src}}}})
      template = opts[:print_to_pdf]["headerTemplate"]

      refute template =~ ~s(onerror="alert)
      assert template =~ "&quot;"
    end

    test "wkhtmltopdf keeps the text but warns that it cannot draw the logo" do
      log =
        capture_log(fn ->
          {_html, opts} =
            PDF.pdf_generator(@plain, page: %{header: %{left: %{text: "Acme", image: @logo}}})

          assert params_pair(opts[:shell_params], "--header-left") == "Acme"
          refute "--header-html" in opts[:shell_params]
        end)

      assert log =~ "wkhtmltopdf cannot draw"
      assert log =~ "with_pdf_generator/3"
    end

    test ":header_html takes over from the text flags" do
      {_html, opts} =
        PDF.pdf_generator(@plain,
          page: %{header: %{left: %{text: "Acme", image: @logo}}},
          header_html: "/tmp/hdr.html"
        )

      assert params_pair(opts[:shell_params], "--header-html") == "/tmp/hdr.html"
      refute "--header-left" in opts[:shell_params]
    end

    test "running_html/3 is a standalone document that resolves the counters" do
      html =
        PDF.running_html(@plain, :footer,
          page: %{
            footer: %{left: %{image: @logo}, center: "{page} / {pages}", right: "{title}"},
            title: "Report"
          }
        )

      assert html =~ "<!DOCTYPE html>"
      assert html =~ ~s(<img src="https://cdn.example.com/logo.png")
      assert html =~ ~s(<span data-ttx-token="page"></span>)
      assert html =~ ~s(<span data-ttx-token="topage"></span>)
      assert html =~ "Report", "{title} has no query parameter, so it is resolved here"
      assert html =~ "location.search"
    end

    test "with_pdf_generator/3 writes the running files, then removes them" do
      page = %{header: %{left: %{image: @logo}}, footer: %{center: "{page}"}}

      {path, seen} =
        PDF.with_pdf_generator(@plain, [page: page], fn html, opts ->
          assert html =~ "Plain"
          header = params_pair(opts[:shell_params], "--header-html")

          assert header != nil, "the header became an HTML file"
          assert File.exists?(header)
          assert File.read!(header) =~ ~s(<img src="https://cdn.example.com/logo.png")

          # The footer has no image, so it stays on the cheap text flags.
          assert params_pair(opts[:shell_params], "--footer-center") == "[page]"
          refute "--footer-html" in opts[:shell_params]

          {header, :ok}
        end)

      assert seen == :ok
      refute File.exists?(path), "the temporary file is cleaned up"
      refute File.exists?(Path.dirname(path))
    end

    test "with_pdf_generator/3 cleans up even when the engine raises" do
      page = %{header: %{left: %{image: @logo}}}
      parent = self()

      assert_raise RuntimeError, "boom", fn ->
        PDF.with_pdf_generator(@plain, [page: page], fn _html, opts ->
          send(parent, {:dir, Path.dirname(params_pair(opts[:shell_params], "--header-html"))})
          raise "boom"
        end)
      end

      assert_receive {:dir, dir}
      refute File.exists?(dir)
    end

    test "with_pdf_generator/3 writes nothing when no region has a logo" do
      PDF.with_pdf_generator(@doc_json, [], fn _html, opts ->
        refute "--header-html" in opts[:shell_params]
        assert params_pair(opts[:shell_params], "--header-left") == "Acme S.A."
      end)
    end
  end

  describe "markup in headers and footers" do
    test "Chrome gets the allow-listed subset, rebuilt" do
      {_source, opts} =
        PDF.chromic_pdf(@plain, page: %{header: %{left: "<h1>hola</h1>", center: "<b>x</b>"}})

      template = opts[:print_to_pdf]["headerTemplate"]

      assert template =~ "<h1>hola</h1>"
      assert template =~ "<b>x</b>"
    end

    test "anything outside the subset is escaped, not emitted" do
      {_source, opts} =
        PDF.chromic_pdf(@plain, page: %{footer: %{left: "<script>alert(1)</script>"}})

      template = opts[:print_to_pdf]["footerTemplate"]

      refute template =~ "<script>"
      assert template =~ "&lt;script&gt;"
    end

    test "markup and tokens coexist" do
      {_source, opts} = PDF.chromic_pdf(@plain, page: %{footer: %{center: "<b>{page}</b>"}})

      assert opts[:print_to_pdf]["footerTemplate"] =~
               ~s(<b><span class="pageNumber"></span></b>)
    end

    test "wkhtmltopdf's text flags get the tags stripped, with a warning" do
      log =
        capture_log(fn ->
          {_html, opts} = PDF.pdf_generator(@plain, page: %{header: %{left: "<b>Acme</b>"}})

          assert params_pair(opts[:shell_params], "--header-left") == "Acme",
                 "the flag renders literally, so the tags must not reach it"
        end)

      assert log =~ "image or markup"
    end

    test "with_pdf_generator/3 routes a markup-only region through --header-html" do
      PDF.with_pdf_generator(@plain, [page: %{header: %{left: "<h1>hola</h1>"}}], fn _html,
                                                                                     opts ->
        path = params_pair(opts[:shell_params], "--header-html")

        assert path != nil
        assert File.read!(path) =~ "<h1>hola</h1>"
      end)
    end

    test "a slot with neither markup nor a logo still uses the cheap text flags" do
      PDF.with_pdf_generator(@plain, [page: %{header: %{left: "Acme"}}], fn _html, opts ->
        refute "--header-html" in opts[:shell_params]
        assert params_pair(opts[:shell_params], "--header-left") == "Acme"
      end)
    end
  end

  test "stylesheet/0 exposes the embedded CSS" do
    assert PDF.stylesheet() =~ ".ttx-prose"
  end

  test "the exported page setup survives a full round trip" do
    page = Page.from_doc(@doc_json)
    assert page.size == :legal
    assert PDF.to_html(@doc_json) =~ Page.css_size(page)
  end

  defp params_pair(params, flag) do
    case Enum.find_index(params, &(&1 == flag)) do
      nil -> nil
      index -> Enum.at(params, index + 1)
    end
  end
end
