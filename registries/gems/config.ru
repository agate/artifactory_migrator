require 'fileutils'
require 'rubygems'
require 'geminabox'

FileUtils.mkdir_p 'data'
Geminabox.data = './data'
run Geminabox::Server
