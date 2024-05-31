require 'sinatra'
require 'faraday'
require 'yaml'

require_relative 'lib/emission_conversion'

config = YAML.load_file(File.join(__dir__, 'etc/config.yml')) || {}

set :bind, '0.0.0.0'
set :port, config['port'] || 80

HUNTER_DIR = config['hunter_dir'] || '/opt/flight/opt/hunter/'
BOAVIZTA_URL = config['boavizta_url'] || 'https://api.boavizta.openflighthpc.org'
LEADERBOARD_URL = config['leaderboard_url'] || 'https://leaderboard.openflighthpc.org'
LOCATION = config['location'] || 'GBR'
AUTH_TOKEN = ''

def boavizta
  @boavizta ||= Faraday.new(BOAVIZTA_URL)
end

def leaderboard
  @leaderboard ||= Faraday.new(LEADERBOARD_URL)
end

def carbon_for_load(node, cpu_load)
  response = boavizta.post('/v1/server/') do |req|
    req.headers[:content_type] = 'application/json'
    req.params[:verbose] = false
    req.params[:criteria] = 'gwp'
    req.body = JSON.pretty_generate(
      {
        "model": {
          "type": "rack"
        },
        "configuration": {
          "cpu": {
            "units": node.cpus.units,
            "core_units": node.cpus.cores_per_cpu,
            "name": node.cpus.cpu_data.CPU0.model
          },
          "ram": [{
            "units": node.ram.units,
            "capacity": node.ram.capacity_per_unit
          }],
        },
        "usage": {
          "usage_location": LOCATION,
          "hours_use_time": 1,
          "hours_life_time": 1,
          "time_workload": cpu_load
        }
      }
    )
  end
  JSON.parse(response.body).dig(*%w[impacts gwp use value]) * 1000
end

def send_data(node, auth_token)
  response = leaderboard.post('/add-record') do |req|
    req.headers[:content_type] = 'application/json'
    req.headers['Authorization'] = auth_token unless auth_token.to_s.empty?
    req.body = JSON.generate(
      {
        "device_id": node.uuid,
        "platform": node.platform,
        "cpus": node.cpus.units,
        "cores_per_cpu": node.cpus.cores_per_cpu,
        "cpu_name": node.cpus.cpu_data.CPU0.model,
        "ram_units": node.ram.units,
        "ram_capacity_per_unit": node.ram.capacity_per_unit,
        "disk": node.disk,
        "instance_type": "",
        "current_load": 50,
        "location": LOCATION,
        "tags": []
      }
    )
  end

  response.body
end

parsed_dir = File.join(HUNTER_DIR, '/var/parsed')

raise "The specified directory '#{HUNTER_DIR}' has no associated parsed nodes." if !File.directory?(parsed_dir)

nodes = []
Dir.each_child(parsed_dir) do |file|
  hunter_data = YAML.load_file(File.join(parsed_dir, file))
  data = JSON.parse(YAML.load(hunter_data['content']).to_json, object_class: OpenStruct) # Yes, this is how it's done.
  data.label = hunter_data['label']
  nodes << data
end

get '/' do
  total_max = nodes.map { |node| carbon_for_load(node, 100) }.sum
  year_emissions = (total_max * 8.76).round(2)
  emission_conversions = {}.tap do |ec|
    ec[:driving] = (year_emissions * EmissionConversion::DRIVE).floor
    ec[:big_mac] = (year_emissions * EmissionConversion::BIG_MAC).floor
    ec[:mcplant] = (year_emissions * EmissionConversion::MCPLANT).floor
    ec[:flight] = (year_emissions * EmissionConversion::FLIGHT).floor
    ec[:netflix] = (year_emissions * EmissionConversion::NETFLIX).floor
  end

  erb :home, :locals => {:nodes => nodes, :ec => emission_conversions}
end

get '/node/:label' do
  node = nodes.find { |node| node.label == params['label'] }

  erb :node, :locals => {:node => node}
end

post '/send-data' do
  erb :send_data, :locals => {:nodes => nodes, :auth_token => params['auth_token']}
end

