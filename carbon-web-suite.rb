require 'sinatra'
require 'faraday'
require 'yaml'

GATHER_COMMAND="/home/matt/Documents/GitHub/flight-gather/bin/gather"

system_data = YAML.load(`#{GATHER_COMMAND} show`)

get '/' do
  erb :home, :locals => {:test => system_data}
end
