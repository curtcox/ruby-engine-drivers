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

        @path_cache = nil

        @signal_graph = SignalGraph.from_map(setting(:connections) || {}).freeze

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

    def paths
        @path_cache ||= Hash.new do |hash, node|
            hash[node] = signal_graph.dijkstra node
        end
    end

    # Find the shortest path between between two nodes and return a list of the
    # nodes which this passes through and their connecting edges.
    def route(source, sink)
        path = paths[sink]

        distance = path.distance_to[source]
        raise "no route from #{source} to #{sink}" if distance.infinite?

        logger.debug do
            "found route from #{source} to #{sink} in #{distance} hops"
        end

        nodes = []
        edges = []
        node = signal_graph[source]
        until node.nil?
            nodes << node
            predecessor = path.predecessor[node.id]
            edges << predecessor.edges[node.id] unless predecessor.nil?
            node = predecessor
        end

        logger.debug { nodes.join ' ---> ' }

        [nodes, edges]
    end
end

# Graph data structure for respresentating abstract signal networks.
#
# All signal sinks and sources are represented as nodes, with directed edges
# holding connectivity information needed to execute device level interaction
# to 'activate' the edge.
#
# Directivity of the graph is inverted from the signal flow - edges use signal
# sinks as source and signal sources as their terminus. This optimises for
# cheap removal of signal sinks and better path finding (as most environments
# will have a small number of displays and a large number of sources).
class Aca::Router::SignalGraph
    Paths = Struct.new :distance_to, :predecessor

    Edge = Struct.new :source, :target, :device, :input, :output do
        def activate
            if output.nil?
                system[device].switch_to input
            else
                system[device].switch input => output
            end
        end
    end

    class Node
        attr_reader :id, :edges

        def initialize(id)
            @id = id.to_sym
            @edges = HashWithIndifferentAccess.new do |_, other_id|
                raise ArgumentError, "No edge from \"#{id}\" to \"#{other_id}\""
            end
        end

        def join(other_id, datum)
            edges[other_id] = datum
            self
        end

        def to_s
            id.to_s
        end

        def eql?(other)
            id == other
        end

        def hash
            id.hash
        end
    end

    include Enumerable

    attr_reader :nodes

    def initialize
        @nodes = ActiveSupport::HashWithIndifferentAccess.new do |_, id|
            raise ArgumentError, "\"#{id}\" does not exist"
        end
    end

    def [](id)
        nodes[id]
    end

    def insert(id)
        nodes[id] = Node.new id unless nodes.key? id
        self
    end

    alias << insert

    # If there is *certainty* the node has no incoming edges (i.e. it was a temp
    # node used during graph construction), `check_incoming_edges` can be set
    # to false to keep this O(1) rather than O(n). Using this flag at any other
    # time will result a corrupt structure.
    def delete(id, check_incoming_edges: true)
        nodes.except! id

        each { |node| node.edges.delete id } if check_incoming_edges

        self
    end

    def join(source, target, &block)
        datum = Edge.new(source, target).tap(&block)
        nodes[source].join target, datum
        self
    end

    def each(&block)
        nodes.values.each(&block)
    end

    def successors(id)
        nodes[id].edges.keys.map { |x| nodes[x] }
    end

    def sources
        select { |node| indegree(node.id).zero? }
    end

    def sinks
        select { |node| outdegree(node.id).zero? }
    end

    def incoming_edges(id)
        reduce(HashWithIndifferentAccess.new) do |edges, node|
            edges.tap { |e| e[node.id] = node.edges[id] if node.edges.key? id }
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

    def dijkstra(id)
        active = Containers::PriorityQueue.new { |x, y| (x <=> y) == -1 }
        distance_to = Hash.new { 1.0 / 0.0 }
        predecessor = {}

        distance_to[id] = 0
        active.push nodes[id], distance_to[id]

        until active.empty?
            u = active.pop
            successors(u.id).each do |v|
                alt = distance_to[u.id] + 1
                next unless alt < distance_to[v.id]
                distance_to[v.id] = alt
                predecessor[v.id] = u
                active.push v, distance_to[v.id]
            end
        end

        Paths.new distance_to, predecessor
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
                graph.join(device, source) do |edge|
                    edge.device = device
                    edge.input = input
                end

                # Check is the input is a matrix switcher or multi-output
                # device (such as a USB switch).
                upstream_device, output = source.split '__'
                next if output.nil?

                matrix_nodes |= [upstream_device]

                # Push in nodes and edges to each matrix input
                matrix_inputs = map[upstream_device]
                matrix_inputs.each_pair do |matrix_input, upstream_source|
                    graph << upstream_source
                    graph.join(source, upstream_source) do |edge|
                        edge.device = upstream_device
                        edge.input = matrix_input
                        edge.output = output
                    end
                end
            end
        end

        # Remove any temp 'matrix device nodes' as we now how fully connected
        # nodes for each input and output.
        matrix_nodes.reduce(graph) do |g, node|
            g.delete node, check_incoming_edges: false
        end
    end
end
