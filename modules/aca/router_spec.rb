# frozen_string_literal: true

require 'json'

Orchestrator::Testing.mock_device 'Aca::Router' do
    def section(message)
        puts "\n\n#{'-' * 80}"
        puts message
        puts "\n"
    end

    SignalGraph = Aca::Router::SignalGraph

    # -------------------------------------------------------------------------
    section 'Internal graph structure'

    graph = SignalGraph.new

    # Node insertion
    graph << :test_node
    expect(graph).to include(:test_node)

    # Node access
    expect(graph[:test_node]).to be_a(SignalGraph::Node)
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


    # -------------------------------------------------------------------------
    section 'Parse from signal map'

    signal_map = JSON.parse <<-JSON
        {
            "Display_1 as Left_LCD": {
                "hdmi": "Switcher_1__1",
                "hdmi2": "SubSwitchA__1"
            },
            "Display_2 as Right_LCD": {
                "hdmi": "Switcher_1__2",
                "hdmi2": "SubSwitchB__2",
                "display_port": "g"
            },
            "Switcher_1": ["a", "b"],
            "Switcher_2 as SubSwitchA": {
                "1": "c",
                "2": "d"
            },
            "Switcher_2 as SubSwitchB": {
                "3": "e",
                "4": "f"
            }
        }
    JSON

    normalised_map = SignalGraph.normalise(signal_map)
    expect(normalised_map).to eq(
        'Display_1 as Left_LCD' => {
            'hdmi'  => 'Switcher_1__1',
            'hdmi2' => 'SubSwitchA__1'
        },
        'Display_2 as Right_LCD' => {
            'hdmi'  => 'Switcher_1__2',
            'hdmi2' => 'SubSwitchB__2',
            'display_port' => 'g'
        },
        'Switcher_1' => {
            1 => 'a',
            2 => 'b'
        },
        'Switcher_2 as SubSwitchA' => {
            1 => 'c',
            2 => 'd'
        },
        'Switcher_2 as SubSwitchB' => {
            3 => 'e',
            4 => 'f'
        }
    )

    mods = SignalGraph.extract_mods!(normalised_map)
    expect(mods).to eq(
        'Left_LCD'   => :Display_1,
        'Right_LCD'  => :Display_2,
        'Switcher_1' => :Switcher_1,
        'SubSwitchA' => :Switcher_2,
        'SubSwitchB' => :Switcher_2
    )
    expect(normalised_map).to eq(
        'Left_LCD' => {
            'hdmi'  => 'Switcher_1__1',
            'hdmi2' => 'SubSwitchA__1'
        },
        'Right_LCD' => {
            'hdmi'  => 'Switcher_1__2',
            'hdmi2' => 'SubSwitchB__2',
            'display_port' => 'g'
        },
        'Switcher_1' => {
            1 => 'a',
            2 => 'b'
        },
        'SubSwitchA' => {
            1 => 'c',
            2 => 'd'
        },
        'SubSwitchB' => {
            3 => 'e',
            4 => 'f'
        }
    )

    graph = SignalGraph.from_map(signal_map)

    expect(graph.sources.map(&:id)).to contain_exactly(:Left_LCD, :Right_LCD)

    expect(graph.sinks.map(&:id)).to contain_exactly(*(:a..:g).to_a)

    routes = graph.sources.map(&:id).map { |id| [id, graph.dijkstra(id)] }.to_h
    expect(routes[:Left_LCD].distance_to[:a]).to be(2)
    expect(routes[:Left_LCD].distance_to[:c]).to be(2)
    expect(routes[:Left_LCD].distance_to[:e]).to be_infinite
    expect(routes[:Left_LCD].distance_to[:g]).to be_infinite
    expect(routes[:Right_LCD].distance_to[:g]).to be(1)
    expect(routes[:Right_LCD].distance_to[:a]).to be(2)
    expect(routes[:Right_LCD].distance_to[:g]).to be(1)
    expect(routes[:Right_LCD].distance_to[:c]).to be_infinite


    # -------------------------------------------------------------------------
    section 'Module methods'

    exec(:load_from_map, signal_map)

    exec(:route, :a, :Left_LCD)
    nodes, = result
    nodes.map!(&:id)
    expect(nodes).to contain_exactly(:Left_LCD, :Switcher_1__1, :a)

    exec(:route, :c, :Left_LCD)
    nodes, = result
    nodes.map!(&:id)
    expect(nodes).to contain_exactly(:Left_LCD, :SubSwitchA__1, :c)

    expect { exec(:route, :e, :Left_LCD) }.to \
        raise_error('no route from e to Left_LCD')
end
