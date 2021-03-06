module DataAccessHelper
    include WatermarkHelper

    def getData(params)
        if ENV["WATERMARK"].to_s == ""
            case params.to_s
            when ->(n) { n.starts_with?("id=") }
                [Store.select(:id, :item).find(params[3..-1])].map(&:serializable_hash) rescue []
            when ->(n) { n.starts_with?("day=") }
                day_filter = params[4..-1]
                Store.where("key LIKE '%" + day_filter + "%'").select(:id, :item).to_a.map(&:serializable_hash)
            else
                Store.select(:id, :item).to_a.map(&:serializable_hash)
            end
        else
            retVal = []
            fragments = []
            if params.class.to_s != "String"
                params = params.stringify_keys.except("format", "controller", "action", "store").to_json rescue ""
            end
            if params == "{}" || params == ""
                fragments = all_fragments("")
            else
                items = []
                Store.where(id: params).pluck(:item).each { |item| items << Date.parse(JSON(item)["time"]).to_s }
                fragments = items.uniq
            end
            fragments.each do |fragment_id|
                key = get_fragment_key(fragment_id, doorkeeper_token.application_id)
                data = get_fragment(fragment_id)
                retVal += apply_watermark(data, key)
            end
            return retVal
        end
    end

    def get_provision(params, logstr)
        retVal_type = container_format
        timeStart = Time.now.utc
        retVal_data = getData(params)
        if retVal_data.nil?
            retVal_data = []
        end
        timeEnd = Time.now.utc
        content = []
        case retVal_type.to_s
        when "JSON"
            if retVal_data.count > 0
                if retVal_data.first["item"].is_a? String
                    retVal_data.each { |el| content << JSON(el["item"]) } rescue nil
                else
                    retVal_data.each { |el| content << el["item"] } rescue nil
                end
            end
            content_hash = Digest::SHA256.hexdigest(content.to_json)
        when "RDF"
            retVal_data.each { |el| content << el["item"].to_s }
            content_hash = Digest::SHA256.hexdigest(content.to_s)
        else
            content = ""
            retVal_data.each { |el| content += el["item"].to_s + "\n" } rescue ""
            content_hash = Digest::SHA256.hexdigest(content.to_s)
        end
        param_str = request.query_string.to_s

        retVal = {
            "content": content,
            "usage-policy": container_usage_policy.to_s,
            "provenance": getProvenance(content_hash, param_str, timeStart, timeEnd)
        }.stringify_keys

        createLog({
            "type": logstr,
            "scope": retVal_data.map{|h| h["id"]}.flatten.sort.to_json}, # "all (" + retVal_data.count.to_s + " records)"},
            Digest::SHA256.hexdigest(retVal.to_json))

        return retVal
    end
end