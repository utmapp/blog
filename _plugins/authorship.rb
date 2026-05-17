# frozen_string_literal: true
#
# Per-paragraph authorship tagging for the UTM blog.
#
# Splits a post's source into top-level blocks (separated by blank lines,
# with fenced code blocks held intact) and tags each one:
#
#   - Blocks that start with an HTML opening tag  →  author-ai
#   - Everything else (i.e. real markdown)        →  author-human
#
# The tag is applied via a kramdown IAL appended after the block, so the
# rendered element carries `class="author-…"` and `data-author="…"`. The
# stylesheet uses the class for the gutter bar and the data-author for the
# hover tooltip.
#
# Front matter on the post supplies the names:
#
#   ---
#   human: osy
#   ai: claude-opus-4-7
#   ---
#
# Either side can be omitted; blocks on a side without an author are left
# untouched. Posts that declare neither key are passed through unchanged.
#
# Overrides:
#   The default heuristic covers "AI writes HTML, human writes markdown",
#   but either side can be inverted by setting the class explicitly. The
#   plugin notices an existing `author-human` / `author-ai` class and:
#     - skips applying its own default
#     - still injects `data-author` from the matching front-matter name
#
# So a human-authored HTML block looks like:
#
#   <p class="author-human">A human wrote this in HTML.</p>
#
# And an AI-authored markdown block uses a kramdown IAL:
#
#   A paragraph the AI drafted in markdown.
#   {:.author-ai}

