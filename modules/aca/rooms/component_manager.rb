# frozen_string_literal: true

module Aca; end
module Aca::Rooms; end

module Aca::Rooms::Components; end

module Aca::Rooms::ComponentManager
    module Composer
        # Mini-DSL for defining cross-component behaviours.
        #
        # With the block provided `before`, `during`, or `after` can be used
        # to insert additional behaviour to methods that should only exist when
        # both components are in use. The result of the original method will
        # be preserved, but will be deferred until the completion of any
        # composite behaviours.
        def compose_with(component, &extensions)
            overlay = overlay_module_for component

            hooks = {}

            # Eval the block to populate hooks with the overlay actions as
            # method => { position => [actions] }
            composer = Class.new do
                [:before, :during, :after].each do |position|
                    define_method position do |method, &action|
                        ((hooks[method] ||= {})[position] ||= []) << action
                    end
                end
            end

            composer.new.instance_eval(&extensions)

            # Build the overlay Module for prepending
            hooks.each do |method, actions|
                # FIXME: this removes visibility of original args
                overlay.send :define_method, method do |*args|
                    result = nil

                    sequence = [
                        actions[:before],
                        [
                            proc { |*x| result = super(*x) },
                            *actions[:during]
                        ],
                        actions[:after]
                    ].compact!

                    exec_actions = sequence.reduce(thread.finally) do |a, b|
                        a.then do
                            thread.all(b.map { |x| instance_exec(*args, &x) })
                        end
                    end

                    exec_actions.then { result }
                end
            end

            self
        end

        private

        # Build out a module heirachy so that <base>::Compositions::<other>
        # exists and can be used to house any behaviour extensions to be
        # applied when both components are in use.
        def overlay_module_for(component)
            [:Compositions, component].reduce(self) do |context, name|
                if context.const_defined? name, false
                    context.const_get name
                else
                    context.const_set name, Module.new
                end
            end
        end
    end

    module Mixin
        def components(*components)
            # Load the associated module
            modules = components.map do |component|
                fqn = "::Aca::Rooms::Components::#{component}"
                ::Orchestrator::DependencyManager.load fqn, :logic
            end

            # Include the component
            include(*modules)

            # Compose cross-component behaviours
            overlays = modules.flat_map do |base|
                next unless base.const_defined? :Compositions, false

                components.each_with_object([]) do |component, compositions|
                    next unless base::Compositions.const_defined? component
                    compositions << base::Compositions.const_get(component)
                end
            end
            prepend(*overlays.compact)
        end
    end

    module_function

    def included(other)
        other.extend Mixin
    end
end
