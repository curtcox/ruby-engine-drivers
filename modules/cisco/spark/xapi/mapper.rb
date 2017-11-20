# frozen_string_literal: true

module Cisco; end
module Cisco::Spark; end
module Cisco::Spark::Xapi; end

# Minimal DSL for mapping Cisco's xAPI to methods.
module Cisco::Spark::Xapi::Mapper
    module ApiMapperMethods
        # Bind an xCommand to a module method.
        #
        # This abuses ruby's ordered hashes and fat arrow hash to provide a
        # neat, declarative syntax for building out Room OS device modules.
        #
        # Example:
        #   command 'Fake n Command' => :my_method,
        #           ParamA: [:enum, :of, :options],
        #           ParamB: String,
        #           _OptionalParam: Integer
        #
        # Will provide the method:
        #   def my_method(index, param_a, param_b, optional_param = nil)
        #       ...
        #   end
        #
        # @param mapping [Hash]
        #  - first k/v pair is a mapping from the xCommand => method_name
        #  - use 'n' within command path elements containing an index element
        #    (as per the device protocol guide), this will be lifted into an
        #    'index' parameter
        #  - all other pairs are ParamName: <type>
        #  - prefix optional params with an underscore
        # @return [Symbol] the mapped method name
        def command(mapping)
            command_path, method_name = mapping.shift

            raise ArgumentError, 'mapped command must be a String' \
                unless command_path.is_a? String

            raise ArgumentError, 'method name must be a Symbol' \
                unless method_name.is_a? Symbol

            params = mapping.keys.map { |name| name.to_s.underscore }
            opt_, req = params.partition { |name| name.starts_with? '_' }
            opt = opt_.map { |name| "#{name[1..-1]} = nil" }
            param_str = (req + opt).join ', '

            # TODO: add support for index commands
            command_str = command_path.split(' ').join(' ')
            # use .tap to isolate

            # TODO: add argument type checks

            class_eval <<-METHOD
                def #{method_name}(#{param_str})
                    args = binding.local_variables
                                  .map { |p|
                                      [p.to_s.camelize, binding.local_variable_get(p)]
                                  }
                                  .to_h
                                  .compact
                    do_send Xapi::Action.xcommand('#{command_str}', args)
                    logger.debug { args }
                end
            METHOD

            method_name
        end

        # Bind an xCommand to a protected method (admin execution only).
        #
        # @return [Symbol]
        # @see #command
        def command!(mapping)
            protect_method command(mapping)
        end
    end

    def self.included(klass)
        klass.extend ApiMapperMethods
    end
end
