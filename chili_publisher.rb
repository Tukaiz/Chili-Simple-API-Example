module ChiliPublisher
  class Server
    require 'savon'
    require './chili_publisher_uri'
    ENVI = 'tukaiz'
    USER = 'tukaiz'
    PASS = 'tukaiz_dem0'

    attr_reader :client, :session_id

    def initialize
      client
    end

    def render(object)
      @template = object.template
      # get xml from object
      xml = object.as_xml

      puts "\n\n\n\n#{xml}\n\n\n\n" unless Rails.env.test?

      response = get_document_create_temp_pdf(@template, xml)
      key = find_key(response)
      status = run_until_complete(key)
      OpenStruct.new( images:   preview_images(status[:pdf_url]),
                      pdf_url:  status[:pdf_url])
    end

    def get_item_by_name(name, resource_name = "Documents")
      response = @client.call(:resource_item_get_by_name, message: {"apiKey"=> session_id ,"resourceName" => resource_name, "itemName" => name })
      doc = Nokogiri.XML(response.body[:resource_item_get_by_name_response][:resource_item_get_by_name_result])
    end

    def get_resource_list
      response = client.call(:resource_list, message: {"apiKey" => session_id })
      doc = Nokogiri.XML(response.body[:resource_list_response][:resource_list_result])
      doc.xpath("//resources/item").map{|i| i.attr('name')}
    end

    def get_resource_tree(resource_name,parent_folder="",include_sub_directories=false,include_files=false)
      response = client.call(:resource_get_tree, message: {"apiKey" => session_id, "resourceName"=>resource_name, "parentFolder"=>parent_folder,
       "includeSubDirectories"=>include_sub_directories, "includeFiles"=>include_files })
      doc = Nokogiri.XML(response.body[:resource_get_tree_response][:resource_get_tree_result])
    end

    def get_available_doc_list
      doc= get_resource_tree("Documents","",true,true)
      doc.xpath("//item[@isFolder='false']").map{|i|
        { alias:        i.attr('id'),
          display_name: i.attr('name'),
          name:         i.attr('name'),
          height:       i.xpath("./fileInfo").attr('height').value,
          width:        i.xpath("./fileInfo").attr('width').value,
          preview:      i.attr('iconURL') }
      }
    end

    def get_document_pdf(document_id)
      # set high quality settings
      set_high_quality_export
      # DocumentCreatePDF ( string apiKey, string itemID, string settingsXML, int taskPriority );
      response = client.call(:document_create_pdf,message: {"apiKey"=>session_id, "itemID"=>document_id, "settingsXML"=>export_settings})
      # need to grab inner result, nokogiri will choke on it
      result_match=response.body[:document_create_pdf_response][:document_create_pdf_result].match(/result=\"(<.*\/>)\"/)
      result = Nokogiri.XML(result_match[1])
    end

    def get_document_create_temp_pdf(item_id,doc_xml)
      set_high_quality_export
      # used to render a document with custom information
      response = client.call(:document_create_temp_pdf, message:{"apiKey"=>session_id, "itemID"=>item_id, "docXML"=>doc_xml, "settingsXML"=>export_settings})
      result_match=response.body[:document_create_temp_pdf_response][:document_create_temp_pdf_result].match(/result=\"(<.*\/>)\"/)
      result = Nokogiri.XML(result_match[1])
    end

    def search_by(resource_name="Documents",name="")
      doc = api_call("resource_search", {"apiKey"=>session_id, "resourceName"=>resource_name, "name"=>name})
    end
    ## Document Utils
    def get_task_list(running=true, waiting=true, finished=true)
      doc = api_call("tasks_get_list", {"apiKey"=>session_id, "includeRunningTasks"=>running,"includeWaitingTasks"=>waiting,"includeFinishedTasks"=>finished})
    end
    #DocumentGetVariableDefinitions
    def get_document_variable_definitions(item_id)
      doc = api_call("document_get_variable_definitions", {"apiKey"=>session_id, "itemID"=>item_id})
    end
    #DocumentGetVariableValues
    def get_document_variable_values(item_id)
      doc = api_call("document_get_variable_values", {"apiKey"=>session_id, "itemID"=>item_id})
    end
    #DocumentSetVariableDefinitions
    def set_document_variable_definitions(item_id, xml)
      doc = api_call("document_set_variable_definitions", {"apiKey"=>session_id, "itemID"=>item_id, "varXML"=>xml})
    end
    #DocumentSetVariableValues
    def set_document_variable_values(item_id, xml)
      doc = api_call("document_set_variable_values", {"apiKey"=>session_id, "itemID"=>item_id, "varXML"=>xml})
    end

    def get_document_info(itemID, extended=false)
      response = client.call(:document_get_info, message: {"apiKey"=>session_id, "itemID"=>itemID, "extended"=>extended})
      doc = Nokogiri.XML(response.body[:document_get_info_response][:document_get_info_result])
    end

    def get_authentication_code
      response = client.call(:get_authentication_code, message: {"SessionID" => session_id})
    end

    def get_resource_xml(item_id, resource_name)
      response = client.call(:resource_item_get_xml, message: {"apiKey"=>session_id, "resourceName"=>resource_name,"itemID"=>item_id})
      # get raw xml response so Nokogiri doesnt botch it
      response.xpath("//soap:Body").xpath("chili:ResourceItemGetXMLResponse/chili:ResourceItemGetXMLResult",{"chili"=>"http://www.chili-publisher.com/"}).first.text
    end

    ## Export Settings
    def get_all_export_settings
      # PdfExportSettings
      doc = search_by("PdfExportSettings","")
      settings = doc.xpath("//searchresults/item").map{|i|i.xpath("./@name|./@id").map(&:value)}
    end

    def set_high_quality_export
      # set high quality settings
      hq_settings = get_item_by_name("BC preview 2", "PdfExportSettings")
      set_export_settings(hq_settings.xpath("//@id").first.value)
    end

    def set_export_settings(item_id=nil)
      # set first available setting if one is not provided
      item_id = get_all_export_settings.first[1] unless item_id
      @export_settings = get_resource_xml(item_id,"PdfExportSettings")
    end

private

    def client
      @client ||= Savon.client(
        wsdl: ChiliPublisherUri.url_for(path: '/CHILI/main.asmx', query: 'WSDL').to_s
      )
    end

    def authenticate
      response = client.call(:generate_api_key, message: {"environmentNameOrURL" => ENVI,"userName" => USER, "password" => PASS })
      session_id_match = response.body[:generate_api_key_response][:generate_api_key_result].match(/^.*key=\"(.*?)\".*$/)
      session_id_match ? session_id_match[1] : "" # not sure what to do if no authentication is found
    end

    def session_id
      @session_id ||= authenticate
    end

    def api_call(name, message={})
      response = client.call(name.to_sym, message: message)
      doc = Nokogiri.XML(response.body["#{name}_response".to_sym]["#{name}_result".to_sym])
    end

    def export_settings

      @export_settings ||= set_export_settings
    end

    def run_until_complete(key)
      count = 0
      while get_doc_status(key)[:progress_percent].to_i < 100 and count < 20
        count += 1
        sleep 0.8
      end
      get_doc_status(key)
    end

    def find_key(response)
      doc = Nokogiri.XML(response.body[:start_doc_response][:start_doc_result])
      doc.css("DSMDocRenderStatus").first.attr('Key')
    end

    def preview_images(pdf)
      @template.page_count.times.map {|count|
        {page: (count+1).to_s, url: pdf.gsub('.pdf', make_string(count) )} }
    end

    def make_string(int)
      ('_' + "%03d" % (int+1) +'.jpg')
    end

    def get_doc_status(key)
      response = @client.call(:get_doc_status, message: {"SessionID" => session_id, "Key" => key})
      doc = Nokogiri.XML(response.body[:get_doc_status_response][:get_doc_status_result])

      { page_count:       doc.css("DSMDocRenderStatus").first[:PageCount],
        pdf_url:          doc.css("DSMDocRenderStatus").first[:PDFUrl],
        progress_percent: doc.css("DSMDocRenderStatus").first[:LastProgressPercent],
        jpegs:            doc.css("Jpeg").map { |i|
                                                    { page: i[:Page], url: i[:Url] }
                                              }  }
    end

  end
end
