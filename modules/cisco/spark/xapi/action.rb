# frozen_string_literal: true

require 'set'

module Cisco; end
module Cisco::Spark; end
module Cisco::Spark::Xapi; end

# Pure utility methods for building Cisco xAPI actions.
module Cisco::Spark::Xapi::Action
    ACTION_TYPE ||= Set.new [
        :xConfiguration,
        :xCommand,
        :xStatus,
        :xFeedback,
        :xPreferences
    ]

    module_function

    # Serialize an xAPI action into transmittable command.
    #
    # @param type [ACTION_TYPE] the type of action to execute
    # @param command [String, Array<String>] action command path
    # @param args [Hash] an optional hash of keyword arguments for the action
    # @return [String]
    def create_action(type, command, args = {})
        unless ACTION_TYPE.include? type
            raise ArgumentError,
                  "Invalid action type. Must be one of #{ACTION_TYPE}."
        end

        args = args.map do |name, value|
            value = "\"#{value}\"" if value.is_a? String
            "#{name}: #{value}"
        end

        [type, command, args].flatten.join ' '
    end

    # Serialize an xCommand into transmittable command.
    #
    # @param command [String, Array<String>] command path
    # @param args [Hash] an optional hash of keyword arguments
    # @return [String]
    def xcommand(command, args = {})
        create_action :xCommand, command, args
    end
end
