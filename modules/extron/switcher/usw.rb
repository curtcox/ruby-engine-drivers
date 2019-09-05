load File.expand_path('../base.rb', File.dirname(__FILE__))
module Extron::Switcher; end

# This moduel is for direct control of the Extron XTP T USW103
# Does not require the USW to be connected to an XTP Matrix Frame
# Output is ignored, only accepts input command

class Extron::Switcher::USW < Extron::Base
    descriptive_name 'Extron USW 103'
    generic_name :Switcher

    #
    # No need to wait as commands can be chained
    # USW103 does not take output arguement so it is ignored
    def switch(map)
        logger.debug { "switching #{map}" }
        map.each do |input, outputs|
            input = input.to_s if input.is_a?(Symbol)
            input = input.to_i if input.is_a?(String)

            outputs = Array(outputs)
            command = ''
            outputs.each do |output|
                command = "X#{input} !"
            end
            send(command)
        end
        nil
    end

    #
    # Sends copyright information
    # Then sends password prompt
    #
    def received(data, resolve, command)
        logger.debug { "Extron Matrix sent #{data}" }

        if data =~ /Login/i
            device_ready
        elsif command.present? && command[:command] == :information
            data = data.split(' ')
            return :ignore unless data.length > 1
        else
            # ACK looks like 'Etie1*1*3' 'Etiesub_input_vidio*sub_input_audio*3' (but there is no seperation so  video will always ewual audio)
            if data[0-3] == "Etie"
                input = data[5]
                sub_input = data[7]
                self["input"] = input
                self["output"] = sub_input
            else
                if data == 'E22'    # Busy! We should retry this one
                    command[:delay_on_receive] = 1 unless command.nil?
                    return :failed

                end

            end
        end

        return :success
    end
end
