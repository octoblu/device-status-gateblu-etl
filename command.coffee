_ = require 'lodash'
url = require 'url'
debug = require('debug')('device-status-gateblu:command')
async = require 'async'
moment = require 'moment'
request = require 'request'
ElasticSearch = require 'elasticsearch'

QUERY = require './query.json'

class Command
  constructor : ->
    sourceElasticsearchUrl       = process.env.SOURCE_ELASTICSEARCH_URL ? 'localhost:9200'
    @destinationElasticsearchUrl = process.env.DESTINATION_ELASTICSEARCH_URL ? 'localhost:9200'
    @captureRangeInMinutes       = process.env.CAPTURE_RANGE_IN_MINUTES

    @sourceElasticsearch = new ElasticSearch.Client host: sourceElasticsearchUrl

  run: =>
    debug 'running...'
    @search @query(), (error, result) =>
      throw error if error?

      deployments = @process @normalize result
      async.each deployments, @update, (error) =>
        throw error if error?
        debug 'finished....maybe?'
        process.exit 0

  query: =>
    return QUERY unless @captureRangeInMinutes?

    captureSince = moment().subtract parseInt(@captureRangeInMinutes), 'minutes'

    query = _.cloneDeep QUERY
    query.aggs.addGatebluDevice.filter.and.push({
      range:
        _timestamp:
          gte: captureSince
    })

    return query

  update: (deployment, callback) =>
    debug 'updating with....', deployment
    uri = url.format
      protocol: 'http'
      host: @destinationElasticsearchUrl
      pathname: "/gateblu_device_add_history/event/#{deployment.deploymentUuid}"

    request.put uri, json: deployment, (error, response, body) =>
      debug 'got error updating public es', error if error
      debug 'got error updating public es', new Error(JSON.stringify body) if response.statusCode >= 300
      return callback error if error?
      return callback new Error(JSON.stringify body) if response.statusCode >= 300
      callback null

  search: (body, callback=->) =>
    @sourceElasticsearch.search({
      index: 'device_status_gateblu'
      type:  'event'
      search_type: 'count'
      body:  body
    }, callback)

  normalize: (result) =>
    debug 'got result', result
    buckets = result.aggregations.addGatebluDevice.group_by_deploymentUuid.buckets
    _.map buckets, (bucket) =>
      {
        deploymentUuid: bucket.key
        beginTime: bucket.beginRecord.beginTime.value
        endTime:   bucket.endRecord.endTime.value
        workflow: 'add-device'
      }

  process: (deployments) =>
    _.map deployments, (deployment) =>
      {workflow, deploymentUuid, beginTime, endTime} = deployment

      formattedBeginTime = null
      formattedBeginTime = moment(beginTime).toISOString() if beginTime?
      formattedEndTime = null
      formattedEndTime = moment(endTime).toISOString() if endTime?

      elapsedTime = null
      elapsedTime = endTime - beginTime if beginTime? && endTime?

      {
        deploymentUuid: deploymentUuid
        workflow: workflow
        beginTime: formattedBeginTime
        endTime: formattedEndTime
        elapsedTime: elapsedTime
        success: endTime?
      }

command = new Command()
command.run()
