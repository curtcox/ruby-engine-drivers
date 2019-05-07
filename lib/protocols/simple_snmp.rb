# encoding: UTF-8
# frozen_string_literal: true

require 'netsnmp'

module Protocols; end

# A simple proxy object for netsnmp
# See https://github.com/swisscom/ruby-netsnmp
class Protocols::SimpleSnmp
    def initialize(driver)
        @driver = driver
    end

    def send(payload)
        @driver.send(payload).value
    end
end
