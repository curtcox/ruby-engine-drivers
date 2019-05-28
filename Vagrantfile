# frozen_string_literal: true

# Local path to the drivers repo that you would like to use.
DRIVERS_PATH = './'

# Local path to the front-ends to have available.
WWW_PATH = nil

Vagrant.configure('2') do |config|
    config.vm.define 'ACAEngine'

    config.vm.box = 'acaengine/dev-env'

    config.vm.synced_folder DRIVERS_PATH, '/etc/aca/aca-device-modules' \
        unless DRIVERS_PATH.nil?

    config.vm.synced_folder WWW_PATH, '/etc/aca/www' \
        unless WWW_PATH.nil?
end
