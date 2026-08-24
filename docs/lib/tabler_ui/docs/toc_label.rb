# frozen_string_literal: true

module TablerUi
  module Docs
    # Shortens a Demo or Section title for the Contents column
    # (docs/app/views/tabler_ui/docs/components/show.html.erb) only --
    # display-layer helper, not part of the demo DSL. Demo titles are
    # written as full descriptive one-liners for the demo card heading
    # (docs/app/views/tabler_ui/docs/demos/_demo.html.erb) and are often a
    # full sentence; reused verbatim as a nav label they make that column
    # hard to scan. Most titles are already short and pass through
    # unchanged; a long one is cut at its first natural break instead of
    # requiring a second, shorter title to be authored per demo.
    module TocLabel
      MAX_LENGTH = 60
      TRUNCATE_LENGTH = 57
      TRAILING_PARENTHETICAL = /\A(.+?)\s+\(.*\)\z/.freeze

      class << self
        # @param text [String] a Demo#title or ParsedComponent::Section#title
        # @return [String] `text` unchanged if it's already MAX_LENGTH
        #   characters or fewer (or blank). Otherwise, the text before its
        #   first natural break -- a trailing " (...)" explanation, else
        #   " -- ", else ", ", in that order -- and if that candidate is
        #   still too long, hard-truncated to TRUNCATE_LENGTH characters
        #   with "..." appended so the result is never longer than
        #   MAX_LENGTH characters.
        def shorten(text)
          return text if text.blank? || text.length <= MAX_LENGTH

          candidate = shorten_candidate(text)
          return candidate if candidate.length <= MAX_LENGTH

          "#{candidate[0, TRUNCATE_LENGTH]}..."
        end

        private

        # @param text [String] known non-blank and over MAX_LENGTH already
        # @return [String] the first applicable candidate; may still be
        #   over MAX_LENGTH -- #shorten truncates it if so
        def shorten_candidate(text)
          if (match = TRAILING_PARENTHETICAL.match(text))
            match[1]
          elsif text.include?(" -- ")
            text.split(" -- ", 2).first
          elsif text.include?(", ")
            text.split(", ", 2).first
          else
            text
          end
        end
      end
    end
  end
end
