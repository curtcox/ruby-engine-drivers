# frozen_string_literal: true

module Aca; end
module Aca::Rooms; end

module Aca::Rooms::Components; end

module Aca::Rooms::ComponentManager
    module Composer
        Hook = Struct.new :before, :during, :after

        def compose_with(component, &extensions)
            # Nested hash of { components => { method => Hook } }
            const_set :HOOKS, {} unless const_defined? :HOOKS
            hooks = const_get :HOOKS
            hooks[component] ||= Hash.new { |h, k| h[k] = Hook.new }

            # Mini-DSL for defining cross-component behaviours
            composer = Class.new do
                Hook.members.each do |position|
                    define_method position do |method, &action|
                        hooks[component][method][position] = action
                    end
                end
            end

            composer.new.instance_eval(&extensions)

            self

            # HOOKS = {
            #     Power: {
            #         powerup: ...
            #     }
            # }
            #
            # HOOKS = {
            #     powerup: [...]
            # }
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

            # Map [{ method => Hook }] to { method => [Hook] }
            hooks = hooks.reduce { |a, b| a.merge(b) { |_, x, y| [*x, *y] } }
                         .transform_values!          { |x| Array.wrap x }

            overrides = Module.new do
                hooks.each do |method, hook_list|
                    define_method method do |*args|
                        actions = [
                            [hook_list.map(&:before)],
                            [hook_list.map(&:during), -> { super }],
                            [hook_list.map(&:after)]
                        ]

                        actions.reduce do

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
