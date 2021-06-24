require 'zip'
require 'httparty'

NUM_THREADS = 1
BATCH_SIZE = 60
FHIR_SERVER = 'http://localhost:8080/plan-net/fhir'
# FHIR_SERVER = 'https://api.logicahealth.org/DVJan21CnthnPDex/open'

def upload_plan_net_resources
  file_paths = [
    # File.join(__dir__, 'conformance', '*', '*.json'),
  ]

  if ARGV.length > 0
    # sample data directory provided through arguments
    file_paths.append(File.join(__dir__, ARGV[0], 'output', '**', '*.json'))
  else
    # Default sample data directory
    file_paths.append(File.join(__dir__, '..', 'pdex-plan-net-sample-data', 'output', '**', '*.json'))
  end

  filenames = Queue.new
  file_paths.flat_map do |file_path|
    Dir.glob(file_path).each do |filename| 
      filenames.push(filename) if filename.end_with? '.json'
    end
  end
  puts "#{filenames.length} resources to upload"
  old_retry_count = filenames.length

  filenames_to_retry = Queue.new
  @threads = Array.new(NUM_THREADS) do
    Thread.new do
      resources = {}

      until filenames.empty?
        # This will remove the first object from @queue
        filename = filenames.pop

        start = Time.now
        # puts "Parsing #{filename}"
        resource = JSON.parse(File.read(filename), symbolize_names: true)
        parse_finish = Time.now

        # aggregate resources
        resources[resource[:resourceType]] = [] unless resources.key?(resource[:resourceType])
        resources[resource[:resourceType]].push(resource)

        if resources[resource[:resourceType]].length() >= BATCH_SIZE
          puts "uploading batch of #{resources[resource[:resourceType]].length()} #{resource[:resourceType]} resources"
          upload_start = Time.now
          response = upload_resources(resource[:resourceType], resources[resource[:resourceType]])
          upload_finish = Time.now
          puts "upload time: #{upload_finish - upload_start}"
          resources[resource[:resourceType]] = [] unless !response.success?
          puts response unless response.success?
          filenames_to_retry << filename unless response.success?
        end
        finish = Time.now

        execution_time = finish - start
        # puts "execution time: #{execution_time}"
      end

      resources.each do |key, value|
        puts "uploading last batch of #{key}"
        upload_start = Time.now
        response = upload_resources(key, value)
        upload_finish = Time.now
        puts "upload time: #{upload_finish - upload_start}"
        resources[key] = [] unless !response.success?
        puts response unless response.success?
        filenames_to_retry << filename unless response.success?
      end
    end
  end

  begin
    @threads.each(&:join)
  ensure
    # TODO
  end

  puts "#{filenames_to_retry.length} resources to retry" unless filenames_to_retry.empty?
end

def upload_resource(resource)
  resource_type = resource[:resourceType]
  resource[:status] = 'active' if resource_type == 'SearchParameter'
  id = resource[:id]
  HTTParty.put(
    "#{FHIR_SERVER}/#{resource_type}/#{id}",
    body: resource.to_json,
    headers: { 'Content-Type': 'application/json' }
  )
end

def upload_resources(resource_type, resources)
  bundle = {
    :resourceType => "Bundle",
    :id => "bundle-transaction",
    :type => "transaction",
    :entry => [],
  }

  resources.each do |resource|
    puts resource
    bundle_resource = {
      :resource => resource,
      :request => {
        :method => "PUT",
        :url => "#{resource_type}/#{resource[:id]}",
      }
    }

    bundle[:entry] << bundle_resource
  end

  HTTParty.post(
    "#{FHIR_SERVER}",
    body: bundle.to_json,
    headers: { 'Content-Type': 'application/json', 'Prefer': 'return=minimal' },
    timeout: 120
  )
end

def execute_transaction(transaction)

  HTTParty.post(
    FHIR_SERVER,
    body: transaction.to_json,
    headers: { 'Content-Type': 'application/json' }
  )
end

upload_plan_net_resources