module UTMBlog
  module Authorship
    HTML_OPEN_TAG    = /\A\s*<(?!!--)[a-zA-Z]/.freeze
    HTML_OPEN_FULL   = /\A(\s*<[a-zA-Z][a-zA-Z0-9]*)([^>]*?)(\/?>)/m.freeze
    FENCE            = /\A(\s*)(```|~~~)/.freeze
    RAW_BLOCK_OPEN   = /\A\s*<(pre|script|style|textarea)\b/i.freeze
    RAW_BLOCK_CLOSE  = ->(tag) { /<\/#{Regexp.escape(tag)}\s*>/i }
    TRAILING_IAL     = /\A\s*\{:[^}]*\}\s*\z/.freeze
    AUTHOR_CLASS_RE  = /\bauthor-(human|ai)\b/.freeze
    HTML_HEADER_RE   = /\A\s*<h[1-6]\b/i.freeze
    ATX_HEADER_RE    = /\A\s*[#]{1,6}\s+\S/.freeze
    SETEXT_RULE_RE   = /\A\s*(=+|-+)\s*\z/.freeze
    HTML_HR_RE       = /\A\s*<hr\b/i.freeze
    MD_HR_RE         = /\A\s*(?:[-_*]\s*){3,}\s*\z/.freeze

    module_function

    def transform(content, human:, ai:)
      return content unless human || ai

      split_into_blocks(content)
        .map { |block| tag_block(block, human: human, ai: ai) }
        .join("\n\n")
    end

    # Splits markdown source into top-level blocks. Fenced code blocks are
    # kept atomic so their contents are never inspected as HTML.
    def split_into_blocks(content)
      lines  = content.split("\n", -1)
      blocks = []
      buf    = []
      i      = 0

      flush = lambda do
        next if buf.empty?
        blocks << buf.join("\n")
        buf = []
      end

      while i < lines.length
        line = lines[i]

        if (m = line.match(FENCE))
          flush.call
          indent, fence = m[1], m[2]
          fenced = [line]
          i += 1
          while i < lines.length
            fenced << lines[i]
            if lines[i] =~ /\A#{Regexp.escape(indent)}#{Regexp.escape(fence)}\s*\z/
              i += 1
              break
            end
            i += 1
          end
          blocks << fenced.join("\n")
        elsif (m = line.match(RAW_BLOCK_OPEN))
          flush.call
          tag    = m[1].downcase
          closer = RAW_BLOCK_CLOSE.call(tag)
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

    def tag_block(block, human:, ai:)
      return block if block.strip.empty?
      return block if html_noise?(block) # comments / doctype / processing instructions
      return block if header_block?(block) # h1–h6 are never attributed
      return block if hr_block?(block)     # <hr> breaks runs, never attributed

      override = explicit_author_class(block)

      if override
        # The block already declares which side wrote it. Don't apply the
        # default class; just fill in data-author from front matter.
        name = override == "author-ai" ? ai : human
        return block unless name
        inject_data_author(block, name)
      elsif html_element?(block)
        ai ? append_ial(block, klass: "author-ai", author: ai) : block
      else
        human ? append_ial(block, klass: "author-human", author: human) : block
      end
    end

    def html_element?(block)
      block.lstrip.match?(HTML_OPEN_TAG)
    end

    def html_noise?(block)
      s = block.lstrip
      s.start_with?("<!--", "<!", "<?")
    end

    # Matches markdown ATX (`## Heading`), setext (`Heading\n=====`), and
    # raw HTML heading blocks (`<h1>` … `<h6>`).
    def header_block?(block)
      return true if block.lstrip =~ HTML_HEADER_RE
      return true if block.lstrip =~ ATX_HEADER_RE
      lines = block.split("\n").reject { |l| l.strip.empty? }
      lines.length >= 2 && lines.last =~ SETEXT_RULE_RE
    end

    # Matches `<hr>` and markdown thematic breaks (`---`, `***`, `___`).
    # Used so horizontal rules naturally interrupt an author run.
    def hr_block?(block)
      return true if block.lstrip =~ HTML_HR_RE
      single_line = block.strip
      single_line.lines.count == 1 && single_line =~ MD_HR_RE
    end

    # Returns "author-human" / "author-ai" if the block already declares
    # one explicitly (in its outer HTML class attribute or its trailing
    # kramdown IAL); nil otherwise.
    def explicit_author_class(block)
      if html_element?(block)
        return nil unless block =~ HTML_OPEN_FULL
        attrs = Regexp.last_match(2)
        cls   = attrs[/\bclass\s*=\s*["']([^"']*)["']/, 1].to_s
        cls.split.find { |c| c == "author-human" || c == "author-ai" }
      else
        lines = block.split("\n", -1)
        return nil unless lines.last && lines.last.match?(TRAILING_IAL)
        ial = lines.last.strip[2..-2].to_s
        m   = ial.match(/\.(author-(?:human|ai))\b/)
        m && m[1]
      end
    end

    # Adds `data-author` to an already-attributed block without touching its
    # existing class. Works on both the outer HTML tag and the trailing IAL.
    def inject_data_author(block, author)
      author_attr = author.to_s.gsub('"', "&quot;")

      if html_element?(block)
        return block if block =~ /\A\s*<[a-zA-Z][a-zA-Z0-9]*[^>]*\bdata-author\s*=/
        return block unless block =~ HTML_OPEN_FULL
        prefix, attrs, close = Regexp.last_match[1..3]
        consumed = Regexp.last_match(0).length
        rest     = block[consumed..-1] || ""
        "#{prefix}#{attrs} data-author=\"#{author_attr}\"#{close}#{rest}"
      else
        lines = block.split("\n", -1)
        ial   = lines.last.strip
        return block if ial =~ /\bdata-author\s*=/
        inner = ial[2..-2].to_s.strip
        lines[-1] = "{:#{inner} data-author=\"#{author_attr}\"}"
        lines.join("\n")
      end
    end

    # Append (or merge into) a kramdown block IAL on a trailing line.
    # Kramdown attaches the IAL to the preceding block-level element,
    # including raw HTML blocks.
    def append_ial(block, klass:, author:)
      author_attr = author.to_s.gsub('"', "&quot;")
      lines       = block.split("\n", -1)

      if lines.last && lines.last.match?(TRAILING_IAL)
        existing = lines.last.strip[2..-2].to_s.strip
        lines[-1] = "{:.#{klass} data-author=\"#{author_attr}\" #{existing}}"
        lines.join("\n")
      else
        "#{block}\n{:.#{klass} data-author=\"#{author_attr}\"}"
      end
    end
  end
end

Jekyll::Hooks.register :documents, :pre_render do |doc|
  next unless doc.respond_to?(:collection) && doc.collection && doc.collection.label == "posts"

  human = doc.data["human"]
  ai    = doc.data["ai"]
  next unless human || ai

  doc.content = UTMBlog::Authorship.transform(doc.content, human: human, ai: ai)
end
