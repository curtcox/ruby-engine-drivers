# frozen_string_literal: true

module Aca; end
module Aca::Rooms; end

module Aca::Rooms::Components; end

module Aca::Rooms::ComponentManager
    module Composer
        Hook = Struct.new :method, :position, :action

        def compose_with(component, &extensions)
            # Hash of { component => [Hook] }
            const_set :HOOKS, {} unless const_defined? :HOOKS
            hooks = const_get(:HOOKS)[component] = []

            # Mini-DSL for defining cross-component behaviours
            composer = Class.new do
                [:before, :during, :after].each do |position|
                    define_method position do |method, &action|
                        hooks << Hook.new(method, position, action)
                    end
                end
            end

            composer.new.instance_eval(&extensions)

            self
        end
    end

    module Mixin
        def components(*components)
            modules = components.map do |component|
                fqn = "::Aca::Rooms::Components::#{component}"
                ::Orchestrator::DependencyManager.load fqn, :logic
            end

            # Include the component methods
            include(*modules)

            # Get all cross-component behaviours for the loaded components
            hooks = modules.select   { |mod| mod.singleton_class < Composer }
                           .flat_map { |mod| mod::HOOKS.values_at(*components) }
                           .compact
                           .flatten

            # Map from [Hook] to { method => { position => [action] } }
            hooks = hooks.each_with_object({}) do |hook, h|
                ((h[hook.method] ||= {})[hook.position] ||= []) << hook.action
            end

            overrides = Module.new do
                hooks.each do |method, actions|
                    define_method method do |*args|
                        result = nil

                        sequence = [
                            actions[:before],
                            [
                                proc { result = super(*args) },
                                *actions[:during]
                            ],
                            actions[:after]
                        ].compact!

                        sequence.reduce(thread.finally) do |prev, succ|
                            prev.then do
                                thread.all(succ.map { |x| instance_exec(*args, &x) })
                            end
                        end.then do
                            result
                        end
                    end
                end
            end

            prepend overrides
        end
    end

    module_function

    def included(other)
        other.extend Mixin
    end
end
