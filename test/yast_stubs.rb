
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
end

def stub_yast_require
  # stub require "yast" only, leave the other requires
  Object.any_instance.stub(:require).and_call_original
  Object.any_instance.stub(:require).with("yast")
end
