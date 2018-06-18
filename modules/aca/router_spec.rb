# frozen_string_literal: true

Orchestrator::Testing.mock_device 'Aca::Router' do
    def section(message)
        puts "\n\n#{'-' * 80}"
        puts message
        puts "\n"
    end

    # -------------------------------------------------------------------------
    section 'Internal graph tests'

    graph = Aca::Router::SignalGraph.new

    # Node insertion
    graph << :test_node
    expect(graph).to include(:test_node)

    # Node access
    expect(graph[:test_node]).to be_a(Aca::Router::SignalGraph::Node)
    expect { graph[:does_not_exist] }.to raise_error(ArgumentError)

    # Node deletion
    graph.delete :test_node
    expect(graph).not_to include(:test_node)

    # Edge creation
    graph << :display
    graph << :laptop
    graph.join(:display, :laptop) do |edge|
        edge.device = :Display_1
        edge.input  = :hdmi
    end
    expect(graph.successors(:display)).to include(graph[:laptop])

    # Graph structural inspection
    # note: signal flow is inverted from graph directivity
    expect(graph.indegree(:display)).to be(0)
    expect(graph.indegree(:laptop)).to be(1)
    expect(graph.outdegree(:display)).to be(1)
    expect(graph.outdegree(:laptop)).to be(0)
    expect(graph.sources.map(&:id)).to include(:display)
    expect(graph.sinks.map(&:id)).to include(:laptop)

    # Edge inspection
    edge = graph[:display].edges[:laptop]
    expect(edge.device).to be(:Display_1)
    expect(edge.input).to be(:hdmi)
    expect(edge).to be_nx1
    expect(edge).not_to be_nxn

    # Creation from a signal map
    graph = Aca::Router::SignalGraph.from_map(
        Display_1: {
            hdmi: :Switcher_1__1
        },
        Display_2: {
            hdmi: :Switcher_1__2
        },
        Display_3: {
            display_port: :Switcher_2
        },
        Switcher_1: [:Laptop_1, :Laptop_2, :Switcher_2],
        Switcher_2: {
            usbc: :Laptop_3,
            wireless: :Wireless
        }
    )

    expect(graph.sources.map(&:id)).to \
        contain_exactly(:Display_1, :Display_2, :Display_3)

    expect(graph.sinks.map(&:id)).to \
        contain_exactly(:Laptop_1, :Laptop_2, :Laptop_3, :Wireless)

    # Path finding
    routes = graph.sources.map(&:id).map { |id| [id, graph.dijkstra(id)] }.to_h
    expect(routes[:Display_1].distance_to[:Laptop_1]).to be(2)
    expect(routes[:Display_1].distance_to[:Laptop_3]).to be(3)
    expect(routes[:Display_3].distance_to[:Laptop_1]).to be_infinite
    expect(routes[:Display_3].distance_to[:Laptop_3]).to be(2)
end
