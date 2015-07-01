require 'cert/version'
require 'cert/dependency_checker'
require 'cert/developer_center'
require 'cert/cert_runner'
require 'cert/cert_checker'
require 'cert/signing_request'
require 'cert/keychain_importer'

require 'fastlane_core'

module Cert
  # Use this to just setup the configuration attribute and set it later somewhere else
  class << self
    attr_accessor :config
  end

  Helper = FastlaneCore::Helper # you gotta love Ruby: Helper.* should use the Helper class contained in FastlaneCore

  ENV['FASTLANE_TEAM_ID'] ||= ENV["CERT_TEAM_ID"]

  DependencyChecker.check_dependencies
end
