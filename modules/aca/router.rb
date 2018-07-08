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


    default_settings(
        # Nested hash of signal connectivity. See SignalGraph.from_map.
        connections: {}
    )


    # ------------------------------
    # Callbacks

    def on_load
        on_update
    end

    def on_update
        connections = setting :connections

        logger.warn 'no connections defined' unless connections

        load_from_map(connections || {})
    end


    # ------------------------------
    # Public API

    # Route a set of signals to arbitrary destinations.
    #
    # `signal_map`  is a hash of the structure `{ source: sink | [sinks] }`
    # 'atomic'      may be used to throw an exception, prior to any device
    #               interaction taking place if any of the routes are not
    #               possible
    # `force`       control if switch events should be forced, even when the
    #               associated device module is already reporting it's on the
    #               correct input
    #
    # Multiple sources can be specified simultaneously, or if connecting a
    # single source to a single destination, Ruby's implicit hash syntax can be
    # used to let you express it neatly as `connect source => sink`.
    def connect(signal_map, atomic: false, force: false)
        edges = map_to_edges signal_map, strict: atomic

        edge_list = edges.values.reduce(&:|)

        edge_list.select! { |e| needs_activation? e, ignore_status: force }

        edge_list, unroutable = edge_list.partition { |e| can_activate? e }
        raise 'can not perform all routes' if unroutable.any? && atomic

        interactions = edge_list.map { |e| activate e }

        thread.finally(interactions).then do |results|
            failed = edge_list.zip(results).reject { |_, (_, success)| success }

            edges_with_errors = unroutable
            failed.each do |edge, (error, _)|
                logger.warn "could not switch #{edge}: #{error}"
                edges_with_errors << edge
            end

            if edges_with_errors.empty?
                logger.debug 'all routes activated successfully'
                signal_map
            elsif atomic
                thread.reject 'failed to activate all routes'
            else
                signal_map.select do |source, _|
                    (edges[source] & edges_with_errors).empty?
                end
            end
        end
    end

    # Lookup the input on a sink node that would be used to connect a specific
    # source to it.
    #
    # `on` may be ommited if the source node has only one neighbour (e.g. is
    # an input node) and you wish to query the phsycial input associated with
    # it. Similarly `on` maybe used to look up the input used by any other node
    # within the graph that would be used to show `source`.
    def input_for(source, on: nil)
        sink = on || upstream(source)
        _, edges = route source, sink
        edges.last.input
    end

    # Get the node immediately upstream of an input node.
    #
    # Depending on the device API, this may be of use for determining signal
    # presence.
    def upstream(source, sink = nil)
        if sink.nil?
            edges = signal_graph.incoming_edges source
            raise "no outputs from #{source}" if edges.empty?
            raise "multiple outputs from #{source}, please specify a sink" \
                if edges.size > 1
        else
            _, edges = route source, sink
        end

        edges.first.source
    end

    # Get the node immediately downstream of an output node.
    #
    # This may be used walking back up the signal graph to find a decoder for
    # an output device.
    def downstream(sink, source = nil)
        if source.nil?
            edges = signal_graph.outgoing_edges sink
            raise "no inputs to #{sink}" if edges.empty?
            raise "multiple inputs to #{sink}, please specify a source" \
                if edges.size > 1
        else
            _, edges = route source, sink
        end

        edges.last.target
    end


    # ------------------------------
    # Internals

    protected

    def signal_graph
        @signal_graph ||= SignalGraph.new
    end

    def paths
        @path_cache ||= HashWithIndifferentAccess.new do |hash, node|
            hash[node] = signal_graph.dijkstra node
        end
    end

    def load_from_map(connections)
        logger.debug 'building graph from signal map'

        @path_cache = nil
        @signal_graph = SignalGraph.from_map(connections).freeze

        # TODO: track active signal source at each node and expose as a hash
        self[:nodes] = signal_graph.map(&:id)
        self[:inputs] = signal_graph.sinks.map(&:id)
        self[:outputs] = signal_graph.sources.map(&:id)
    end

    # Find the shortest path between between two nodes and return a list of the
    # nodes which this passes through and their connecting edges.
    def route(source, sink)
        path = paths[sink]

        distance = path.distance_to[source]
        raise "no route from #{source} to #{sink}" if distance.infinite?

        logger.debug do
            "found route connecting #{source} to #{sink} in #{distance} hops"
        end

        nodes = []
        edges = []
        node = signal_graph[source]
        until node.nil?
            nodes.unshift node
            predecessor = path.predecessor[node.id]
            edges << predecessor.edges[node.id] unless predecessor.nil?
            node = predecessor
        end

        logger.debug { edges.map(&:to_s).join ' then ' }

        [nodes, edges]
    end

    # Find the optimum combined paths required to route a single source to
    # multiple sink devices.
    def route_many(source, sinks, strict: false)
        node_exists = proc do |id|
            signal_graph.include?(id).tap do |exists|
                unless exists
                    message = "#{id} does not exist"
                    raise ArgumentError, message if strict
                    logger.warn message
                end
            end
        end

        nodes = Set.new
        edges = Set.new

        if node_exists[source]
            Array(sinks).select(&node_exists).each do |sink|
                n, e = route source, sink
                nodes |= n
                edges |= e
            end
        end

        [nodes, edges]
    end

    # Given a signal map, convert it to a hash still keyed on source id's, but
    # containing the edges within the graph to be utilised.
    def map_to_edges(signal_map, strict: false)
        nodes = {}
        edges = {}

        signal_map.each_pair do |source, sinks|
            n, e = route_many source, sinks, strict: strict
            nodes[source] = n
            edges[source] = e
        end

        conflicts = nodes.size > 1 ? nodes.values.reduce(&:&) : Set.new
        unless conflicts.empty?
            sources = nodes.reject { |(_, n)| (n & conflicts).empty? }.keys
            message = "routes for #{sources.join ', '} intersect"
            raise message if strict
            logger.warn message
        end

        edges
    end

    def needs_activation?(edge, ignore_status: false)
        mod = system[edge.device]

        fail_with = proc do |reason|
            logger.info "module for #{edge.device} #{reason} - skipping #{edge}"
            return false
        end

        single_source = signal_graph.outdegree(edge.source) == 1

        fail_with['does not exist, but appears to be an alias'] \
            if mod.nil? && single_source

        fail_with['already on correct input'] \
            if edge.nx1? && mod[:input] == edge.input && !ignore_status

        fail_with['has an incompatible api, but only a single input defined'] \
            if edge.nx1? && !mod.respond_to?(:switch_to) && single_source

        true
    end

    def can_activate?(edge)
        mod = system[edge.device]

        fail_with = proc do |reason|
            logger.warn "mod #{edge.device} #{reason} - can not switch #{edge}"
            return false
        end

        fail_with['does not exist'] if mod.nil?

        fail_with['offline'] if mod[:connected] == false

        fail_with['has an incompatible api (missing #switch_to)'] \
            if edge.nx1? && !mod.respond_to?(:switch_to)

        fail_with['has an incompatible api (missing #switch)'] \
            if edge.nxn? && !mod.respond_to?(:switch)

        true
    end

    def activate(edge)
        mod = system[edge.device]

        if edge.nx1?
            mod.switch_to edge.input
        elsif edge.nxn?
            mod.switch edge.input => edge.output
        else
            raise 'unexpected edge type'
        end
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

    class Edge
        attr_reader :source, :target, :device, :input, :output

        Meta = Struct.new(:device, :input, :output)

        def initialize(source, target, &blk)
            @source = source
            @target = target

            meta = Meta.new.tap(&blk)
            normalise_io = lambda do |x|
                if x.is_a? String
                    x[/^\d+$/]&.to_i || x.to_sym
                else
                    x
                end
            end
            @device = meta.device&.to_sym
            @input  = normalise_io[meta.input]
            @output = normalise_io[meta.output]
        end

        def to_s
            "#{target} to #{device} (in #{input})"
        end

        # Check if the edge is a switchable input on a single output device
        def nx1?
            output.nil?
        end

        # Check if the edge a matrix switcher / multi-output device
        def nxn?
            !nx1?
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
        @nodes = HashWithIndifferentAccess.new do |_, id|
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
        nodes.delete(id) { raise ArgumentError, "\"#{id}\" does not exist" }
        each { |node| node.edges.delete id } if check_incoming_edges
        self
    end

    def join(source, target, &block)
        datum = Edge.new(source, target, &block)
        nodes[source].join target, datum
        self
    end

    def each(&block)
        nodes.values.each(&block)
    end

    def include?(id)
        nodes.key? id
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
        each_with_object([]) do |node, edges|
            edges << node.edges[id] if node.edges.key? id
        end
    end

    def outgoing_edges(id)
        nodes[id].edges.values
    end

    def indegree(id)
        incoming_edges(id).size
    end

    def outdegree(id)
        outgoing_edges(id).size
    end

    def dijkstra(id)
        active = Containers::PriorityQueue.new { |x, y| (x <=> y) == -1 }
        distance_to = HashWithIndifferentAccess.new { 1.0 / 0.0 }
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

    # Pre-parse a connection map into a normalised nested hash structure
    # suitable for parsing into the graph.
    #
    # This assumes the input map has been parsed from JSON so takes care of
    # mapping keys back to integers (where suitable) and expanding sources
    # specified as an array into a nested Hash. The target normalised output is
    #
    #     { device: { input: source } }
    #
    def self.normalise(map)
        map.with_indifferent_access.transform_values! do |inputs|
            case inputs
            when Array
                (1..inputs.size).zip(inputs).to_h
            when Hash
                inputs.transform_keys do |key|
                    key.to_s[/^\d+$/]&.to_i || key
                end
            else
                raise ArgumentError, 'inputs must be a Hash or Array'
            end
        end
    end

    # Extract module references from a connection map.
    #
    # This is a destructive operation that will tranform outputs specified as
    # `device as output` to simply `output` and return a Hash of the structure
    # `{ output: device }`.
    def self.extract_mods!(map)
        mods = HashWithIndifferentAccess.new

        map.transform_keys! do |key|
            mod, node = key.to_s.split ' as '
            node ||= mod
            mods[node] = mod.to_sym
            node
        end

        mods
    end

    # Build a signal map from a nested hash of input connectivity. The input
    # map should be of the structure
    #
    #     { device: { input_name: source } }
    #   or
    #     { device: [source] }
    #
    # When inputs are specified as an array, 1-based indices will be used.
    #
    # Sources that refer to the output of a matrix switcher are defined as
    # "device__output" (using two underscores to seperate the output
    # name/number and device).
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
    #         Switcher_1: [:Laptop_1, :Laptop_2],
    #     }
    #
    # Device keys should relate to module id's for control. These may also be
    # aliased by defining them as as "mod as device". This can be used to
    # provide better readability (e.g. "Display_1 as Left_LCD") or to segment
    # them so that only specific routes are allowed. This approach enables
    # devices such as centralised matrix switchers split into multiple virtual
    # switchers that only have access to a subset of the inputs.
    def self.from_map(map)
        graph = new

        matrix_nodes = []

        connections = normalise map

        mods = extract_mods! connections

        connections.each_pair do |device, inputs|
            # Create the node for the signal sink
            graph << device

            inputs.each_pair do |input, source|
                # Create a node and edge to each input source
                graph << source
                graph.join(device, source) do |edge|
                    edge.device = mods[device]
                    edge.input  = input
                end

                # Check is the input is a matrix switcher or multi-output
                # device (such as a USB switch).
                upstream_device, output = source.to_s.split '__'
                next if output.nil?

                matrix_nodes |= [upstream_device]

                # Push in nodes and edges to each matrix input
                matrix_inputs = connections[upstream_device]
                matrix_inputs.each_pair do |matrix_input, upstream_source|
                    graph << upstream_source
                    graph.join(source, upstream_source) do |edge|
                        edge.device = mods[upstream_device]
                        edge.input  = matrix_input
                        edge.output = output
                    end
                end
            end
        end

        # Remove any temp 'matrix device nodes' as we now how fully connected
        # nodes for each input and output.
        matrix_nodes.each { |id| graph.delete id, check_incoming_edges: false }

        graph
    end
end
