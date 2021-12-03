require "./migrate/*"

module Migrate
  # :nodoc:
  enum Direction
    Up
    Down
  end

  # For tagging so consumers know where errors originate from.
  class Error < Exception
  end
end
