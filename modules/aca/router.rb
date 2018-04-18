# frozen_string_literal: true

require 'algorithms'
require 'set'

module Aca; end

class Aca::Router
    include ::Orchestrator::Constants

    descriptive_name 'ACA Signal Router'
    generic_name :Router
    implements :logic
    description <<~DESC
        Signal distribution management for handling routing across multiple
        devices and complex/layered switching infrastructure.
    DESC

    def on_load
        on_update
    end

    def on_update
        logger.debug 'building graph from signal map'

        @signal_graph = SignalGraph.from_map(setting(:connections) || {})

        self[:nodes] = signal_graph.map(&:id)
        self[:inputs] = signal_graph.sinks.map(&:id)
        self[:outputs] = signal_graph.sources.map(&:id)
    end

    # Route a set of signals to arbitrary destinations.
    #
    # `map` is a hashmap of the structure `{ source: target | [targets] }`
    #
    # Multiple sources can be specified simultaneously, or if connecting a
    # single source to a single destination, Ruby's implicit hash syntax can be
    # used to let you express it neatly as `connect source => target`.
    def connect(map)
        # 1. Turn map -> list of paths (list of lists of nodes)
        # 2. Check for intersections of node lists for different sources
        #     - get unique nodes for each source
        #     - intersect lists
        #     - confirm empty
        # 3. Perform device interactions
        #     - step through paths and pair device interactions into tuples representing switch events
        #     - flatten and uniq
        #     - remove singular nodes (passthrough)
        #     - execute interactions
        # 4. Consolidate each path into a success / fail
        # 5. Raise exceptions / log errors for failures
        # 6. Return consolidated promise

        map.each_pair do |source, targets|
            Array(targets).each { |target| route source, target }
        end
    end

    protected

    def signal_graph
        @signal_graph ||= SignalGraph.new
    end

    # Given a list of nodes that form a path, execute the device level
    # interactions to switch a signal across across them.
    def switch(path)

    end

    # Find the shortest path between a source and target node and return the
    # list of nodes which form it.
    def route(source, target)

    end
end

# Graph data structure for respresentating abstract signal networks.
#
# All signal sinks and sources are represented as nodes, with directed edges
# holding connectivity information and a lambda that can be executed to
# 'activate' the edge, performing any device level interaction for signal
# switching.
#
# Directivity of the graph is inverted from the signal flow - edges use signal
# sinks as source and signal sources as their terminus so that a nodes may
# be efficiently added or removed taking all incoming signal connections with
# them.
class Aca::Router::SignalGraph
    Edge = Struct.new :source, :target, :selector do
        def activate
            selector&.call
        end
    end

    class Node
        attr_reader :id, :edges

        def initialize(id)
            @id = id.to_sym
            @edges = Set.new
        end

        def join(other, selector = nil)
            edges << Edge.new(self, other, selector)
            self
        end

        def successors
            edges.map(&:target)
        end

        def inspect
            "#{id} --> [#{successors.join ' '}]"
        end

        def to_s
            id.to_s
        end

        def eql?(other)
            id == other.id
        end

        def hash
            id.hash
        end
    end

    include Enumerable

    attr_reader :nodes

    def initialize
        @nodes = ActiveSupport::HashWithIndifferentAccess.new
    end

    def <<(id)
        nodes[id] ||= Node.new id
        self
    end

    def join(source, target, &selector)
        nodes[source].join nodes[target], selector
        self
    end

    def [](id)
        nodes[id]
    end

    def each(&block)
        nodes.values.each(&block)
    end

    def sources
        select { |node| indegree(node.id).zero? }
    end

    def sinks
        select { |node| outdegree(node.id).zero? }
    end

    def incoming_edges(id)
        reduce(Set.new) do |edges, node|
            edges | node.successors.select { |x| x.id == id }
        end
    end

    def outgoing_edges(id)
        nodes[id].edges
    end

    def indegree(id)
        incoming_edges(id).size
    end

    def outdegree(id)
        outgoing_edges(id).size
    end

    def inspect
        object_identifier = "#{self.class.name}:0x#{format('%02x', object_id)}"
        nodes = map(&:inspect).join ', '
        "#<#{object_identifier} @nodes={ #{nodes} }>"
    end

    def to_s
        "{ #{to_a.join ', '} }"
    end

    # Build a signal map from a nested hash of input connectivity.
    #
    # `map` should be of the structure
    #     { device: { input_name: source } }
    #   or
    #     { device: [source] }
    #
    # When inputs are specified as an array, 1-based indicies will be used.
    #
    # Sources which exist on matrix switchers are defined as "device__output".
    #
    # For example, a map containing two displays and 2 laptop inputs, all
    # connected via 2x2 matrix switcher would be:
    #     {
    #         Display_1: {
    #             hdmi: :Switcher_1__1
    #         },
    #         Display_2: {
    #             hdmi: :Switcher_1__2
    #         },
    #         Switcher_1: [:Laptop_1, :Laptop_2]
    #     }
    #
    def self.from_map(map)
        graph = new

        matrix_nodes = []

        to_hash = proc { |x| x.is_a?(Array) ? Hash[(1..x.size).zip x] : x }

        map.transform_values!(&to_hash).each_pair do |device, inputs|
            # Create the node for the signal sink
            graph << device

            inputs.each_pair do |input, source|
                # Create a node and edge to each input source
                graph << source
                graph.join(device, source) do
                    system[device].switch_to input
                end

                # Check is the input is a matrix switcher
                upstream_device, output = source.split '__'
                next if output.nil?

                matrix_nodes |= [upstream_device]

                # Push in nodes and edges to each matrix input
                matrix_inputs = map[upstream_device]
                matrix_inputs.each_pair do |matrix_input, upstream_source|
                    graph << upstream_source
                    graph.join(source, upstream_source) do
                        system[upstream_device].switch matrix_input => output
                    end
                end
            end
        end

        # Remove any temp 'matrix device nodes' as we now how fully connected
        # nodes for each input and output.
        graph.tap { |g| g.nodes.except!(*matrix_nodes) }
    end
end
