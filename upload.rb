require 'zip'
require 'httparty'

FHIR_SERVER = 'http://localhost:8080/plan-net/fhir'
# FHIR_SERVER = 'https://api.logicahealth.org/DVJan21CnthnPDex/open'

def upload_plan_net_resources
  file_paths = [
    File.join(__dir__, 'conformance', '*', '*.json'),
  ]

  resources = {}

  if ARGV.length > 0
    # sample data directory provided through arguments
    file_paths.append(File.join(__dir__, ARGV[0], 'output', '**', '*.json'))
  else
    # Default sample data directory
    file_paths.append(File.join(__dir__, '..', 'pdex-plan-net-sample-data', 'output', '**', '*.json'))
  end

  filenames = file_paths.flat_map do |file_path|
    Dir.glob(file_path)
      .select { |filename| filename.end_with? '.json' }
  end
  puts "#{filenames.length} resources to upload"
  old_retry_count = filenames.length

  loop do
    filenames_to_retry = []
    filenames.each_with_index do |filename, index|
      start = Time.now
      # puts "Parsing #{filename}"
      resource = JSON.parse(File.read(filename), symbolize_names: true)
      parse_finish = Time.now
      # puts "parsing time: #{parse_finish - start}"

      # aggregate resources
      resources[resource[:resourceType]] = [] unless resources.key?(resource[:resourceType])
      resources[resource[:resourceType]].push(resource)

      if resources[resource[:resourceType]].length() > 200
        upload_start = Time.now
        response = upload_resources(resource[:resourceType], resources[resource[:resourceType]])
        upload_finish = Time.now
        puts "upload time: #{upload_finish - upload_start}"
        resources[resource[:resourceType]] = [] unless !response.success?
        puts response unless response.success?
        filenames_to_retry << filename unless response.success?
      end

      if index % 100 == 0
        puts index
      end
      finish = Time.now

      execution_time = finish - start
      # puts "execution time: #{execution_time}"
    end

    resources.each do |key, value|
      upload_start = Time.now
      response = upload_resources(key, value)
      upload_finish = Time.now
      puts "upload time: #{upload_finish - upload_start}"
      resources[key] = [] unless !response.success?
      puts response unless response.success?
      filenames_to_retry << filename unless response.success?
    end

    break if filenames_to_retry.empty?
    retry_count = filenames_to_retry.length
    if retry_count == old_retry_count
      puts "Unable to upload #{retry_count} resources:"
      puts filenames.join("\n")
      break
    end
    puts "#{retry_count} resources to retry"
    filenames = filenames_to_retry
    old_retry_count = retry_count
  end
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
    bundle_resource = {
      :resource => resource,
      :request => {
        :method => "POST",
        :url => resource_type,
      }
    }

    bundle[:entry] << bundle_resource
  end

  HTTParty.post(
    "#{FHIR_SERVER}",
    body: bundle.to_json,
    headers: { 'Content-Type': 'application/json' }
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
