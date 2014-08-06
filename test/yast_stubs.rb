
require "logger"
require "singleton"

module Yast
  module Logger
    # Just empty logger - does not log anything
    class NullLogger < ::Logger
      include Singleton
      def initialize(*args)
      end
      def add(*args, &block)
      end
    end

    def log
      NullLogger.instance
    end

    def self.included(base)
      base.extend self
    end
  end
  module I18n
    def textdomain dom
    end
  end
  def self.import(mod)
    true
  end

  # simply mock a Path as a String
  class Path < String
    def initialize(path)
      super(path)
    end
  end
end

def stub_yast_require
  # stub require "yast" only, leave the other requires
  allow_any_instance_of(Object).to receive(:require).and_call_original
  allow_any_instance_of(Object).to receive(:require).with("yast")
end
