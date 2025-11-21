module Migrate
  # For tagging so consumers know where errors originate from.
  class Error < Exception
  end

  # :nodoc:
  enum Direction
    Up
    Down
  end
end

require "./migrate/*"
require "./migrate/adapters/*"
