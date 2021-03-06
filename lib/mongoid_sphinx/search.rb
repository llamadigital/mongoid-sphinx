require 'zlib'
require 'ostruct'

module MongoidSphinx
  def self.default_client(options={})
    MongoidSphinx::Configuration.instance.client.tap do |client|
      client.match_mode = options[:match_mode] || :extended
      client.limit = options[:limit] if options.key?(:limit)
      client.max_matches = options[:max_matches] if options.key?(:max_matches)

      if options.key?(:sort_by)
        client.sort_mode = :extended
        client.sort_by = options[:sort_by]
      end

      if options.key?(:with)
        options[:with].each do |key, value|
          client.filters << Riddle::Client::Filter.new(key.to_s, value.is_a?(Range) ? value : value.to_a, false)
        end
      end

      if options.key?(:without)
        options[:without].each do |key, value|
          client.filters << Riddle::Client::Filter.new(key.to_s, value.is_a?(Range) ? value : value.to_a, true)
        end
      end

      client.index_weights = options[:index_weights] if options.key?(:index_weights)

      if classes = options[:class]
        classes = Array(classes).map{ |klass| class_filter(klass) }
        client.filters << Riddle::Client::Filter.new('class_filter', classes, false)
      end
    end
  end

  def self.extract_index_weights(classes)
    names = extract_index_names(classes)
    Hash[names.zip([1]*names.length)]
  end

  def self.extract_index_names(classes)
    classes.map(&:index_names).flatten
  end

  def self.class_filter(klass)
    Zlib::crc32(klass.to_s) & 0xffffffff
  end

  def self.search(query, options = {})
    client = default_client(options)
    indexes =
      if options[:index]
        options[:index]
      elsif options[:class]
        extract_index_names(Array(options[:class])).join(',')
      else
        '*'
      end
    results = client.query(query, indexes)
    process_results(results)
  end

  def self.excerpts(words, docs, index, options = {})
    client = default_client(options)
    client.excerpts(options.merge({words:words, docs:docs, index:index}))
  end

  def self.search_ids(id_range, options = {})
    client = MongoidSphinx::Configuration.instance.client

    if id_range.is_a?(Range)
      client.id_range = id_range
    elsif id_range.is_a?(Fixnum)
      client.id_range = id_range..id_range
    else
      return []
    end

    client.match_mode = :extended
    client.limit = options[:limit] if options.key?(:limit)
    client.max_matches = options[:max_matches] if options.key?(:max_matches)

    if options.key?(:index_weights)
      client.index_weights = options[:index_weights]
    elsif options[:class]
      client.index_weights = extract_index_weights(Array(options[:class]))
    end

    if classes = options[:class]
      classes = Array(classes).map{ |klass| class_filter(klass) }
      client.filters << Riddle::Client::Filter.new('class_filter', classes, false)
    end

    results = client.query('*', options[:index] || '*')
    process_results(results)
  end

  def self.process_results(results)
    if results and results[:status] == 0 and (matches = results[:matches])
      matches.map do |row|
        class_name = row.fetch(:attributes,{}).fetch('class_name',nil)
        OpenStruct.new(sphinx_id:row[:doc], sphinx_weight:row[:weight], class_name:class_name) if row[:doc]
      end.compact
    else
      []
    end
  end
end
