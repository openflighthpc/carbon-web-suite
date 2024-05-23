require 'sinatra'
require 'faraday'
require 'yaml'

config = YAML.load_file(File.join(__dir__, 'etc/config.yml')) || {}

HUNTER_DIR = config['hunter_dir'] || '/opt/flight/opt/hunter/'
BOAVIZTA_URL = config['boavizta_url'] || 'https://api.boavizta.openflighthpc.org'
LOCATION = config['location'] || 'GBR'

def boavizta
  @boavizta ||= Faraday.new(BOAVIZTA_URL)
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
  erb :home, :locals => {:nodes => nodes}
end
