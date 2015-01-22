# encoding: utf-8

require "logstash/devutils/rspec/spec_helper"
require "logstash/filters/multiline"

describe LogStash::Filters::Multiline do

  describe "simple multiline" do
    config <<-CONFIG
    filter {
      multiline {
        periodic_flush => false
        pattern => "^\\s"
        what => previous
      }
    }
    CONFIG

    sample [ "hello world", "   second line", "another first line" ] do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2
      insist { subject[0]["message"] } == "hello world\n   second line"
      insist { subject[1]["message"] } == "another first line"
    end
  end

  describe "multiline using grok patterns" do
    config <<-CONFIG
    filter {
      multiline {
        pattern => "^%{NUMBER} %{TIME}"
        negate => true
        what => previous
      }
    }
    CONFIG

    sample [ "120913 12:04:33 first line", "second line", "third line" ] do
      insist { subject["message"] } ==  "120913 12:04:33 first line\nsecond line\nthird line"
    end
  end

  describe "multiline safety among multiple concurrent streams" do
    config <<-CONFIG
      filter {
        multiline {
          pattern => "^\\s"
          what => previous
        }
      }
    CONFIG

    count = 50
    stream_count = 3

    # first make sure to have starting lines for all streams
    eventstream = stream_count.times.map do |i|
      stream = "stream#{i}"
      lines = [LogStash::Event.new("message" => "hello world #{stream}", "host" => stream, "type" => stream)]
      lines += rand(5).times.map do |n|
        LogStash::Event.new("message" => "   extra line in #{stream}", "host" => stream, "type" => stream)
      end
    end

    # them add starting lines for random stream with sublines also for random stream
    eventstream += (count - stream_count).times.map do |i|
      stream = "stream#{rand(stream_count)}"
      lines = [LogStash::Event.new("message" => "hello world #{stream}", "host" => stream, "type" => stream)]
      lines += rand(5).times.map do |n|
        stream = "stream#{rand(stream_count)}"
        LogStash::Event.new("message" => "   extra line in #{stream}", "host" => stream, "type" => stream)
      end
    end

    events = eventstream.flatten.map{|event| event.to_hash}

    sample events do
      expect(subject).to be_a(Array)
      insist { subject.size } == count

      subject.each_with_index do |event, i|
        insist { event["type"] == event["host"] } == true
        stream = event["type"]
        insist { event["message"].split("\n").first } =~ /hello world /
        insist { event["message"].scan(/stream\d/).all?{|word| word == stream} } == true
      end
    end
  end


  describe "multiline add/remove tags and fields only when matched" do
    config <<-CONFIG
      filter {
        mutate {
          add_tag => "dummy"
        }
        multiline {
          add_tag => [ "nope" ]
          remove_tag => "dummy"
          add_field => [ "dummy2", "value" ]
          pattern => "an unlikely match"
          what => previous
        }
      }
    CONFIG

    sample [ "120913 12:04:33 first line", "120913 12:04:33 second line" ] do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2

      subject.each do |s|
        insist { s["tags"].include?("nope")  } == true
        insist { s["tags"].include?("dummy") } == false
        insist { s.include?("dummy2") } == true
      end
    end
  end

  describe "regression test for GH issue #1258" do
    config <<-CONFIG
      filter {
        multiline {
          pattern => "^\s"
          what => "next"
        }
      }
    CONFIG

    sample [ "  match", "nomatch" ] do
      expect(subject).to be_a(LogStash::Event)
      insist { subject["message"] } == "  match\nnomatch"
    end
  end

  describe "multiple match/nomatch" do
    config <<-CONFIG
      filter {
        multiline {
          pattern => "^\s"
          what => "next"
        }
      }
    CONFIG

    sample ["  match1", "nomatch1", "  match2", "nomatch2"] do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2
      insist { subject[0]["message"] } == "  match1\nnomatch1"
      insist { subject[1]["message"] } == "  match2\nnomatch2"
    end
  end

  describe "keep duplicates by default on message field" do
    config <<-CONFIG
      filter {
        multiline {
          pattern => "^\s"
          what => "next"
        }
      }
    CONFIG

    sample ["  match1", "  match1", "nomatch1", "  1match2", "  2match2", "  1match2", "nomatch2"] do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2
      insist { subject[0]["message"] } == "  match1\n  match1\nnomatch1"
      insist { subject[1]["message"] } == "  1match2\n  2match2\n  1match2\nnomatch2"
    end
  end

  describe "remove duplicates using :allow_duplicates => false on message field" do
    config <<-CONFIG
      filter {
        multiline {
          allow_duplicates => false
          pattern => "^\s"
          what => "next"
        }
      }
    CONFIG

    sample ["  match1", "  match1", "nomatch1", "  1match2", "  2match2", "  1match2", "nomatch2"] do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2
      insist { subject[0]["message"] } == "  match1\nnomatch1"
      insist { subject[1]["message"] } == "  1match2\n  2match2\nnomatch2"
    end
  end

  describe "keep duplicates only on @source field" do
    config <<-CONFIG
      filter {
        multiline {
          source => "foo"
          pattern => "^\s"
          what => "next"
        }
      }
    CONFIG

    sample [
      {"message" => "bar", "foo" => "  match1"},
      {"message" => "bar", "foo" => "  match1"},
      {"message" => "baz", "foo" => "nomatch1"},
      {"foo" => "  1match2"},
      {"foo" => "  2match2"},
      {"foo" => "  1match2"},
      {"foo" => "nomatch2"}
    ] do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2
      insist { subject[0]["foo"] } == "  match1\n  match1\nnomatch1"
      insist { subject[0]["message"] } == ["bar", "baz"]
      insist { subject[1]["foo"] } == "  1match2\n  2match2\n  1match2\nnomatch2"
    end
  end

  describe "fix dropped duplicated lines" do
    # as reported in https://github.com/logstash-plugins/logstash-filter-multiline/issues/3

    config <<-CONFIG
      filter {
        multiline {
          pattern => "^START"
          what => "previous"
          negate=> true
        }
      }
    CONFIG

    messages = [
      "START",
      "<Tag1 Id=\"1\">",
        "<Tag2>Foo</Tag2>",
      "</Tag1>",
      "<Tag1 Id=\"2\">",
        "<Tag2>Foo</Tag2>",
      "</Tag1>",
      "START",
    ]
    sample messages do
      expect(subject).to be_a(Array)
      insist { subject.size } == 2
      insist { subject[0]["message"] } == messages[0..-2].join("\n")
    end
  end


 describe "integrations" do

    it "should merge messages arrays as Java ArrayList from json codec using JrJackson" do

      config = <<-CONFIG
        input {
          generator {
            lines => [
              '{"message": ["first", ">>second"]}',
              '{"message": [">>third", ">>fourth"]}'
            ]
            count => 1
            codec => "json"
          }
        }
      CONFIG

      # first generate events from generator input with json codec with array messages
      # so that JrJackson generates Java ArrayList objects

      events = []
      queue = Queue.new
      pipeline = LogStash::Pipeline.new(config)
      pipeline.instance_eval do
        @output_func = lambda { |event| queue << event }
      end
      runner = Thread.new { pipeline.run }
      sleep 0.1 while !pipeline.ready?

      events << queue.pop
      events << queue.pop

      pipeline.shutdown
      runner.join

      expect(events.size).to eq(2)

      # next run these 2 events into the multiline filter.
      # before v0.1.4 this would trigger NoMethodError: undefined method `|' for #<Java::JavaUtil::ArrayList
      # we don't want to run this filter through the pipeline because the filter worker rescues
      # all exceptions.

      filter = LogStash::Filters::Multiline.new({"pattern" => "^>>.*", "what" => "previous", "periodic_flush" => false })
      filter.register

      results = []
      events.each do |event|
        filter.filter(event) { |new_event| results << new_event }
        results.unshift(event) unless event.cancelled?
      end
      results += filter.flush(:final => true)

      expect(results[0]["message"]).to eq("first\n>>second\n>>third\n>>fourth")
    end
  end

end
