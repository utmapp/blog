# frozen_string_literal: true
#
# Wraps top-level post tables so a table wider than the reading column
# scrolls inside its own box instead of widening the whole page (which
# on iOS lets the entire post pan sideways).
#
#   <div class="table-wrap author-…" data-author="…">
#     <div class="table-scroll"><table>…</table></div>
#   </div>
#
# Two layers are needed: the scroller must clip (overflow-x: auto), but
# the author gutter bar and hover tooltip are drawn *outside* the block
# (left: -1rem / top: -1.55em) and would be clipped too. So the author
# class and data-author are hoisted off the <table> onto the outer,
# non-clipping wrapper.
#
# Only tables that open at column 0 are touched — those are the
# top-level blocks emitted by kramdown (or raw HTML written at the top
# level). Tables nested inside custom HTML (e.g. a report card with its
# own scroller) are indented and left alone.
#
# Hook order: this file sorts before wrap_runs.rb, so the wrapper — now
# carrying the author class — is what wrap_runs sees and groups. No
# blank lines are introduced, so the wrapper stays a single block.

module UTMBlog
  module TableScroll
    TOP_LEVEL_TABLE = %r{^<table\b(?<attrs>[^>]*)>(?<body>.*?)</table>}m.freeze
    AUTHOR_CLASS    = /\Aauthor-(?:human|ai)\z/.freeze

    module_function

    def transform(html)
      return html unless html.is_a?(String)
      html.gsub(TOP_LEVEL_TABLE) { wrap($~) }
    end

    def wrap(m)
      attrs = m[:attrs].to_s

      classes     = attrs[/\bclass="([^"]*)"/, 1].to_s.split
      author      = classes.find { |c| c.match?(AUTHOR_CLASS) }
      data_author = attrs[/\bdata-author="([^"]*)"/, 1]

      # Strip the author markers from the table itself.
      table_classes = classes.reject { |c| c.match?(AUTHOR_CLASS) }
      table_attrs   = attrs.sub(/\s*\bdata-author="[^"]*"/, "")
      table_attrs   = if table_classes.empty?
                        table_attrs.sub(/\s*\bclass="[^"]*"/, "")
                      else
                        table_attrs.sub(/\bclass="[^"]*"/, %(class="#{table_classes.join(" ")}"))
                      end

      wrap_classes = ["table-wrap", author].compact.join(" ")
      wrap_data    = data_author ? %( data-author="#{data_author}") : ""

      %(<div class="#{wrap_classes}"#{wrap_data}><div class="table-scroll">) +
        %(<table#{table_attrs}>#{m[:body]}</table></div></div>)
    end
  end
end

Jekyll::Hooks.register :documents, :post_render do |doc|
  next unless doc.respond_to?(:collection) && doc.collection && doc.collection.label == "posts"
  doc.output = UTMBlog::TableScroll.transform(doc.output) if doc.output
end
