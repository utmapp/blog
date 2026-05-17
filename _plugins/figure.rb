# frozen_string_literal: true
#
# Wraps "image + italic caption" pairs in <figure>/<figcaption> so they
# render as a single semantic block instead of an image followed by a
# stray italic paragraph. No syntax change needed — keep writing:
#
#   ![alt](src)
#   *Caption*
#
# or with a click-through link to the full image:
#
#   [![alt](src)](src){:target="_blank"}
#   *Caption*
#
# Both forms — image+em rendered as one paragraph (no blank line in
# source) or two adjacent paragraphs (blank line in source) — are picked
# up. Any author class / data-author on the source paragraph is hoisted
# onto the figure so attribution stays correct.

module UTMBlog
  module Figures
    LINKED_IMG_SRC = '(?:<a\b[^>]*>\s*)?<img\b[^>]*/?>(?:\s*</a>)?'

    TWO_PARAGRAPH = %r{
      <p\b(?<p_attrs>[^>]*)>\s*
      (?<picture>#{LINKED_IMG_SRC})\s*
      </p>
      \s*
      <p\b[^>]*>\s*<em>(?<caption>.+?)</em>\s*</p>
    }mx.freeze

    SINGLE_PARAGRAPH = %r{
      <p\b(?<p_attrs>[^>]*)>\s*
      (?<picture>#{LINKED_IMG_SRC})\s*
      (?:<br\s*/?>\s*)?
      <em>(?<caption>.+?)</em>\s*
      </p>
    }mx.freeze

    module_function

    def transform(html)
      return html unless html.is_a?(String)
      # Match the two-paragraph form first; otherwise the single-paragraph
      # regex could swallow the trailing </p><p>… boundary unexpectedly.
      html = html.gsub(TWO_PARAGRAPH)    { wrap_match($~) }
      html = html.gsub(SINGLE_PARAGRAPH) { wrap_match($~) }
      html
    end

    def wrap_match(m)
      attrs   = m[:p_attrs].to_s
      picture = m[:picture].strip
      caption = m[:caption].strip

      author_class = attrs[/\bclass="([^"]*)"/, 1].to_s.split.find { |c| c.start_with?("author-") }
      data_author  = attrs[/\bdata-author="([^"]*)"/, 1]

      classes = author_class ? "figure #{author_class}" : "figure"
      data    = data_author ? %( data-author="#{data_author}") : ""

      %(<figure class="#{classes}"#{data}>\n  #{picture}\n  <figcaption>#{caption}</figcaption>\n</figure>)
    end
  end
end

Jekyll::Hooks.register :documents, :post_render do |doc|
  next unless doc.respond_to?(:collection) && doc.collection && doc.collection.label == "posts"
  doc.output = UTMBlog::Figures.transform(doc.output) if doc.output
end
