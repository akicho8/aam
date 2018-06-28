require "active_record"
require "active_support/core_ext/string/filters"
require "table_format"

module Aam
  SCHEMA_HEADER = "# == Schema Information =="

  mattr_accessor :logger
  self.logger = ActiveSupport::Logger.new(STDOUT)
end

require "aam/version"
require "aam/schema_info_generator"
require "aam/annotation"
require "aam/railtie" if defined? Rails::Railtie
