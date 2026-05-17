# frozen_string_literal: true
#
# Groups consecutive top-level author-tagged blocks within a post body
# into <div class="author-run …"> wrappers, so the gutter bar renders
# as one continuous line per run instead of breaking between blocks.
#
# A run ends at:
#   - a different author key (different class or different data-author)
#   - a block without an author class (headers and <hr> are not tagged
#     by authorship.rb, so they naturally interrupt a run)
#
# Hook order matters: this file loads after authorship.rb and figure.rb
# alphabetically, so by the time it runs, figures are already wrapped
# and figure elements have inherited the author class. The wrapper sees
# them as just another author-tagged block.

module UTMBlog
  module WrapRuns
    POST_BODY_OPEN = /<div class="post-body[^"]*"[^>]*itemprop="articleBody"[^>]*>/.freeze
    POST_BODY_END  = /<\/div>\s*<footer class="post-footer/.freeze

    module_function

    def group(html)
      return html unless html.is_a?(String)

      m_start = html.match(POST_BODY_OPEN)
      return html unless m_start
      body_start = m_start.end(0)

      m_end = html.match(POST_BODY_END, body_start)
      return html unless m_end
      body_end = m_end.begin(0)

      head = html[0...body_start]
      body = html[body_start...body_end]
      tail = html[body_end..-1]

      head + group_consecutive(body) + tail
    end

    RAW_OPEN  = /\A\s*<(pre|script|style|textarea)\b/i.freeze

    # Splits on blank lines, but keeps <pre>/<script>/<style>/<textarea>
    # blocks atomic so any blank lines inside them don't fracture the run.
    def split_blocks(body)
      lines  = body.split("\n", -1)
      blocks = []
      buf    = []
      i      = 0

      flush = lambda do
        joined = buf.join("\n")
        blocks << joined unless joined.strip.empty?
        buf = []
      end

      while i < lines.length
        line = lines[i]
        if (m = line.match(RAW_OPEN))
          flush.call
          tag    = m[1].downcase
          closer = /<\/#{Regexp.escape(tag)}\s*>/i
          raw    = [line]
          if line =~ closer
            blocks << raw.join("\n")
            i += 1
          else
            i += 1
            while i < lines.length
              raw << lines[i]
              if lines[i] =~ closer
                i += 1
                break
              end
              i += 1
            end
            blocks << raw.join("\n")
          end
        elsif line.strip.empty?
          flush.call
          i += 1
        else
          buf << line
          i += 1
        end
      end
      flush.call
      blocks
    end

    def group_consecutive(body)
      blocks = split_blocks(body)

      result      = []
      current_run = []
      current_key = nil

      blocks.each do |block|
        key = author_key(block)

        if key && key == current_key
          current_run << block
        else
          result << render_run(current_run, current_key) unless current_run.empty?
          current_run = [block]
          current_key = key
        end
      end
      result << render_run(current_run, current_key) unless current_run.empty?

      "\n" + result.join("\n\n") + "\n"
    end

    # Returns [author-class, data-author] or nil. The author class lives
    # somewhere in the outermost element's class list; data-author is its
    # sibling attribute on the same tag.
    def author_key(block)
      cls_match = block.match(/<[a-zA-Z][^>]*\bclass="[^"]*\bauthor-(human|ai)\b/m)
      return nil unless cls_match
      kind = "author-#{cls_match[1]}"

      author_match = block.match(/<[a-zA-Z][^>]*\bdata-author="([^"]*)"/m)
      return nil unless author_match
      [kind, author_match[1]]
    end

    def render_run(blocks, key)
      content = blocks.join("\n\n")
      return content if key.nil?
      kind, name = key
      %(<div class="author-run #{kind}" data-author="#{name}">\n#{content}\n</div>)
    end
  end
end

Jekyll::Hooks.register :documents, :post_render do |doc|
  next unless doc.respond_to?(:collection) && doc.collection && doc.collection.label == "posts"
  doc.output = UTMBlog::WrapRuns.group(doc.output) if doc.output
end
